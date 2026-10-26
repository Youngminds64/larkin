export type MentionPolicy = "require" | "free";
export type ReplyMode = "card" | "cli";

export interface ReplyRule {
  /** Which messages the row is about. */
  message: string;
  /** Whether the Agent picks the message up. */
  handled: string;
  /** How its reply reaches the chat. */
  reply: string;
}

/**
 * What happens to each kind of incoming message under a group policy and reply mode, worded for the dashboard.
 * Mirrors decideWake (message-policy.ts) and the card/command split in the standing prompt.
 */
export function describeReplyRules(policy: MentionPolicy, replyMode: ReplyMode): ReplyRule[] {
  const addressedReply = replyMode === "card"
    ? "在原消息下发一张卡片，回复实时写进去；在话题里就回在话题里"
    : "它自己发一条消息回复原消息；在话题里就回在话题里";
  return [
    { message: "私聊", handled: "每条都处理", reply: addressedReply },
    { message: "群里 @ 它（包括 @所有人）", handled: "处理", reply: addressedReply },
    policy === "free"
      ? { message: "群里没 @ 它", handled: "也会看，由它判断要不要回", reply: `要回时发一条普通消息${replyMode === "card" ? "，不出卡片" : ""}；需要来回讨论的会开话题，免得刷屏` }
      : { message: "群里没 @ 它", handled: "不处理", reply: "不回复。消息会存下来，下次它在这个群被叫到时一起读到" },
    { message: "其他机器人发的消息", handled: "只有准确 @ 它才处理，@所有人 不算", reply: addressedReply },
  ];
}

export const MENTION_POLICY_HELP: Record<MentionPolicy, string> = {
  require: "群里只有 @ 它的消息才会处理，适合人多、话题杂的群。",
  free: "群里每条消息它都会看，自己判断要不要回，适合小群或专门找它干活的群。每条消息都会叫醒它，花的额度更多。",
};
