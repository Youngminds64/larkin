// Streaming card replies: the Host, not the model, delivers the reply.
//
// After the model polls a chat/thread Inbox message, every user-facing text delta
// of that Runtime turn is streamed into one Feishu CardKit card that replies to
// the polled message (in the same topic when the source is a thread). The card is
// opened lazily on the first text so an intentionally silent turn posts nothing.
// When the turn fails after a poll, the Host posts or finishes the card with a
// visible failure instead of leaving the user without a reply.
//
// The model's current reply anchor is the canonical Inbox `last_source`, which a
// successful scoped poll sets and the Runtime turn boundary clears. A poll is a
// tool call, so the source is re-resolved after tool activity and at a bounded
// interval; text written before any poll has no anchor and is not delivered.
//
// The mode is the global `replyMode` in Larkin config (dashboard 全局设置), else LARKIN_REPLY_MODE;
// `cli` restores the legacy model-driven `+messages-reply`.

import type { NormalizedRuntimeEvent } from "../runtime/runtime-contracts.js";

export { replyModeFromEnv, type ReplyMode } from "../platform/reply-mode.js";

export interface StreamReplySource { deliveryTarget: string; deliveryAnchor: string }

export interface MarkdownStreamController {
  setContent(full: string): Promise<void>;
}

export interface StreamReplyChannel {
  stream(
    to: string,
    input: { markdown: (controller: MarkdownStreamController) => Promise<void> },
    opts?: { replyTo?: string; replyInThread?: boolean },
  ): Promise<{ messageId: string }>;
}

export interface StreamReplyOptions {
  channelFor(agentId: string): StreamReplyChannel | undefined;
  resolveSource(agentId: string): StreamReplySource | null;
  log?: (...parts: unknown[]) => void;
  /** Minimum gap between card content updates. */
  throttleMs?: number;
  /** Re-read the Inbox source at least this often while text is streaming. */
  resolveIntervalMs?: number;
  now?: () => number;
}

export const STREAM_REPLY_INITIAL_TEXT = "正在回复…";
export const STREAM_REPLY_FAILURE_TEXT = "处理这条消息时出错了，没能完成回复。请稍后重试。";

interface ReplyAddress { key: string; chatId: string; anchor: string; inThread: boolean }

/** Map a canonical Inbox source to a card address; only IM chat/thread sources with a real om_ anchor qualify. */
export function replyAddressOf(source: StreamReplySource | null): ReplyAddress | null {
  if (!source || !/^om_[A-Za-z0-9_-]+$/.test(source.deliveryAnchor)) return null;
  const chat = /^chat:([^:]+)$/.exec(source.deliveryTarget);
  if (chat) return { key: `${source.deliveryTarget}#${source.deliveryAnchor}`, chatId: chat[1], anchor: source.deliveryAnchor, inThread: false };
  const thread = /^thread:([^:]+):([^:]+)$/.exec(source.deliveryTarget);
  if (thread) return { key: `${source.deliveryTarget}#${source.deliveryAnchor}`, chatId: thread[1], anchor: source.deliveryAnchor, inThread: true };
  return null;
}

class CardReply {
  text = "";
  private controller: MarkdownStreamController | null = null;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private lastPushAt = 0;
  private settle: { resolve(): void; reject(error: Error): void } | null = null;
  private finished = false;
  private failure: string | undefined;
  readonly done: Promise<void>;

  constructor(readonly address: ReplyAddress, channel: StreamReplyChannel, private readonly throttleMs: number,
    private readonly now: () => number, log: (...parts: unknown[]) => void) {
    this.done = channel.stream(address.chatId, {
      markdown: (controller) => new Promise<void>((resolve, reject) => {
        this.controller = controller;
        this.settle = { resolve, reject };
        if (this.finished) this.close();
        else this.push();
      }),
    }, { replyTo: address.anchor, replyInThread: address.inThread })
      .then(({ messageId }) => {
        log(`流式卡片已发送 anchor=${address.anchor} message=${messageId} chars=${this.text.length}`);
      }, (error: unknown) => {
        log(`流式卡片回复失败 anchor=${address.anchor}: ${error instanceof Error ? error.message : String(error)}`);
      });
  }

  append(text: string): void {
    if (this.finished || !text) return;
    this.text += text;
    this.schedule();
  }

  /** Close the stream; `failure` keeps the partial text and lets the SDK mark it interrupted. */
  finish(failure?: string): void {
    if (this.finished) return;
    this.finished = true;
    if (failure && !this.text.trim()) this.text = failure;
    this.failure = failure;
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    if (this.settle) this.close();
  }

  private schedule(): void {
    if (this.timer || !this.controller) return;
    const wait = Math.max(0, this.lastPushAt + this.throttleMs - this.now());
    this.timer = setTimeout(() => { this.timer = null; this.push(); }, wait);
    this.timer.unref?.();
  }

  private push(): void {
    if (!this.controller || !this.text) return;
    this.lastPushAt = this.now();
    void this.controller.setContent(this.text).catch(() => { /* the SDK records streaming failure itself */ });
  }

  private close(): void {
    const settle = this.settle!;
    this.settle = null;
    const finalText = this.text;
    const controller = this.controller!;
    void controller.setContent(finalText || " ").catch(() => {}).then(() => {
      if (this.failure && finalText !== this.failure) settle.reject(new Error(this.failure));
      else settle.resolve();
    });
  }
}

interface TurnState {
  card: CardReply | null;
  needsResolve: boolean;
  lastResolveAt: number;
  pendingBreak: boolean;
  /** Address of the latest poll even before any text arrives; used for failure replies. */
  lastAddress: ReplyAddress | null;
  failed: string | null;
  /** Diagnostics: assistant text seen this turn and cards opened for it. */
  textChars: number;
  cards: number;
  tools: number;
  /** Last Inbox source read for this turn, raw, so a non-card source is visible in the summary. */
  source: string;
}

export class StreamReplyCoordinator {
  private readonly turns = new Map<string, TurnState>();
  private readonly log: (...parts: unknown[]) => void;
  private readonly throttleMs: number;
  private readonly resolveIntervalMs: number;
  private readonly now: () => number;
  private readonly pending = new Set<Promise<void>>();

  constructor(private readonly options: StreamReplyOptions) {
    this.log = options.log ?? (() => {});
    this.throttleMs = options.throttleMs ?? 250;
    this.resolveIntervalMs = options.resolveIntervalMs ?? 500;
    this.now = options.now ?? Date.now;
  }

  observe(agentId: string, event: NormalizedRuntimeEvent): void {
    if (event.type === "turn-start") {
      this.endTurn(agentId);
      this.turns.set(agentId, this.freshTurn());
      return;
    }
    const turn = this.turns.get(agentId);
    if (event.type === "turn-end" || event.type === "closed") {
      if (!turn) return;
      if (event.type === "closed") turn.failed ??= STREAM_REPLY_FAILURE_TEXT;
      this.endTurn(agentId);
      return;
    }
    if (!turn) return;
    if (event.type === "activity" && event.activity === "tool") {
      turn.needsResolve = true;
      turn.tools += 1;
      if (turn.card?.text) turn.pendingBreak = true;
      return;
    }
    if (event.type === "error" || (event.type === "input-error" && event.willRetry !== true)) {
      turn.failed = STREAM_REPLY_FAILURE_TEXT;
      return;
    }
    if (event.type === "text-delta") this.onText(agentId, turn, event.text, event.newBlock === true);
  }

  /** Resolve once every card opened so far has finished streaming (tests and shutdown). */
  async idle(): Promise<void> {
    while (this.pending.size) await Promise.all([...this.pending]);
  }

  private freshTurn(): TurnState {
    return { card: null, needsResolve: true, lastResolveAt: 0, pendingBreak: false, lastAddress: null, failed: null, textChars: 0, cards: 0, tools: 0, source: "none" };
  }

  private onText(agentId: string, turn: TurnState, text: string, newBlock: boolean): void {
    if (!text) return;
    turn.textChars += text.length;
    const address = this.currentAddress(agentId, turn);
    if (!address) {
      if (turn.card) { turn.card.finish(); turn.card = null; }
      return;
    }
    if (!turn.card || turn.card.address.key !== address.key) {
      turn.card?.finish();
      turn.card = this.open(agentId, address);
      if (!turn.card) return;
      turn.cards += 1;
      turn.pendingBreak = false;
    } else if ((newBlock || turn.pendingBreak) && turn.card.text && !turn.card.text.endsWith("\n\n")) {
      turn.card.append(turn.card.text.endsWith("\n") ? "\n" : "\n\n");
    }
    turn.pendingBreak = false;
    turn.card.append(text);
  }

  private currentAddress(agentId: string, turn: TurnState): ReplyAddress | null {
    const due = turn.needsResolve || !turn.card || this.now() - turn.lastResolveAt >= this.resolveIntervalMs;
    if (!due) return turn.card!.address;
    turn.needsResolve = false;
    turn.lastResolveAt = this.now();
    let source: StreamReplySource | null = null;
    try { source = this.options.resolveSource(agentId); }
    catch (error) { this.log(`读取当前 Inbox source 失败 agent=${agentId}: ${error instanceof Error ? error.message : String(error)}`); }
    const address = replyAddressOf(source);
    turn.source = source ? `${source.deliveryTarget}#${source.deliveryAnchor}` : "none";
    if (address) turn.lastAddress = address;
    return address;
  }

  private open(agentId: string, address: ReplyAddress): CardReply | null {
    const channel = this.options.channelFor(agentId);
    if (!channel) { this.log(`没有可用的飞书连接，无法发送流式卡片 agent=${agentId}`); return null; }
    const card = new CardReply(address, channel, this.throttleMs, this.now, this.log);
    this.pending.add(card.done);
    void card.done.finally(() => this.pending.delete(card.done));
    return card;
  }

  private endTurn(agentId: string): void {
    const turn = this.turns.get(agentId);
    if (!turn) return;
    this.turns.delete(agentId);
    if (turn.textChars || turn.failed) {
      this.log(`流式回复回合结束 agent=${agentId} text=${turn.textChars} cards=${turn.cards} tools=${turn.tools} source=${turn.source}${turn.failed ? " failed" : ""}`
        + (turn.textChars && !turn.cards ? "（有回复文字但本回合没有领取到消息，文字未发送）" : ""));
    }
    if (!turn.failed) { turn.card?.finish(); return; }
    // A failed turn after a poll must not leave the user unanswered.
    if (!turn.card) {
      if (!turn.lastAddress) {
        try { turn.lastAddress = replyAddressOf(this.options.resolveSource(agentId)); } catch { /* best effort */ }
      }
      if (turn.lastAddress) turn.card = this.open(agentId, turn.lastAddress);
    }
    turn.card?.finish(turn.failed);
  }
}
