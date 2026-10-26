#!/usr/bin/env bash
# 把 fork（Youngminds64/larkin）里准备好的 2 个分支提交到上游 eddiearc/larkin：先开 2 个 issue，再开 2 个 PR。
# 第 2 个分支叠在第 1 个上面（包含它的提交），所以只合第 2 个 PR 也会把两个改动一起带上。
# 用法：bash submit-upstream.sh check    只检查，不在上游创建任何东西
#       bash submit-upstream.sh submit   检查通过后创建 issue 和 PR
# 中途失败可以直接重跑：已经创建的会记在状态文件里，不会重复创建。
set -euo pipefail
MODE="${1:-}"
if [ "$MODE" != check ] && [ "$MODE" != submit ]; then echo "用法: bash $0 check|submit"; exit 2; fi
UPSTREAM=eddiearc/larkin
FORK_OWNER=Youngminds64
FORK=Youngminds64/larkin
EXPECTED_UPSTREAM_MAIN=22b24a9b7457ea25c355f70722a1d11ccad27bcf
WORK="$HOME/.larkin-upstream-submit-3"
STATE="$WORK/state.env"
mkdir -p "$WORK/issues" "$WORK/prs" "$WORK/rendered"
touch "$STATE"
# shellcheck disable=SC1090
. "$STATE"
fail() { echo; echo "✗ $*"; echo "已停止。不要手动创建 issue 或 PR，把上面的输出原样发给用户。"; exit 1; }

KEYS=(1 2)
# 索引数组（macOS 自带的 bash 3.2 不支持关联数组）
ISSUE_TITLE=(); PR_TITLE=(); BRANCH=(); EXPECTED_SHA=()
ISSUE_TITLE[1]='[Bug]: Agent 回复时用了上文里另一条消息的 message_id，重试时又把 id 打错，回复发不出去'
PR_TITLE[1]='fix(prompt): copy reply ids verbatim and state reminder recipients once'
BRANCH[1]='up/reply-id-guidance'
EXPECTED_SHA[1]=eb57dd9fd3514826196eeee8a06af1efcd0ba7c8
ISSUE_TITLE[2]='[Feature]: 回复方式按 Agent 单独设置，管理后台去掉全局设置页'
PR_TITLE[2]='feat(dashboard): set reply mode per Agent and drop the global settings sheet'
BRANCH[2]='up/agent-settings'
EXPECTED_SHA[2]=a6cf985aa3b09eeeb683a1b76477db423caa10e7

# ---------- 正文 ----------
cat > "$WORK/issues/1.md" <<'LARKIN_KIT_EOF'
### What happened?

Agent 刚 poll 到一条新消息，回复时却把 `--message-id` 填成了上文里更早一条消息的 id，回复落到了旧消息下面。重试时它改为手打 id，打错了一个字符（例如 `…cd44…` 写成 `…cc44…`），被 wrapper 拒绝：

```
无法从 Inbox 状态确定 om_… 的 target；先 poll 对应消息，禁止旁路 target binding
```

Agent 看到「先 poll 对应消息」，又去 poll，但那条消息早就 poll 过了，于是反复重试，最后没有回复成功。

同一次排查里还发现三处会误导人的地方：

1. standing prompt 里关于回复 id 的规则只限定了格式（必须是 `om_` 开头的真实 id），没说 id 要从哪里取。上面两种错法都符合 `om_` 开头，规则管不到。
2. 上面那条报错用了内部术语（target、target binding），没先说结果（发没发出去），「先 poll 对应消息」在这种情况下是错的方向。
3. 卡片模式下，消息没有 @ 机器人、所以没开卡片时，宿主日志写的是「有回复文字但本回合没有领取到消息，文字未发送」。其实消息领到了，只是没 @，日志给的原因不对。

另外，提醒触发时的提醒消息里有三处重复的禁令（「不得猜测收件人」「不得从提醒标题推断收件人」「不得向标题中的任何人发送」），和 standing prompt 里的 `Never infer recipients from a reminder title.` 重复；还有一行「锚点无法由 Inbox 解析时改发到群里」的兜底。提醒触发前锚点已经由 `bindInboxDeliveryAnchor` 钉住，这个兜底实际上走不到，留着只会给 Agent 多一条绕路的选项。

### Reproduction

这是模型行为问题，没法每次稳定复现。出现的条件：

1. 卡片回复模式，Codex runtime。
2. 同一个会话里，上文已经出现过同一个群里另一条消息的 `message_id`。
3. 新消息 poll 进来后，Agent 用 `larkin im +messages-reply --message-id …` 回复，填成了上文那条旧消息的 id；或者手打 id 打错一个字符，触发上面的报错。

### Expected behavior

- Agent 回复时，从要回答的那条消息里原样复制 `message_id`。
- 回复目标找不到时，报错直接说结果：回复没有发出，以及哪个 id 不在 Inbox 记录里。
- 宿主日志能区分「本回合没领到消息」和「领到了但消息没 @ 机器人」。
- 提醒里「发到谁」只在一处正面说清楚。

### Affected area

Runtime host or sessions

### Larkin version or commit

0.5.21 / 22b24a9

### Environment

macOS arm64，Codex runtime，卡片回复模式

### Redacted diagnostics

修复思路：
- 回复 id 规则（cli 和 card 两份 standing prompt）并进原有那一行，加一句 `copied verbatim from the message you are answering`，版本升到 `larkin-standing-v35` / `larkin-standing-v42-card`。
- 报错改成 `回复未发送：本 Agent 的 Inbox 记录里没有 <id>`，不带替代 id 和指令，避免引导 Agent 猜测或绕路。
- 宿主日志按 `replyByCommand` 分两种说法。
- 提醒消息去掉三处禁令和走不到的兜底，末尾统一写「标题里提到的人只是提醒内容，不是收件人」；standing prompt 里那句对应删除。

修复已在 fork 准备好，会单独提 PR。

### Checklist

- [x] I searched existing issues for the same problem.
- [x] I removed credentials, private messages, user data, and other sensitive information.
- [x] This is not a vulnerability or other security-sensitive disclosure.
LARKIN_KIT_EOF
cat > "$WORK/prs/1.md" <<'LARKIN_KIT_EOF'
## Summary

修 Agent 回复时用错或打错 `message_id`、以及相关提示误导的问题（详见 issue）：

- **回复 id 规则：** cli 和 card 两份 standing prompt 的回复 id 规则并进原有那一行，要求 id `copied verbatim from the message you are answering`。版本升到 `larkin-standing-v35` / `larkin-standing-v42-card`，钉了版本号的 eval 数据集、grader 和断言同步更新。
- **找不到回复目标时的报错：** 从 `无法从 Inbox 状态确定 <id> 的 target；先 poll 对应消息，禁止旁路 target binding` 改成 `回复未发送：本 Agent 的 Inbox 记录里没有 <id>`（其他写入操作是 `<operation> 未执行：…`）。只说事实，不附替代 id 或指令。
- **宿主日志：** 卡片模式下有回复文字但没开卡片时，区分两种情况：
  - 消息没 @ 机器人：`（本回合领到的消息没有 @ 机器人，Agent 输出的文字不会自动发到飞书）`
  - 本回合没领到消息：`（本回合没有领到消息，Agent 输出的文字没有可回复的对象，没有发到飞书）`
- **提醒消息文案：**
  - `原始 deliveryTarget` 改成 `送达目标`。
  - 删除「锚点无法解析时改发到群里」的兜底。提醒触发前 `HostReminderOrchestrator` 已经用 `bindInboxDeliveryAnchor` 钉住锚点，这条兜底实际走不到（它在 8dce821 加入，14 分钟后的 6a14222 开始钉锚点）。
  - 删除旧版提醒的「存量 user-facing reminder…」和「历史锚点不是可用的 delivery anchor」两行。
  - 去掉三处收件人禁令。内部提醒写成 `这是内部提醒，没有送达目标。`，末尾统一加一句 `标题里提到的人只是提醒内容，不是收件人。`；standing prompt 里的 `Never infer recipients from a reminder title.` 相应删除，只在提醒里说一次。

## Related issue

Closes #{{I1}}

## Scope

- In scope：`src/agent/context-prompt.ts`、`src/app/lark-cli.ts`、`src/feishu/stream-reply.ts`、`src/feishu/host-business-state.ts`，以及版本号相关的 eval 数据集、grader 和测试。
- Out of scope：回复目标的解析逻辑本身（`resolveInboxMessageTarget`）不变，仍然 fail closed。
- Compatibility or migration impact：standing prompt 版本变化会让运行中的 Agent 在下次会话时拿到新 prompt。`package.json` 版本 0.5.21 → 0.5.22；如果其他 PR 先合，我会改成合并时的上游版本 + 1 个 patch。

## Validation

以下都在 Linux x64、Bun 1.4.4 下运行。

- [x] Relevant focused tests pass：`test/unit/feishu/stream-reply.test.mjs`、`test/unit/feishu/host-business-state.test.mjs`、`test/unit/runtime/runtime-adapters.test.mjs`、`test/unit/evals/*.test.mjs`。
- [x] `bun run build` passes.
- [x] `bun run test` passes：分步跑了它包含的各项，全部通过：typecheck 通过；`test:frontend` 通过；`test:unit` 987 通过；`test:integration` 200 通过；`test:e2e` 22 通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.

需要真实 Agent 的 native eval（`test:eval:*:native`）没有跑。

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF
cat > "$WORK/issues/2.md" <<'LARKIN_KIT_EOF'
### Problem or opportunity

管理后台里，每个 Agent 都有自己的页面，模型、群消息策略、沙箱、Inbox 巡检都在那里设。唯独「回复方式」（流式卡片还是命令回复）只能在「全局设置」里改，而且一改就作用到所有 Agent。全局设置页里另一项「真人群消息默认策略」和每个 Agent 页面上的群消息策略重复。

实际使用中，不同 Agent 适合的回复方式不一样：有的机器人还没有 `cardkit:card:write` 权限，只能用命令回复；有的希望在群里用流式卡片。现在没法分开设。

另外，Agent 页面上的群消息策略是一个下拉框，选项写的是 `require · 群内需要 @` / `free · 群内无需 @`，用户不容易看懂两种策略分别意味着什么。

### Desired outcome

- 回复方式可以在每个 Agent 自己的「回复」页单独设置。
- 所有设置都在 Agent 页面上完成，不再需要全局设置页。
- 群消息策略用带说明的选项展示，一眼能看懂。

### Proposed direction

- 配置里新增 `agents.<id>.replyMode`。没设的 Agent 仍然跟随全局 `replyMode`，所以现有配置行为不变。
- 新增 `set-agent-reply-mode` 变更，按模型变更的方式应用（需要重新加载会话）。改全局回复方式时，跳过已经单独设置过的 Agent，它们的配置签名也不变。
- 「回复」页把群消息策略和回复方式都做成选项卡：「只回 @ 它的 / 每条都看」，「流式卡片 / 普通消息」，各带一句说明；按群设置的表格用同样的名称。
- 去掉全局设置按钮和面板。

### Alternatives considered

保留全局设置页，只在 Agent 页加一个「覆盖全局」的选项。这样同一个值有两个地方能改，还要解释继承关系，用户更难弄清楚当前到底是什么值。

### Scope and compatibility

- 配置文件向后兼容：旧配置没有 `agents.<id>.replyMode`，行为不变；全局 `replyMode` 仍然有效，`larkin config` 命令不变。
- 全局默认回复方式保持 cli。
- 去掉全局设置页后，全局群消息默认策略只能通过 CLI 修改。

### Validation ideas

- `test/unit/platform/reply-mode-config.test.mjs` 覆盖 Agent 级回复方式的存储、继承、签名和全局变更跳过逻辑。
- 前端测试覆盖：没有全局设置按钮；在 Agent 回复页切换回复方式后，只对该 Agent 发 `set-agent-reply-mode` 并应用。

### Are you willing to contribute an implementation after alignment?

Yes. 实现已在 fork 准备好，会单独提 PR。

### Checklist

- [x] I searched existing issues and did not find an equivalent proposal.
- [x] I will wait for maintainer alignment before implementing this non-trivial change.
- [x] This request contains no credentials, private user data, or vulnerability details.
LARKIN_KIT_EOF
cat > "$WORK/prs/2.md" <<'LARKIN_KIT_EOF'
## Summary

回复方式改成按 Agent 单独设置，管理后台去掉全局设置页（详见 issue）：

- **配置：** 新增 `agents.<id>.replyMode`，没设的 Agent 跟随全局 `replyMode`，现有配置行为不变。新增 `set-agent-reply-mode` 变更，按模型变更的方式应用。改全局回复方式时，跳过已经单独设置过的 Agent，它们的配置签名也不变。
- **回复页：** 群消息策略和回复方式都改成带说明的选项卡。群消息策略是「只回 @ 它的 / 每条都看」，回复方式是「流式卡片 / 普通消息」，流式卡片的说明里写明需要 `cardkit:card:write` 权限。按群设置的表格用同样的名称（新文件 `src/dashboard/web/mention-policy.ts`）。
- **去掉全局设置：** 全局设置按钮和面板删除。全局默认值仍可通过 `larkin config` 修改。
- 全局默认回复方式保持 cli，不变。

**这个分支叠在 #{{P1}} 上面**，包含它的提交（版本号 0.5.22 也在那个提交里）。先合 #{{P1}} 再合本 PR，或者只合本 PR（会一起带上 #{{P1}}）都可以。#{{P1}} 合并后，本 PR 的改动只剩这一个提交。

## Related issue

Closes #{{I2}}

## Scope

- In scope：`src/platform/config.ts`、`src/dashboard/dashboard-config-controller.ts`、`src/dashboard/web/app.tsx`、`src/dashboard/web/mention-policy.ts`、`src/dashboard/web/types.ts`、`src/dashboard/web/styles.css` 及对应测试。
- Out of scope：回复方式本身的运行逻辑、`larkin config` 命令不变。
- Compatibility or migration impact：配置文件向后兼容，旧配置没有 `agents.<id>.replyMode` 时行为不变。本 PR 自己不再升版本，和 #{{P1}} 一起算 0.5.22。

## Validation

以下都在 Linux x64、Bun 1.4.4 下运行。

- [x] Relevant focused tests pass：`test/unit/platform/reply-mode-config.test.mjs`、`test/frontend/dashboard-workbench.test.tsx`、`test/unit/dashboard/dashboard-typescript.test.mjs`、`test/unit/dashboard/dashboard-workbench-source.test.mjs`。
- [x] `bun run build` passes.
- [x] `bun run test` passes：分步跑了它包含的各项，全部通过：typecheck 通过；`test:frontend` 45 通过；`test:unit` 988 通过；`test:integration` 200 通过；`test:e2e` 22 通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.

可选的真浏览器测试：`dashboard-inbox-audit-browser` 通过。`dashboard-workbench-browser` 在等一个叫「配置」的标签页时超时，上游 main（22b24a9）原样运行也在同一处失败，所以这个测试里本 PR 改到的步骤没有被真正执行到。

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF

# 把正文里的 {{I1}} {{I2}} {{P1}} 换成已经知道的编号；还不知道的写成「待补」。
render() {  # $1 源文件  $2 目标文件
  local src="$1" dst="$2" k v
  cp "$src" "$dst"
  for k in "${KEYS[@]}"; do
    v="$(eval echo "\${ISSUE_$k:-}")"
    sed -i.bak "s/{{I$k}}/${v:-待补}/g" "$dst"
  done
  v="${PR_1:-}"; sed -i.bak "s/{{P1}}/${v:-待补}/g" "$dst"
  rm -f "$dst.bak"
  if grep -q "{{" "$dst"; then fail "正文里还有没替换的占位符：$dst"; fi
}
save() { echo "$1=$2" >> "$STATE"; eval "$1=$2"; }
num_from_url() { echo "$1" | sed -E "s#.*/([0-9]+)/?\$#\1#"; }

echo "== 1. 检查 GitHub 登录"
LOGIN="$(gh api user --jq .login 2>/dev/null)" || fail "gh 没有登录或连不上 GitHub。请用户先运行 gh auth login。"
[ "$LOGIN" = "$FORK_OWNER" ] || fail "gh 当前登录的是 $LOGIN，需要登录 $FORK_OWNER。"
echo "   已登录 $LOGIN"

echo "== 2. 检查上游 main 有没有变化"
MAIN="$(gh api repos/$UPSTREAM/commits/main --jq .sha)" || fail "读不到上游 main。"
if [ "$MAIN" != "$EXPECTED_UPSTREAM_MAIN" ]; then
  echo "   上游 main 现在是 $MAIN，准备分支时是 $EXPECTED_UPSTREAM_MAIN。新增的提交："
  gh api "repos/$UPSTREAM/compare/$EXPECTED_UPSTREAM_MAIN...$MAIN" --jq '.commits[] | "   \(.sha[0:7]) \(.commit.message | split("\n")[0])"' || true
  fail "上游 main 已经前进，分支需要先更新。请把这段输出发给用户，由用户转给 Claude 处理。"
fi
echo "   上游 main 仍是 ${MAIN:0:7}"

echo "== 3. 检查 fork 上的 2 个分支"
for k in "${KEYS[@]}"; do
  b="${BRANCH[$k]}"
  s="$(gh api "repos/$FORK/branches/$b" --jq .commit.sha 2>/dev/null)" || fail "fork 上找不到分支 $b。"
  [ "$s" = "${EXPECTED_SHA[$k]}" ] || fail "分支 $b 现在是 ${s:0:7}，应该是 ${EXPECTED_SHA[$k]:0:7}。"
  echo "   ✓ $b ${s:0:7}"
done

echo "== 4. 检查上游是否已经有同名的 issue / PR（避免重复）"
EXISTING="$(gh issue list -R $UPSTREAM --author @me --state all --limit 100 --json number,title --jq '.[] | "\(.number)\t\(.title)"'; gh pr list -R $UPSTREAM --author @me --state all --limit 100 --json number,title --jq '.[] | "\(.number)\t\(.title)"')"
for k in "${KEYS[@]}"; do
  for title in "${ISSUE_TITLE[$k]}" "${PR_TITLE[$k]}"; do
    hit="$(printf "%s\n" "$EXISTING" | awk -F "\t" -v t="$title" '$2 == t { print $1 }' | head -1)"
    if [ -n "$hit" ]; then
      known="$(eval echo "\${ISSUE_$k:-} \${PR_$k:-}")"
      case " $known " in *" $hit "*) ;; *) fail "上游已经有同名的 #$hit「$title」，但不是这个脚本创建的。为避免重复，请用户确认后再处理。";; esac
    fi
  done
done
echo "   没有重复"

echo "== 5. 检查正文"
for k in "${KEYS[@]}"; do render "$WORK/issues/$k.md" "$WORK/rendered/issue-$k.md"; render "$WORK/prs/$k.md" "$WORK/rendered/pr-$k.md"; done
echo "   4 份正文都已生成在 $WORK/rendered/"

if [ "$MODE" = check ]; then
  echo
  echo "检查全部通过。将要创建："
  for k in "${KEYS[@]}"; do echo "   issue: ${ISSUE_TITLE[$k]}"; done
  for k in "${KEYS[@]}"; do echo "   PR:    ${PR_TITLE[$k]}  ← $FORK_OWNER:${BRANCH[$k]}"; done
  echo "下一步：bash $0 submit"
  exit 0
fi

echo "== 6. 创建 2 个 issue"
for k in "${KEYS[@]}"; do
  if [ -n "$(eval echo "\${ISSUE_$k:-}")" ]; then echo "   已存在 #$(eval echo "\${ISSUE_$k}") ${ISSUE_TITLE[$k]}"; continue; fi
  url="$(gh issue create -R $UPSTREAM --title "${ISSUE_TITLE[$k]}" --body-file "$WORK/rendered/issue-$k.md")" || fail "创建 issue「${ISSUE_TITLE[$k]}」失败。"
  n="$(num_from_url "$url")"; save "ISSUE_$k" "$n"; echo "   ✓ #$n ${ISSUE_TITLE[$k]}"
  sleep 2
done

echo "== 7. 创建 2 个 PR"
for k in "${KEYS[@]}"; do
  if [ -n "$(eval echo "\${PR_$k:-}")" ]; then echo "   已存在 #$(eval echo "\${PR_$k}") ${PR_TITLE[$k]}"; continue; fi
  render "$WORK/prs/$k.md" "$WORK/rendered/pr-$k.md"
  url="$(gh pr create -R $UPSTREAM --base main --head "$FORK_OWNER:${BRANCH[$k]}" --title "${PR_TITLE[$k]}" --body-file "$WORK/rendered/pr-$k.md")" || fail "创建 PR「${PR_TITLE[$k]}」失败。"
  n="$(num_from_url "$url")"; save "PR_$k" "$n"; echo "   ✓ #$n ${PR_TITLE[$k]}"
  sleep 2
done

echo "== 8. 补全 PR 正文里互相引用的编号"
for k in "${KEYS[@]}"; do
  render "$WORK/prs/$k.md" "$WORK/rendered/pr-$k.md"
  gh pr edit -R $UPSTREAM "$(eval echo "\${PR_$k}")" --body-file "$WORK/rendered/pr-$k.md" >/dev/null || fail "更新 PR #$(eval echo "\${PR_$k}") 的正文失败。"
done
echo "   ✓ 已更新"

echo
echo "全部完成："
printf "%-6s %-8s %-8s %s\n" 序号 issue PR 标题
for k in "${KEYS[@]}"; do printf "%-6s #%-7s #%-7s %s\n" "$k" "$(eval echo "\${ISSUE_$k}")" "$(eval echo "\${PR_$k}")" "${PR_TITLE[$k]}"; done
echo "链接：https://github.com/$UPSTREAM/pulls/$FORK_OWNER"
