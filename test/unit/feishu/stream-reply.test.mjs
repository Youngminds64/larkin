import assert from "node:assert/strict";
import path from "node:path";
import { test } from "bun:test";
import { pathToFileURL } from "node:url";

const ROOT = path.resolve(import.meta.dirname, "..", "..", "..");
const streamReply = await import(pathToFileURL(path.join(ROOT, "dist/feishu/stream-reply.mjs")).href);
const { StreamReplyCoordinator, STREAM_REPLY_FAILURE_TEXT, replyAddressOf, replyModeFromEnv } = streamReply;

/** Mirrors @larksuite/channel `stream()`: run the markdown producer, reject when it rejects. */
function fakeChannel() {
  const cards = [];
  return {
    cards,
    async stream(to, input, opts) {
      const card = { to, opts, contents: [], outcome: "open" };
      cards.push(card);
      try {
        await input.markdown({ async setContent(full) { card.contents.push(full); } });
        card.outcome = "completed";
      } catch (error) {
        card.outcome = `failed:${error.message}`;
        throw error;
      }
      return { messageId: `om_card_${cards.length}` };
    },
  };
}

function harness(initialSource = null) {
  const channel = fakeChannel();
  const state = { source: initialSource };
  const logs = [];
  const coordinator = new StreamReplyCoordinator({
    channelFor: () => channel,
    resolveSource: () => state.source,
    log: (...parts) => logs.push(parts.join(" ")),
    throttleMs: 0,
    resolveIntervalMs: 0,
  });
  const send = (event) => coordinator.observe("agent-1", event);
  return { channel, state, logs, coordinator, send };
}

const finalContent = (card) => card.contents.at(-1);

test("reply mode defaults to card and LARKIN_REPLY_MODE=cli restores the legacy CLI reply", () => {
  assert.equal(replyModeFromEnv({}), "card");
  assert.equal(replyModeFromEnv({ LARKIN_REPLY_MODE: "card" }), "card");
  assert.equal(replyModeFromEnv({ LARKIN_REPLY_MODE: "cli" }), "cli");
});

test("only chat/thread sources with a real om_ anchor become card addresses", () => {
  assert.deepEqual(replyAddressOf({ deliveryTarget: "chat:oc_a", deliveryAnchor: "om_1" }),
    { key: "chat:oc_a#om_1", chatId: "oc_a", anchor: "om_1", inThread: false });
  assert.deepEqual(replyAddressOf({ deliveryTarget: "thread:oc_a:omt_t", deliveryAnchor: "om_2" }),
    { key: "thread:oc_a:omt_t#om_2", chatId: "oc_a", anchor: "om_2", inThread: true });
  assert.equal(replyAddressOf({ deliveryTarget: "document-comment:doc_x", deliveryAnchor: "doc_comment_1" }), null);
  assert.equal(replyAddressOf({ deliveryTarget: "chat:oc_a", deliveryAnchor: "rem_1" }), null);
  assert.equal(replyAddressOf(null), null);
});

test("text after the poll streams into one card replying to the polled message; pre-poll text is dropped", async () => {
  const { channel, state, coordinator, send } = harness();
  send({ type: "turn-start" });
  send({ type: "text-delta", text: "I will poll first.", newBlock: true });
  send({ type: "activity", activity: "tool", name: "Bash" });
  state.source = { deliveryTarget: "chat:oc_room", deliveryAnchor: "om_user" };
  send({ type: "text-delta", text: "你好", newBlock: true });
  send({ type: "text-delta", text: "，世界" });
  send({ type: "activity", activity: "tool", name: "Bash" });
  send({ type: "text-delta", text: "查完了。", newBlock: true });
  send({ type: "turn-end" });
  await coordinator.idle();
  assert.equal(channel.cards.length, 1);
  const [card] = channel.cards;
  assert.equal(card.to, "oc_room");
  assert.deepEqual(card.opts, { replyTo: "om_user", replyInThread: false });
  assert.equal(finalContent(card), "你好，世界\n\n查完了。");
  assert.equal(card.outcome, "completed");
});

test("each turn with reply text logs a diagnostic summary, flagging text that had no polled message", async () => {
  const { state, logs, coordinator, send } = harness();
  send({ type: "turn-start" });
  send({ type: "text-delta", text: "没有领取消息就写的回复", newBlock: true });
  send({ type: "turn-end" });
  assert.match(logs.at(-1), /流式回复回合结束 agent=agent-1 text=11 cards=0 tools=0 source=none（有回复文字但本回合没有领取到消息，文字未发送）/);

  state.source = { deliveryTarget: "chat:oc_room", deliveryAnchor: "om_user" };
  send({ type: "turn-start" });
  send({ type: "text-delta", text: "你好", newBlock: true });
  send({ type: "turn-end" });
  await coordinator.idle();
  assert.ok(logs.includes("流式回复回合结束 agent=agent-1 text=2 cards=1 tools=0 source=chat:oc_room#om_user"));
  assert.ok(logs.includes("流式卡片已发送 anchor=om_user message=om_card_1 chars=2"));

  const before = logs.length;
  send({ type: "turn-start" });
  send({ type: "turn-end" });
  assert.equal(logs.length, before, "a silent turn logs nothing");
});

test("a thread source keeps the card reply inside the same topic", async () => {
  const { channel, coordinator, send } = harness({ deliveryTarget: "thread:oc_room:omt_topic", deliveryAnchor: "om_in_topic" });
  send({ type: "turn-start" });
  send({ type: "text-delta", text: "ok", newBlock: true });
  send({ type: "turn-end" });
  await coordinator.idle();
  assert.equal(channel.cards.length, 1);
  assert.equal(channel.cards[0].to, "oc_room");
  assert.deepEqual(channel.cards[0].opts, { replyTo: "om_in_topic", replyInThread: true });
});

test("polling another target mid-turn closes the first card and opens a new one", async () => {
  const { channel, state, coordinator, send } = harness({ deliveryTarget: "chat:oc_a", deliveryAnchor: "om_a" });
  send({ type: "turn-start" });
  send({ type: "text-delta", text: "answer A", newBlock: true });
  send({ type: "activity", activity: "tool", name: "Bash" });
  state.source = { deliveryTarget: "chat:oc_b", deliveryAnchor: "om_b" };
  send({ type: "text-delta", text: "answer B", newBlock: true });
  send({ type: "turn-end" });
  await coordinator.idle();
  assert.deepEqual(channel.cards.map((card) => [card.to, card.opts.replyTo, finalContent(card), card.outcome]), [
    ["oc_a", "om_a", "answer A", "completed"],
    ["oc_b", "om_b", "answer B", "completed"],
  ]);
});

test("an intentionally silent turn after a poll posts no card", async () => {
  const { channel, coordinator, send } = harness({ deliveryTarget: "chat:oc_a", deliveryAnchor: "om_a" });
  send({ type: "turn-start" });
  send({ type: "activity", activity: "tool", name: "Bash" });
  send({ type: "turn-end" });
  await coordinator.idle();
  assert.equal(channel.cards.length, 0);
});

test("a turn that fails after the poll still answers the user with a failure card", async () => {
  const { channel, coordinator, send } = harness({ deliveryTarget: "chat:oc_a", deliveryAnchor: "om_a" });
  send({ type: "turn-start" });
  send({ type: "activity", activity: "tool", name: "Bash" });
  send({ type: "input-error", inputId: "i1", retryable: false, message: "provider down" });
  send({ type: "turn-end" });
  await coordinator.idle();
  assert.equal(channel.cards.length, 1);
  assert.equal(finalContent(channel.cards[0]), STREAM_REPLY_FAILURE_TEXT);
  assert.equal(channel.cards[0].outcome, "completed");
});

test("a failure after partial text keeps the text and marks the stream interrupted", async () => {
  const { channel, coordinator, send } = harness({ deliveryTarget: "chat:oc_a", deliveryAnchor: "om_a" });
  send({ type: "turn-start" });
  send({ type: "text-delta", text: "half an answer", newBlock: true });
  send({ type: "closed", code: 1, signal: null });
  await coordinator.idle();
  assert.equal(channel.cards.length, 1);
  assert.equal(finalContent(channel.cards[0]), "half an answer");
  assert.equal(channel.cards[0].outcome, `failed:${STREAM_REPLY_FAILURE_TEXT}`);
});

test("a retrying input-error does not mark the turn failed", async () => {
  const { channel, coordinator, send } = harness({ deliveryTarget: "chat:oc_a", deliveryAnchor: "om_a" });
  send({ type: "turn-start" });
  send({ type: "input-error", inputId: "i1", retryable: true, willRetry: true, message: "compacting" });
  send({ type: "turn-end" });
  await coordinator.idle();
  assert.equal(channel.cards.length, 0);
});

test("document-comment and reminder turns never produce an IM card", async () => {
  const { channel, state, coordinator, send } = harness({ deliveryTarget: "document-comment:doc_x", deliveryAnchor: "doc_comment_1" });
  send({ type: "turn-start" });
  send({ type: "text-delta", text: "comment reply goes through comment reply", newBlock: true });
  send({ type: "turn-end" });
  state.source = null;
  send({ type: "turn-start" });
  send({ type: "text-delta", text: "reminder text", newBlock: true });
  send({ type: "turn-end" });
  await coordinator.idle();
  assert.equal(channel.cards.length, 0);
});
