#!/usr/bin/env bash
# 把 fork（Youngminds64/larkin）里准备好的 10 个分支提交到上游 eddiearc/larkin：先开 10 个 issue，再开 10 个 PR。
# 用法：bash submit-upstream.sh check    只检查，不在上游创建任何东西
#       bash submit-upstream.sh submit   检查通过后创建 issue 和 PR
# 中途失败可以直接重跑：已经创建的会记在状态文件里，不会重复创建。
set -euo pipefail
MODE="${1:-}"
if [ "$MODE" != check ] && [ "$MODE" != submit ]; then echo "用法: bash $0 check|submit"; exit 2; fi
UPSTREAM=eddiearc/larkin
FORK_OWNER=Youngminds64
FORK=Youngminds64/larkin
EXPECTED_UPSTREAM_MAIN=5aefc018cf1c23499969e2e7a9efc38c46f4fc34
WORK="$HOME/.larkin-upstream-submit"
STATE="$WORK/state.env"
mkdir -p "$WORK/issues" "$WORK/prs" "$WORK/rendered"
touch "$STATE"
# shellcheck disable=SC1090
. "$STATE"
fail() { echo; echo "✗ $*"; echo "已停止。不要手动创建 issue 或 PR，把上面的输出原样发给用户。"; exit 1; }

KEYS=(1 2 3 4 5 6 7 8 9 10)
# 索引数组（macOS 自带的 bash 3.2 不支持关联数组）
ISSUE_TITLE=(); PR_TITLE=(); BRANCH=(); EXPECTED_SHA=()
ISSUE_TITLE[1]='[Bug]: 在 AI agent 终端或非 UTF-8 系统语言下，两个单测会失败'
PR_TITLE[1]='test: keep two unit tests stable in agent shells and non-UTF-8 locales'
BRANCH[1]='up/test-stability'
EXPECTED_SHA[1]=c8651497cde3f5c7a560cbd16c6b96d18d8ce01e
ISSUE_TITLE[2]='[Bug]: 禁止调用 ps 的沙箱里，Inbox 锁取不到，Agent 领不到消息'
PR_TITLE[2]='fix(inbox): take the Inbox lock without ps'
BRANCH[2]='up/inbox-lock-no-ps'
EXPECTED_SHA[2]=0da6edf78d87a4d7928cfce4d4be940451f3acdd
ISSUE_TITLE[3]='[Bug]: 重启后 Codex 会话就绪前到达的消息一直卡在 Inbox'
PR_TITLE[3]='fix(runtime): resubmit deliveries deferred before the session was ready'
BRANCH[3]='up/resubmit-deferred'
EXPECTED_SHA[3]=9c7ca8bb352336815fdf8cb7d8ba1f098715311f
ISSUE_TITLE[4]='[Bug]: 服务停止时日志没有任何记录，关闭终端会直接杀掉 supervisor'
PR_TITLE[4]='fix(start): log the stop signal and stop cleanly on SIGHUP'
BRANCH[4]='up/stop-signal'
EXPECTED_SHA[4]=d41ae224be8563b5d15895eb74ea26bf20c13221
ISSUE_TITLE[5]='[Bug]: larkin 重启后，已打开的管理后台页面保存一律失败且不说原因'
PR_TITLE[5]='fix(dashboard): keep open pages working across restarts and say why a request failed'
BRANCH[5]='up/dashboard-restart'
EXPECTED_SHA[5]=f21131a0820cf68ce7c145cde013bf9ecb4edae3
ISSUE_TITLE[6]='[Bug]: 管理后台「全局设置」要等飞书群名查完才能操作'
PR_TITLE[6]='fix(dashboard): open global settings without waiting on Feishu group lookups'
BRANCH[6]='up/global-settings-fast'
EXPECTED_SHA[6]=4c06d1e6b696a3c0c59cc7539dd38953de634ca5
ISSUE_TITLE[7]='[Feature]: 把要求的 Bun 版本升到 1.4.4'
PR_TITLE[7]='build: pin Bun 1.4.4'
BRANCH[7]='up/bun-1.4.4'
EXPECTED_SHA[7]=572749a77fec6142ff8a2acbc506219a11cec82a
ISSUE_TITLE[8]='[Feature]: 飞书回复改为 Host 驱动的流式卡片，并展示思考与工具步骤'
PR_TITLE[8]='feat: stream Feishu replies as Host-driven CardKit cards'
BRANCH[8]='up/streaming-card'
EXPECTED_SHA[8]=aac4b88377da66321ff08155b560f7a6a3d7d1a4
ISSUE_TITLE[9]='[Feature]: 管理后台 Agent 页：在线编辑工作区文件、AGENTS.md、能力列表与 tab 重组'
PR_TITLE[9]='feat(dashboard): edit workspace files and regroup the Agent page'
BRANCH[9]='up/dashboard-agent-page'
EXPECTED_SHA[9]=ee4d6cc0ec768e9e087b41f3e12e02cac93b14e0
ISSUE_TITLE[10]='[Feature]: 按 Agent 设置 Codex 沙箱和 Fast 模式'
PR_TITLE[10]='feat: per-Agent Codex sandbox and Fast mode'
BRANCH[10]='up/codex-sandbox-fast'
EXPECTED_SHA[10]=e1f765d2c6d78b943dff3b46779cdbb5b292ac03

# ---------- 正文 ----------
cat > "$WORK/issues/1.md" <<'LARKIN_KIT_EOF'
### What happened?

在两类常见的开发环境里，`bun run test:unit` 有两个用例会失败，但产品代码本身没有问题：

1. **在 AI agent 的终端里跑**（例如 Claude Code、Codex，环境里带 `CLAUDECODE`、`REPL_ID` 或 `AGENT` 变量）：`three-Agent live acceptance is opt-in, hermetic by default, and fixture-verifiable` 失败。这个用例要检查 Bun 打印出的「跳过原因」，而 Bun 检测到自己在 AI agent 里运行时，不会打印被跳过的测试名。
2. **系统语言不是 UTF-8 时**（例如 `LANG=C`）：`shared tmux session lists windows by recorded owner` 失败。测试辅助代码用 Tab 分隔 tmux 的输出再拆开，而 tmux 在非 UTF-8 的 locale 下会把 Tab 打印成 `_`，拆出来就对不上。

现在越来越多贡献者用 AI agent 跑测试，这两个失败会让人误以为自己的改动有问题。

### Reproduction

1. 在上游 main（`5aefc01`）执行 `bun install --frozen-lockfile && bun run build`。
2. 用 `CLAUDECODE=1 bun test --max-concurrency 1 test/unit/app/live-acceptance-harness.test.mjs` 运行，第一个用例失败。
3. 在 `LANG=C`、`LC_ALL=C` 的终端里运行 `bun test --max-concurrency 1 test/unit/evals/pi-tmux-bash.test.mjs`，第二个用例失败。

### Expected behavior

两个用例在 AI agent 终端和非 UTF-8 locale 下都应该通过。

### Affected area

Other（仅测试）

### Larkin version or commit

0.5.19 / 5aefc01

### Environment

Linux x64，Bun 1.3.14，tmux 3.x；在 AI agent 终端里运行测试

### Redacted diagnostics

修复思路：
- live acceptance 用例启动子进程时去掉 `CLAUDECODE`、`REPL_ID`、`AGENT` 这几个变量；
- tmux 辅助代码调用 tmux 时加 `-u`，让它按 UTF-8 输出。产品代码只读取 tmux 的单个字段，不受影响。

修复已在 fork 准备好，会单独提 PR。

### Checklist

- [x] I searched existing issues for the same problem.
- [x] I removed credentials, private messages, user data, and other sensitive information.
- [x] This is not a vulnerability or other security-sensitive disclosure.
LARKIN_KIT_EOF
cat > "$WORK/prs/1.md" <<'LARKIN_KIT_EOF'
## Summary

修两个和运行环境有关、和产品代码无关的单测失败（详见 issue）：

- `three-Agent live acceptance is opt-in, hermetic by default, and fixture-verifiable`：Bun 检测到自己在 AI agent 里运行（`CLAUDECODE`、`REPL_ID`、`AGENT`）时不打印被跳过的测试名，而这个用例正好要检查那行提示。现在用例启动子进程时去掉这几个变量。
- `shared tmux session lists windows by recorded owner`：测试辅助代码按 Tab 拆分 tmux 的输出，而 tmux 在非 UTF-8 locale 下会把 Tab 打印成 `_`。现在调用 tmux 时加 `-u`。产品代码只读取 tmux 的单个字段，不受影响。

## Related issue

Closes #{{I1}}

## Scope

- In scope：`test/unit/app/live-acceptance-harness.test.mjs` 和 `test/support/pi-tmux-bash-live-harness.mjs` 两个测试文件。
- Out of scope：产品代码。
- Compatibility or migration impact：无。只改测试，所以没有升 `package.json` 版本；如果维护者希望也升一个 patch，我再补。

## Validation

以下都在 Linux x64、Bun 1.3.14 下运行。

- [x] Relevant focused tests pass：`test/unit/app/live-acceptance-harness.test.mjs`、`test/unit/evals/pi-tmux-bash.test.mjs`。
- [x] `bun run build` passes.
- [x] `bun run test` passes：分步跑了它包含的各项，全部通过：typecheck 通过；`test:frontend` 31 通过；`test:unit` 939 通过、1 跳过；`test:integration` 197 通过、18 跳过；`test:e2e` 22 通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF
cat > "$WORK/issues/2.md" <<'LARKIN_KIT_EOF'
### What happened?

`larkin inbox poll` 等 Inbox 操作在拿不到 `ps` 权限的环境里会直接失败，报错：

```
无法读取 Inbox lock owner 身份：ps failed
```

原因：Inbox 锁在写入锁主人时，会用 `ps -o lstart=` 读取当前进程的启动时间，作为进程身份的一部分。而 Codex 在 macOS 上的沙箱（Seatbelt，`workspace-write` 模式）不允许调用 `ps`。于是 Agent 一次也领不到消息，用户在飞书里看到的是 Agent 一直不回复。

现在上游把 Codex 会话固定为 `danger-full-access`，所以默认配置下碰不到。但只要 Agent 跑在任何禁止查看进程的沙箱里，就会遇到。我们另一个 issue 提议让每个 Agent 可以选择 `workspace-write` 沙箱，这个修复是它的前提。

### Reproduction

1. 用一个 `ps` 会失败的环境运行 Agent，最简单的复现方式是在 PATH 最前面放一个总是 `exit 1` 的假 `ps`。
2. 调用 `larkin inbox poll --target <target>`（或在测试里构造 `AgentStateStore` 并取锁）。
3. 报错 `无法读取 Inbox lock owner 身份：ps failed`，Inbox 消息领不到。

在 macOS 上，把 Codex 会话改成 `sandbox: "workspace-write"` 后，从飞书给 Agent 发消息，也能稳定复现。

### Expected behavior

取 Inbox 锁不需要查看进程信息，沙箱里和沙箱外行为一致。锁的过期判断仍然安全：主人进程已经退出、或者锁被持有得明显过久时，才能回收。

### Affected area

Runtime host or sessions

### Larkin version or commit

0.5.19 / 5aefc01

### Environment

macOS arm64，Codex runtime，Bun 1.3.14

### Redacted diagnostics

修复思路：锁主人只记录 `{ version, pid, createdAt, nonce }`，不再记录进程启动时间。主人 pid 已不存在，或者锁已被持有 60 秒，就可以回收。Inbox 操作只会持锁几毫秒，所以 60 秒的规则只在「主人崩溃且 pid 被复用」时才起作用。旧版本写下的锁没有 `createdAt`，用锁目录的 mtime 代替。

修复已在 fork 准备好，会单独提 PR。

### Checklist

- [x] I searched existing issues for the same problem.
- [x] I removed credentials, private messages, user data, and other sensitive information.
- [x] This is not a vulnerability or other security-sensitive disclosure.
LARKIN_KIT_EOF
cat > "$WORK/prs/2.md" <<'LARKIN_KIT_EOF'
## Summary

Inbox 锁不再依赖 `ps`，在禁止查看进程的沙箱里（例如 Codex 在 macOS 上的 `workspace-write`）Agent 也能正常领取消息（详见 issue）。

- 锁主人的记录改为 `{ version, pid, createdAt, nonce }`，不再记录进程启动时间，取锁时完全不调用 `ps`，沙箱内外行为一致。
- 回收规则：主人 pid 已不存在，或者锁已被持有 60 秒，就可以回收。Inbox 操作只持锁几毫秒，60 秒的规则只在「主人崩溃且 pid 被复用」时才会起作用。
- 旧版本写下的锁没有 `createdAt`，用锁目录的 mtime 代替，升级时不需要清理。
- 回收过期锁仍然要先拿共享的回收锁，它会记录进程身份。沙箱里的进程拿不到时就等待，由沙箱外的 daemon 回收。
- `AgentStateStore` 不再接受 `inspectProcess` 依赖，原来为此注入它的测试相应简化。

## Related issue

Closes #{{I2}}

## Scope

- In scope：`src/agent/agent-state-store.ts` 的 Inbox 锁主人记录和过期判断，以及相关测试。
- Out of scope：其他进程锁（setup lock、回收锁）的身份判断不变。
- Compatibility or migration impact：锁文件格式向后兼容，旧锁按目录 mtime 判断年龄。`package.json` 版本 0.5.19 → 0.5.20；如果其他 PR 先合，我会改成合并时的上游版本 + 1 个 patch。

## Validation

以下都在 Linux x64、Bun 1.3.14 下运行。

- [x] Relevant focused tests pass：`test/unit/agent/agent-state-store.test.mjs`。
- [x] `bun run build` passes.
- [ ] `bun run test` passes：分步跑了它包含的各项：typecheck 通过；`test:frontend` 31 通过；`test:unit` 938 通过、2 失败、1 跳过；`test:integration` 197 通过、18 跳过；`test:e2e` 22 通过。`test:unit` 的 2 个失败是 #{{P_TEST}} 修的环境问题（这次在 AI agent 终端里运行），上游 main 在同一环境下也是这 2 个失败，其余全部通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF
cat > "$WORK/issues/3.md" <<'LARKIN_KIT_EOF'
### What happened?

larkin 重启或热重载后，如果 Codex 会话还没初始化完，这时到达的第一条消息会一直卡在 Inbox 里，Agent 不处理，用户只看到 Agent 没反应。要等下一条消息或别的事件来了，它才会被一起带上。

日志里能看到：

```
Runtime 暂缓投递，消息保留在 inbox seq=1: Codex thread is not initialized
```

原因：Codex 在 `thread/start` 或 `thread/resume` 返回之前，对 `prompt()` 一律回答 `Codex thread is not initialized`。Host 会把这次投递标成「暂缓」并保留在 Inbox，这部分是对的；但之后没有任何东西会去重新投递它。

### Reproduction

1. 用 Codex runtime 启动 larkin，等它就绪。
2. 重启 larkin（或触发一次热重载），在 Codex 会话初始化完成之前，立刻从飞书给 Agent 发一条私聊消息。
3. 日志出现上面那行「暂缓投递」，之后这条消息一直没有被处理。
4. 再发一条消息，前一条才会被一起处理。

### Expected behavior

会话一就绪，Host 就自动重新投递之前暂缓的消息，不需要等下一条消息触发。

### Affected area

Runtime host or sessions

### Larkin version or commit

0.5.19 / 5aefc01

### Environment

macOS arm64，Codex runtime，Bun 1.3.14

### Redacted diagnostics

修复思路：会话发出 `session-init` 事件时，Host 对这个 Agent 调用一次 `retryPending`，重投暂缓的工作。改动只有 3 行，并补了单测：不带修复时测试失败，带上修复后通过。

修复已在 fork 准备好，会单独提 PR。

### Checklist

- [x] I searched existing issues for the same problem.
- [x] I removed credentials, private messages, user data, and other sensitive information.
- [x] This is not a vulnerability or other security-sensitive disclosure.
LARKIN_KIT_EOF
cat > "$WORK/prs/3.md" <<'LARKIN_KIT_EOF'
## Summary

重启或热重载后，Codex 会话初始化完成前到达的消息会被暂缓并留在 Inbox，但之后没有任何东西去重投它（详见 issue）。现在会话发出 `session-init` 时，Host 对这个 Agent 调用一次 `retryPending`，把暂缓的投递重新提交。

## Related issue

Closes #{{I3}}

## Scope

- In scope：`src/runtime/runtime-host.ts` 在 `session-init` 时重投暂缓的工作（3 行），以及 `test/unit/runtime/runtime-host.test.mjs` 里的新用例。
- Out of scope：暂缓投递本身的判定逻辑不变。
- Compatibility or migration impact：无。`package.json` 版本 0.5.19 → 0.5.20；如果其他 PR 先合，我会改成合并时的上游版本 + 1 个 patch。

## Validation

以下都在 Linux x64、Bun 1.3.14 下运行。

- [x] Relevant focused tests pass：`test/unit/runtime/runtime-host.test.mjs`。
- [x] `bun run build` passes.
- [ ] `bun run test` passes：分步跑了它包含的各项：typecheck 通过；`test:frontend` 31 通过；`test:unit` 938 通过、2 失败、1 跳过；`test:integration` 197 通过、18 跳过；`test:e2e` 22 通过。`test:unit` 的 2 个失败是 #{{P_TEST}} 修的环境问题（这次在 AI agent 终端里运行），上游 main 在同一环境下也是这 2 个失败，其余全部通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF
cat > "$WORK/issues/4.md" <<'LARKIN_KIT_EOF'
### What happened?

larkin 的 supervisor、daemon 和 dashboard 有时会一起消失，但日志里什么都没留下。崩溃、Ctrl+C 和被外部进程杀掉，在日志里看起来完全一样，没法排查。

查下来有两个原因：

1. supervisor 收到 SIGTERM / SIGINT 正常停止时，本来就不打印任何日志，所以事后看不出它是被谁、因为什么停掉的。
2. supervisor 没有处理 SIGHUP。`larkin start` 是前台进程，启动它的终端一关（包括 AI agent 执行命令的会话结束），进程就直接被结束，不走正常的关闭流程，也不留任何记录。

### Reproduction

1. 在一个终端里执行 `larkin start`。
2. 直接关闭这个终端窗口（或对 supervisor 发 `kill -HUP <pid>`）。
3. supervisor、daemon、dashboard 全部退出，日志里没有任何关于停止的记录，也没有执行正常的关闭步骤。

### Expected behavior

- supervisor 停止时记一条日志，写明收到的信号、自己的 pid 和父进程 pid。
- 收到 SIGHUP 时，和 SIGTERM 一样走正常的关闭流程。

### Affected area

Runtime host or sessions

### Larkin version or commit

0.5.19 / 5aefc01

### Environment

macOS arm64，Codex runtime，Bun 1.3.14

### Redacted diagnostics

修复只改 `src/app/run.ts`：停止时先打印一行 `[start] 收到 <信号>，停止服务 (pid=… ppid=…)`，再执行原来的关闭流程；新增 SIGHUP 处理，按 SIGTERM 的方式停止。附带一个集成测试：给 supervisor 发 SIGHUP，检查它打印了这行日志，并且是正常退出而不是被信号直接结束。

修复已在 fork 准备好，会单独提 PR。

### Checklist

- [x] I searched existing issues for the same problem.
- [x] I removed credentials, private messages, user data, and other sensitive information.
- [x] This is not a vulnerability or other security-sensitive disclosure.
LARKIN_KIT_EOF
cat > "$WORK/prs/4.md" <<'LARKIN_KIT_EOF'
## Summary

supervisor 停止时留下记录，关闭终端时也能正常停止（详见 issue）：

- 停止时先打印一行 `[start] 收到 <信号>，停止服务 (pid=… ppid=…)`，再执行原来的关闭流程。这样服务消失后，可以从日志区分崩溃（崩溃本来就会打印自己的日志）、Ctrl+C 和外部 kill。
- 新增 SIGHUP 处理：终端关闭时按 SIGTERM 的方式停止，而不是被信号直接结束、跳过关闭流程。

## Related issue

Closes #{{I4}}

## Scope

- In scope：`src/app/run.ts` 的信号处理，以及新的集成测试 `test/integration/app/supervisor-stop-signal.test.mjs`。
- Out of scope：daemon 和 dashboard 自己的信号处理不变。
- Compatibility or migration impact：无。`package.json` 版本 0.5.19 → 0.5.20；如果其他 PR 先合，我会改成合并时的上游版本 + 1 个 patch。

## Validation

以下都在 Linux x64、Bun 1.3.14 下运行。

- [x] Relevant focused tests pass：`test/integration/app/supervisor-stop-signal.test.mjs`、`test/integration/build/bun-only-runtime-contract.test.mjs`。
- [x] `bun run build` passes.
- [ ] `bun run test` passes：分步跑了它包含的各项：typecheck 通过；`test:frontend` 31 通过；`test:unit` 937 通过、2 失败、1 跳过；`test:integration` 198 通过、18 跳过；`test:e2e` 22 通过。`test:unit` 的 2 个失败是 #{{P_TEST}} 修的环境问题（这次在 AI agent 终端里运行），上游 main 在同一环境下也是这 2 个失败，其余全部通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF
cat > "$WORK/issues/5.md" <<'LARKIN_KIT_EOF'
### What happened?

larkin 重启后，之前打开着的管理后台页面再点保存，一律失败。页面上只显示笼统的 `configuration update rejected`，dashboard 日志里也不记录原因。我们在本地临时加了日志，才看到真实原因是 `csrf rejected`。

原因：dashboard 每次启动都会重新生成一个 CSRF token 并注入到页面里。服务重启后 token 换了，旧页面带的还是旧 token，所有写请求都被拒绝。

其他几类失败也被同样的笼统提示盖住了，用户不知道该怎么办，例如：文件太大、Agent 已被删除、模型已不在列表里、页面来自旧版本。

### Reproduction

1. `larkin start`，打开管理后台，进入任意可以保存的设置页。
2. 不刷新页面，重启 larkin。
3. 在旧页面上修改设置并保存，提示 `configuration update rejected`，没有说明原因，也没有提示刷新。

### Expected behavior

- larkin 重启后，已经打开的页面还能正常保存。
- 请求失败时，页面告诉用户具体原因和下一步该做什么（例如「页面已过期，请刷新」），而不是一句笼统的拒绝。

### Affected area

Dashboard

### Larkin version or commit

0.5.19 / 5aefc01

### Environment

macOS arm64，Codex runtime，Bun 1.3.14，Chrome

### Redacted diagnostics

修复思路：
- CSRF token 存进 larkin home 下一个权限为 0600 的文件，重启后继续使用；文件缺失或权限不安全时才生成新的。token 不对的请求仍然会被拒绝。
- 失败的请求返回固定的错误码和一句给人看的说明；本来就是写给用户的报错原样透传；意外的失败保留原因。原始原因仍写进本地日志。
- 请求根本连不上 dashboard 时，页面提示 larkin 可能已停止或正在重启。

修复已在 fork 准备好，会单独提 PR。

### Checklist

- [x] I searched existing issues for the same problem.
- [x] I removed credentials, private messages, user data, and other sensitive information.
- [x] This is not a vulnerability or other security-sensitive disclosure.
LARKIN_KIT_EOF
cat > "$WORK/prs/5.md" <<'LARKIN_KIT_EOF'
## Summary

larkin 重启后，已经打开的管理后台页面能继续保存；请求失败时告诉用户具体原因（详见 issue）。

- **CSRF token 跨重启保留：** 存进 larkin home 下的 `dashboard-capability` 文件（权限 0600，由当前用户拥有），重启后继续使用；文件缺失或权限不安全时才生成新值。token 不对的请求仍然会被拒绝，提示页面已过期。
- **可读的错误：** 失败的请求返回固定的 `code` 和一句给人看的说明，原始原因写进本地日志。HTTP 状态码也随之区分（原来大多是 400）：
  - CSRF token 不对 → 403 `stale_page`（提示刷新）；Host 或 Origin 不对 → 403 `forbidden`；请求体过大 → 413 `too_large`；Agent 不存在 → 404；页面和后端版本不一致 → 400 `outdated_page`；本来写给用户的报错 → 400 原样透传。
  - 其余意外失败 → 500 并附原因；只有 `/api/config/apply` 例外：配置已经保存、只是 runtime 连不上，所以保持原来的 409，加 `code: "apply_failed"`。
  - `test/integration/dashboard/dashboard-config-security.test.mjs` 里断言的状态码相应改成上面这些值。
- **连不上时的提示：** 请求根本连不上 dashboard 时，页面提示 larkin 可能已停止或正在重启。

## Related issue

Closes #{{I5}}

## Scope

- In scope：`src/app/dashboard.ts`、`src/dashboard/dashboard-lifecycle.ts`、`src/dashboard/dashboard-config-controller.ts`、`src/dashboard/web/app.tsx` 及对应测试。
- Out of scope：dashboard 的鉴权方式不变，仍然只认页面注入的 token。
- Compatibility or migration impact：larkin home 下新增一个 0600 的 `dashboard-capability` 文件。`package.json` 版本 0.5.19 → 0.5.20；如果其他 PR 先合，我会改成合并时的上游版本 + 1 个 patch。

## Validation

以下都在 Linux x64、Bun 1.3.14 下运行。

- [x] Relevant focused tests pass：`test/unit/dashboard/dashboard-config-directories.test.mjs`、`test/unit/dashboard/dashboard-state-lifecycle.test.mjs`、`test/integration/dashboard/dashboard-config-security.test.mjs`、`test/frontend/dashboard-workbench.test.tsx`。
- [x] `bun run build` passes.
- [ ] `bun run test` passes：分步跑了它包含的各项：typecheck 通过；`test:frontend` 32 通过；`test:unit` 939 通过、2 失败、1 跳过；`test:integration` 197 通过、18 跳过；`test:e2e` 22 通过。`test:unit` 的 2 个失败是 #{{P_TEST}} 修的环境问题（这次在 AI agent 终端里运行），上游 main 在同一环境下也是这 2 个失败，其余全部通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF
cat > "$WORK/issues/6.md" <<'LARKIN_KIT_EOF'
### What happened?

打开管理后台的「全局设置」后，所有控件要灰好几秒才能操作，Agent 多或飞书接口慢的时候更久。等待期间保存按钮显示「保存中…」，但其实什么都没在保存，只是在读取。

原因：全局设置面板读的是 `/api/config`，这个接口会先通过飞书查询每个 Agent 的群名，全部查完才返回。而全局设置根本用不到群名。

### Reproduction

1. 配置两个以上 Agent，每个 Agent 都设置过群聊策略。
2. 打开管理后台，点「全局设置」。
3. 面板里的控件在飞书群名查询完成前一直是禁用状态，保存按钮显示「保存中…」。

### Expected behavior

- 全局设置面板马上可用，不等飞书群名查询。
- 读取时按钮显示「读取中…」，只有真正保存时才显示「保存中…」。

### Affected area

Dashboard

### Larkin version or commit

0.5.19 / 5aefc01

### Environment

macOS arm64，Bun 1.3.14，Chrome

### Redacted diagnostics

修复思路：`/api/config` 新增可选参数 `?chats=0`，带上时跳过群名查询；全局设置面板改用它。其他页面的请求不变。补了一个单测：带 `?chats=0` 时一次群名查询都不发起。

修复已在 fork 准备好，会单独提 PR。

### Checklist

- [x] I searched existing issues for the same problem.
- [x] I removed credentials, private messages, user data, and other sensitive information.
- [x] This is not a vulnerability or other security-sensitive disclosure.
LARKIN_KIT_EOF
cat > "$WORK/prs/6.md" <<'LARKIN_KIT_EOF'
## Summary

全局设置面板不再等飞书群名查询（详见 issue）：

- `/api/config` 新增可选参数 `?chats=0`，带上时跳过群名查询；不带时行为不变。
- 全局设置面板改用 `?chats=0`，打开后立即可用。
- 读取时按钮显示「读取中…」，只有真正保存时才显示「保存中…」。

## Related issue

Closes #{{I6}}

## Scope

- In scope：`src/dashboard/dashboard-config-controller.ts`、`src/dashboard/web/app.tsx` 的全局设置面板，以及 `test/unit/dashboard/dashboard-config-directories.test.mjs` 里的新用例。
- Out of scope：其他页面的请求不变。
- Compatibility or migration impact：无。`package.json` 版本 0.5.19 → 0.5.20；如果其他 PR 先合，我会改成合并时的上游版本 + 1 个 patch。

## Validation

以下都在 Linux x64、Bun 1.3.14 下运行。

- [x] Relevant focused tests pass：`test/unit/dashboard/dashboard-config-directories.test.mjs`。
- [x] `bun run build` passes.
- [ ] `bun run test` passes：分步跑了它包含的各项：typecheck 通过；`test:frontend` 31 通过；`test:unit` 938 通过、2 失败、1 跳过；`test:integration` 197 通过、18 跳过；`test:e2e` 22 通过。`test:unit` 的 2 个失败是 #{{P_TEST}} 修的环境问题（这次在 AI agent 终端里运行），上游 main 在同一环境下也是这 2 个失败，其余全部通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF
cat > "$WORK/issues/7.md" <<'LARKIN_KIT_EOF'
### Problem or opportunity

larkin 把 Bun 锁在 1.3.14，版本不对就拒绝启动：

```
requires Bun 1.3.14
```

Bun 1.4.x 已经是当前的稳定版本。机器上装了新版 Bun 的人（包括用 `bun upgrade` 升级过的人）从源码运行 larkin 或跑测试，都会直接被这条检查挡住，只能自己再装一个旧版本 Bun 临时切换。

### Desired outcome

larkin 要求的 Bun 版本升到 1.4.4：源码运行、测试、CI 和发布用的独立安装包都用 1.4.4。装了 1.4.4 的人可以直接运行，不需要降级。

### Proposed direction

把以下几处的 Bun 版本从 1.3.14 改为 1.4.4：
- `src/platform/check-bun-version.cts` 里要求的版本；
- `package.json` 的 `packageManager`；
- CI、release、npm publish、release-platform-smoke 等 workflow；
- README、AGENTS.md、bug report 模板里提到版本的地方；
- npm 包的 bin shim。

已知差异：Bun 1.4 会把运行时转译缓存写到 `$HOME/.bun/install/cache/@t@`。CLI help 隔离测试原本把这个目录当成 larkin 写入的状态而报错，现在在测试里关闭这个缓存。

### Alternatives considered

- 放宽版本检查，允许一个范围（例如 `>=1.3.14 <1.5`）：发布用的独立安装包仍然要选一个具体版本构建，而且不同小版本的行为差异要逐一验证，维护成本更高。
- 保持 1.3.14：新装 Bun 的贡献者都需要手动降级。

### Scope and compatibility

- 影响所有平台和三个 runtime 的运行环境，以及 CI 和发布流程。
- 发布产物会改用 Bun 1.4.4 构建。
- 合入后，从源码运行的用户需要把 Bun 升到 1.4.4（版本检查的报错会提示）。
- 不改配置、权限和持久化数据。

### Validation ideas

- 在 Bun 1.4.4 下跑 `bun install --frozen-lockfile`、`bun run build`、`bun run test`、`bun run licenses:check`、`bun run publication:check:tree` 全部通过。
- CI 和 release 的 dry run 用 1.4.4 构建成功，独立安装包能正常启动。

### Are you willing to contribute an implementation after alignment?

Yes

实现已经在 fork 上完成，会同时提一个 PR，可按维护者的意见调整，或等维护者决定后再合。

### Checklist

- [x] I searched existing issues and did not find an equivalent proposal.
- [ ] I will wait for maintainer alignment before implementing this non-trivial change.
- [x] This request contains no credentials, private user data, or vulnerability details.

> 第二项没有勾：实现已经写好并同时提交了 PR，但合不合、怎么改，完全听维护者的决定。
LARKIN_KIT_EOF
cat > "$WORK/prs/7.md" <<'LARKIN_KIT_EOF'
## Summary

把 larkin 要求的 Bun 版本从 1.3.14 升到 1.4.4（理由和影响面见 issue）：

- `src/platform/check-bun-version.cts` 要求的版本、`package.json` 的 `packageManager`、npm 包的 bin shim；
- CI、release、npm publish、release-platform-smoke 等 workflow；
- README、AGENTS.md、README 头图里的版本号，以及 bug report 模板里的示例；
- 相关测试里写死的版本号。

Bun 1.4 会把运行时转译缓存写到 `$HOME/.bun/install/cache/@t@`。CLI help 隔离测试原本把这个目录当成 larkin 写入的状态而报错，现在测试里通过 `BUN_RUNTIME_TRANSPILER_CACHE_PATH=0` 关闭这个缓存。

## Related issue

Closes #{{I7}}

这是工具链和发布流程的改动，按 CONTRIBUTING 需要先和维护者对齐。实现先提上来方便评估，合不合、什么时候合，听维护者的决定。

## Scope

- In scope：Bun 版本检查、`packageManager`、workflow、文档和相关测试。
- Out of scope：依赖版本和 `bun.lock` 不变。
- Compatibility or migration impact：合入后，从源码运行 larkin 的人需要把 Bun 升到 1.4.4（版本检查会提示）；发布产物改用 Bun 1.4.4 构建。`package.json` 版本 0.5.19 → 0.5.20；如果其他 PR 先合，我会改成合并时的上游版本 + 1 个 patch。这个 PR 合入后，其他 PR 的 CI 会改用 Bun 1.4.4。

## Validation

以下都在 Linux x64、Bun 1.4.4 下运行。

- [x] Relevant focused tests pass：`test/integration/setup/setup-cli.test.mjs`、`test/integration/build/release-platform-ci.test.mjs`、`test/unit/runtime/pi-model-catalog.test.mjs`。
- [x] `bun run build` passes.
- [ ] `bun run test` passes：分步跑了它包含的各项：typecheck 通过；`test:frontend` 31 通过；`test:unit` 937 通过、2 失败、1 跳过；`test:integration` 197 通过、18 跳过；`test:e2e` 22 通过。`test:unit` 的 2 个失败是 #{{P_TEST}} 修的环境问题（这次在 AI agent 终端里运行），上游 main 在同一环境下也是这 2 个失败，其余全部通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF
cat > "$WORK/issues/8.md" <<'LARKIN_KIT_EOF'
### Problem or opportunity

现在 Agent 的回复由模型自己调用 `lark-cli im +messages-reply` 发出，要等它整轮跑完才一次性出现。长任务期间，用户只能看到 OnIt 表情，看不到进度，也不知道 Agent 正在做什么。回复会不会发出、发到哪条消息下，也完全取决于模型是否照提示词拼对了命令。

### Desired outcome

- 模型领取（poll）到一条发给它的消息后（私聊，或群里 @ 它的消息），回复以飞书 CardKit 卡片的形式出现，挂在原消息下；原消息在话题里时，卡片也留在同一话题。正文实时逐字出现。
- 卡片里能看到思考摘要和每一次工具调用。回复结束后，这些步骤折叠成一个「过程回放」面板，下面是完整回答。
- 不需要回复的轮次（静默）不发卡片；轮次失败时，卡片上有明确的失败提示，已输出的正文保留。
- 群里没有 @ 它的消息不开卡片：Agent 自己判断要不要回，要回就用命令回复，需要来回跟进的用话题回复，免得刷屏。
- 可以在管理后台切回现在的命令行回复方式。

### Proposed direction

- **Host 驱动卡片：** Runtime Host 订阅 runtime 事件（正文增量、思考、工具开始/结束），按 canonical Inbox 的 `last_source` 确定回复的锚点消息，用 CardKit 卡片实体做流式更新：结构不变时逐元素更新（打字机效果），新增步骤时整卡更新。
- **三个 runtime 适配：** Codex（`item/started` / `item/completed`）、Claude（`tool_use` / `tool_result`）、Pi（`tool_execution_start` / `tool_execution_end`）补齐工具调用及结果事件。卡片上显示的命令参数会遮掉 token、secret、password、Bearer 等凭据。
- **回复方式设置：** 新增可选的全局配置 `replyMode`（`card` | `cli`），管理后台「全局设置 → 回复方式」可切换；未设置时读环境变量 `LARKIN_REPLY_MODE`，默认 `card`。
- **没 @ 的群消息：** 这类消息的 Inbox 信封带 `mentions_you: false`，不开卡片。卡片模式的 standing prompt 里写一次规则：这时正文不会送达任何人，要回复就用 `im +messages-reply`，跟进类加 `--reply-in-thread`，不回复就静默结束。消息原文不再追加任何说明文字。
- **Standing prompt：** 卡片模式用独立的版本号 `larkin-standing-v41-card`，只保留飞书相关的安全边界（只用 `larkin` 包装命令、真实 `om_` id、同一话题、去重、撤回等），去掉回复命令的拼写配方；同时说明话题和群主时间线的区别、@ 人的正确写法（只有命令发送的 `<at user_id="…"></at>` 才算 @，卡片里的文字不会通知人）。命令行模式继续用 `larkin-standing-v34`，内容不变。
- **Inbox 巡检：** 巡检轮次没有卡片，巡检结果的说明改成编号步骤，写清楚读哪段历史、用什么命令补回复。
- **权限：** setup 时申请 `cardkit:card:write`。

### Alternatives considered

- 用 `@larksuite/channel` 自带的 markdown 流式卡片：只有一个正文元素，放不下步骤面板。
- 继续由模型通过 lark-cli 发文字：做不到流式，回复位置也不稳定。
- 给每条没 @ 的消息追加一段回复说明：每条消息都重复同样的文字，污染上下文；改成信封上的一个字段加 prompt 里写一次规则。

### Scope and compatibility

- 三个 runtime 都受影响；只涉及 IM 私聊、群聊和话题的回复。文档评论回复、提醒投递和附件发送方式不变。
- 机器人需要新增 `cardkit:card:write` 权限：新 setup 会申请；已有机器人要在开放平台手动开通并发布新版本，否则建卡失败（原因会写进日志）。
- 配置新增可选字段 `replyMode`，只有设置过才会写入。旧版本不认识这个字段，回退前需要先删掉。
- 默认回复方式是卡片。如果想先灰度，可以把默认值改成 `cli`，请维护者决定。
- 卡片模式用新的 standing prompt 版本；命令行模式的 prompt 和评测不变。

### Validation ideas

- 私聊长任务时卡片实时更新，结束后折叠成过程回放。
- 话题里的消息，回复留在话题内。
- 中途领取另一条消息时，换成新的卡片。
- 静默轮次不发卡片；失败轮次有失败提示。
- 群里没 @ 的消息不开卡片，Agent 按需用命令回复。
- 切换回复方式后，之后的回复按新方式发出。

### Are you willing to contribute an implementation after alignment?

Yes

实现已在 fork 上完成并在本地飞书环境实测，会同时提一个 PR，可按维护者的意见调整。

### Checklist

- [x] I searched existing issues and did not find an equivalent proposal.
- [ ] I will wait for maintainer alignment before implementing this non-trivial change.
- [x] This request contains no credentials, private user data, or vulnerability details.

> 第二项没有勾：实现已经写好并同时提交了 PR，但合不合、怎么改，完全听维护者的决定。
LARKIN_KIT_EOF
cat > "$WORK/prs/8.md" <<'LARKIN_KIT_EOF'
## Summary

把飞书回复从「模型自己调用 lark-cli 发文字」改成「Runtime Host 实时写入 CardKit 卡片」（背景见 issue）。

**卡片回复**
- 模型 poll 到一条发给它的消息后（私聊，或群里 @ 它的消息），Host 以 canonical Inbox 的 `last_source` 作为锚点，在原消息下回复一张卡片；原消息在话题里时，卡片留在同一话题。
- 卡片是时间线形式：正文用 CardKit 逐元素更新（打字机效果）；工具调用和思考摘要按发生顺序收进折叠面板；底部一行显示当前步骤。结束后所有步骤折叠成「过程回放 · 执行了 N 个工具调用 · 用时 X 秒」，下面是完整回答，并关闭 `streaming_mode`。
- 静默轮次（poll 之后只思考、不回答）不发卡片。轮次失败时，卡片上给出失败提示，已输出的正文保留。
- Codex（`item/started` / `item/completed`）、Claude（`tool_use` / `tool_result`）、Pi（`tool_execution_start` / `tool_execution_end`）都补上了工具调用和结果事件。卡片上显示的命令参数为单行，并遮掉 token、secret、password、Bearer 等凭据。

**没 @ 的群消息**
- 群里没有 @ Agent 的消息不开卡片。这类消息的 Inbox 信封带 `mentions_you: false`（@ 它的是 `true`，私聊不带），消息原文不再追加任何说明文字。原来 @ 机器人时追加在原文末尾的中文「提及说明」也一并去掉，改用这个字段。
- 只有明确唤醒过 Agent（`wake: true`）且不是 `mentions_you: false` 的消息才开卡片；巡检时读到的旧消息不带 `wake`，也不开卡片。

**回复方式设置**
- 新增可选的全局配置 `replyMode`（`card` | `cli`），对应管理后台「全局设置 → 回复方式」，保存后对每个 Agent 重新应用；正忙的 Agent 会被列出来，稍后可在该 Agent 的配置页手动应用。未设置时读环境变量 `LARKIN_REPLY_MODE`，默认 `card`。
- setup 时申请 `cardkit:card:write` 权限。

**Standing prompt**
- 卡片模式使用独立版本 `larkin-standing-v41-card`。它去掉了回复命令的拼写配方，保留飞书相关的安全边界（只用 `larkin` 包装命令、只用真实的 `om_` id、话题里的回复留在话题、去重、撤回前确认等），并且每条规则只写一次：
  - 什么时候卡片会送达，什么时候正文没人看得到、需要用命令回复（跟进类加 `--reply-in-thread`）；
  - 话题（`thread:` 目标）和群主时间线（`chat:` 目标）分别是什么；
  - 回复 Inbox 里领到的消息不需要再找用户确认；
  - 在飞书里 @ 人或 Agent 的唯一有效写法：用命令发送、正文里写 `<at user_id="<open_id>"></at>`；卡片文字和纯文本 `@名字` 都不会通知对方。
- 命令行模式继续用 `larkin-standing-v34`，内容和评测不变。

**Inbox 巡检**
- 巡检轮次没有卡片。`inbox audit --json` 在结果顶层写一次「什么算发现、怎么回复」，每个目标只给自己的三步：读哪段历史、用什么命令补回复、怎么标记完成。
- 启动补投的提示只保留要做的事（先 `inbox check`，再逐个 `inbox poll`），不再重复常驻规则。

**日志**
- daemon 日志新增三类诊断：每个 Agent 的回复方式、每张卡片的发送结果、每轮汇总（正文字数、卡片数、工具数和 Inbox source）。

## Related issue

Closes #{{I8}}

管理后台改进（#{{P_DASH}}）和 Codex 沙箱与 Fast（#{{P_SANDBOX}}）这两个 PR 叠在本 PR 之上，建议先看这个。

## Scope

- In scope：IM 私聊、群聊和话题的回复；三个 runtime 的工具事件；全局回复方式设置；CardKit 权限申请；卡片模式的 standing prompt；Inbox 巡检和启动补投给 Agent 的文字。
- Out of scope：文档评论回复（仍走 `comment reply`）、提醒投递、附件（仍由模型用 `+messages-reply --image/--file` 发送）、按 Agent 单独设置回复方式。
- Compatibility or migration impact：
  - 默认回复方式变成卡片。如果想先灰度，可以把默认值改成 `cli`，请维护者决定。
  - 已有机器人需要在开放平台开通 `cardkit:card:write` 并发布新版本，否则建卡失败，原因会写进日志。
  - 配置里的 `replyMode` 只有设置过才会写入；0.5.19 不认识这个字段，回退前需要先删掉。
  - `package.json` 版本 0.5.19 → 0.5.20；如果其他 PR 先合，我会改成合并时的上游版本 + 1 个 patch。

## Validation

以下都在 Linux x64、Bun 1.3.14 下运行。

- [x] Relevant focused tests pass：`test/unit/feishu/stream-reply.test.mjs`、`test/unit/feishu/host-business-state.test.mjs`、`test/unit/feishu/message-policy.test.mjs`、`test/unit/agent/agent-state-store.test.mjs`、`test/unit/agent/missed-outbound-scan.test.mjs`、`test/unit/platform/reply-mode-config.test.mjs`。
- [x] `bun run build` passes.
- [ ] `bun run test` passes：分步跑了它包含的各项：typecheck 通过；`test:frontend` 32 通过；`test:unit` 961 通过、2 失败、1 跳过；`test:integration` 197 通过、18 跳过；`test:e2e` 22 通过。`test:unit` 的 2 个失败是 #{{P_TEST}} 修的环境问题（这次在 AI agent 终端里运行），上游 main 在同一环境下也是这 2 个失败，其余全部通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.
- [x] 手工验证：在 fork 上用 macOS + Codex runtime 接真实飞书做过多轮验收：私聊和群里 @ 的卡片流式更新、步骤面板和过程回放、话题内回复、静默轮次不发卡片、没 @ 的群消息不开卡片并由 Agent 用命令回复、切换回复方式。

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF
cat > "$WORK/issues/9.md" <<'LARKIN_KIT_EOF'
### Problem or opportunity

管理后台目前能看状态、改一部分配置，但想调整一个 Agent 时还是要登录机器：

- 改 AGENTS.md、CLAUDE.md 等工作区文件只能在机器上改，后台只能预览（#209 提过这个需求）。
- 看不到 Agent 新会话会加载哪些 Skill、Subagent、插件和 MCP，也看不到 larkin 自己给 Agent 的内置指令是什么，写 AGENTS.md 时容易和内置指令冲突。
- Agent 页有 7 个 tab，按数据来源划分，而不是按用户想做的事划分，常用设置散在几处。
- 打开回复规则等页面时，要等飞书逐个查群名才能操作。

### Desired outcome

- 工作区里的文本文件可以直接在后台编辑保存，有并发保护，不会覆盖 Agent 期间的改动。
- 在「设定」里查看、编辑、新建 AGENTS.md；新建时自动加一个引用它的 CLAUDE.md，切换到 Claude runtime 也用同一份人设。
- 只读列出 Agent 会加载的 Skill、Subagent、插件和 MCP，以及 larkin 的内置指令（standing prompt）。
- Agent 页按用途分成 4 个 tab：动态 / 设定 / 回复规则 / 高级。
- 各页面不再等待飞书群名查询。

### Proposed direction

- **工作区编辑：** 新增 `PUT /api/workspace/file`（CSRF 保护）。只能覆盖工作区里已存在的文本文件，≤1 MB，原子写入并保留权限；保存时带上加载时的 sha256，期间文件被改过就返回 409，草稿保留。
- **AGENTS.md：** `GET /api/agent-rules`、`POST /api/agent-rules/file`（只允许新建 AGENTS.md / CLAUDE.md，`wx` 打开，绝不覆盖）。
- **能力列表：** `GET /api/agent-capabilities` 按 runtime 读取各自的目录和配置，只返回名称、描述、位置和状态（可用 / 已停用 / 需要修复 / 被覆盖），不返回文件内容；MCP 只显示传输方式，不暴露参数、环境变量和请求头。`config.toml` 用一个只认表头和单行值的小读取器解析，不引入新依赖。
- **内置指令：** `GET /api/agent-standing-prompt` 用和 Runtime Host 相同的 `ContextPromptBuilder.build` 生成，只读展示，附版本、runtime 和回复方式。
- **页面结构：** 4 个 tab；旧的 `?tab=` 链接会落到对应的新 tab；切换 tab 不丢草稿。「高级」里去掉重复的运行摘要，把「疑似卡住」和 runtime 版本放到更显眼的位置。
- **群名：** 不需要群名的页面跳过查询；查到的群名缓存在 Agent 状态目录（0600），之后先用缓存回答，后台再刷新。
- **诊断：** 配置保存或应用被拒时，接口返回值不变，但 dashboard 日志会记下原因。

### Alternatives considered

- 让用户继续登录机器编辑文件：对不熟悉命令行的用户门槛高，也是 #209 想解决的问题。
- 允许编辑内置指令：它和 larkin 的代码（命令、卡片协议、安全规则）绑在一起，可编辑的话每次升级都会出问题，所以只读展示，自定义仍走 AGENTS.md。

### Scope and compatibility

- 只改管理后台和它的接口，不改 runtime 行为和配置格式。
- 新增的接口都需要 dashboard 的私有访问和 CSRF；能力列表和内置指令只读。
- 工作区编辑只能改已存在的文本文件，不能新建、删除、重命名，也不能越出工作区。
- 新增文件：Agent 状态目录下的群名缓存 `chat-names.json`（0600）。

### Validation ideas

- 在后台编辑并保存 AGENTS.md，新会话按新规则工作；保存期间文件被 Agent 改过时提示冲突且草稿不丢。
- 对 Codex、Claude、Pi 三种 runtime 分别查看能力列表，和实际加载的一致。
- 旧的 `?tab=` 链接能打开对应内容。
- 飞书接口慢时，各页面仍能立即操作。

### Are you willing to contribute an implementation after alignment?

Yes

实现已在 fork 上完成并本地实测，会同时提一个 PR，可按维护者的意见调整或拆分。

### Checklist

- [x] I searched existing issues and did not find an equivalent proposal.
- [ ] I will wait for maintainer alignment before implementing this non-trivial change.
- [x] This request contains no credentials, private user data, or vulnerability details.

> 和 #209 相关，覆盖了其中「在网页里编辑 AGENTS.md 等文件」的部分；#209 里的保存前 diff、单独列出 Skill 目录、重新加载按钮这次没有做。第二项没有勾：实现已经写好并同时提交了 PR，但合不合、怎么改，完全听维护者的决定。
LARKIN_KIT_EOF
cat > "$WORK/prs/9.md" <<'LARKIN_KIT_EOF'
## Summary

> **依赖 #{{P_CARD}}（流式卡片）。** 本分支叠在它上面，所以 GitHub 上的 diff 和提交列表会包含 #{{P_CARD}} 的内容；本 PR 自己的改动从提交「Make workspace text files editable in the dashboard」开始。请先看 #{{P_CARD}}，它合入后这里的 diff 会自动只剩本 PR 的部分。

管理后台的 Agent 页改进（背景见 issue，和 #209 相关）：

**工作区文件可编辑**
- 已完整预览的文本文件可以直接编辑和保存：编辑 / 保存（或 Cmd/Ctrl+S）/ 取消；有未保存草稿时，切换文件、切换 Agent 或离开页面前会提醒。
- 新增 `PUT /api/workspace/file`（CSRF 保护）：只能覆盖工作区里已存在的文本文件，≤1 MB，原子写入并保留原文件权限。保存时带上加载时的 sha256，期间文件被 Agent 改过就返回 409，草稿保留。
- 工作区相关路由挪进独立的 `dashboard-workspace-controller.ts`。

**设定 tab：AGENTS.md、能力列表、内置指令**
- 查看、编辑、新建 `AGENTS.md`。新建时如果 `CLAUDE.md` 不存在，会同时创建一个内容为 `@AGENTS.md` 的 `CLAUDE.md`，切换到 Claude runtime 也用同一份人设。Claude runtime 的 `CLAUDE.md` 没引用 `AGENTS.md` 时，页面会提示一行。
  - `GET /api/agent-rules`、`POST /api/agent-rules/file`（只允许新建 AGENTS.md / CLAUDE.md，用 `wx` 打开，绝不覆盖已有文件或链接）。
- 只读列出 Agent 新会话会加载的 Skill、Subagent、插件和 MCP，按来源（工作区 / 全局 / 插件带的 / 自带）和优先级分组，标出可用 / 已停用 / 需要修复 / 被覆盖。
  - `GET /api/agent-capabilities` 只返回名称、描述、位置和状态，不返回文件内容；MCP 只显示传输方式（`stdio · <命令名>` 或 `HTTP · <origin>`），参数、环境变量、请求头和 URL 查询串都不会到页面上。
  - 按 runtime 读取各自的位置（Codex 尊重 `CODEX_HOME`，Claude 尊重 `CLAUDE_CONFIG_DIR`）。`config.toml` 用一个只认表头和单行值的小读取器解析，不引入新依赖。
- 只读显示 larkin 给这个 Agent 的内置指令（standing prompt），附版本、runtime 和回复方式。`GET /api/agent-standing-prompt` 和 Runtime Host 用的是同一个 `ContextPromptBuilder.build`。

**Agent 页改成 4 个 tab**
- 动态（指标、最近对话和提醒）/ 设定（Runtime、模型、Effort，以及上面的内容）/ 回复规则（私聊说明、群消息策略、各群策略）/ 高级（Inbox 巡检，工作区浏览和日志折叠在下面）。
- 旧的 `?tab=` 链接会落到对应的新 tab；所有 tab 保持挂载，切换 tab 不丢草稿，只有切换 Agent 时会确认。
- 「高级」里去掉和别处重复的运行摘要；只有它显示的两项挪到更显眼的位置：处理表情超过 3 分钟未完成时，Agent 标题旁显示红色「疑似卡住」；runtime 版本和可执行文件路径加到模型设置的就绪行里。

**不等飞书群名**
- 全局设置、模型和高级页读 `/api/config?chats=0`，跳过群名查询；只有回复规则页需要群名。（全局设置这部分和 #{{P_GLOBAL}} 是同一个修复；哪个先合，另一个合并上游 main 时由我处理冲突。）
- 查到的群名按 Agent 缓存在状态目录的 `chat-names.json`（0600），之后先用缓存回答，后台再刷新；从没查过的群才会等一次飞书。

**诊断**
- 配置保存或应用被拒时，接口返回值不变，dashboard 日志里会记下原因。

## Related issue

Closes #{{I9}}

Refs #209：覆盖了其中「在网页里编辑 AGENTS.md 等文件」的部分；保存前 diff、单独列出 Skill 目录、重新加载按钮这次没有做。

## Scope

- In scope：管理后台页面和它的接口。
- Out of scope：runtime 行为和配置格式；新建、删除、重命名工作区文件；编辑能力列表里的条目；编辑内置指令。
- Compatibility or migration impact：
  - 没有配置或数据迁移。Agent 状态目录下新增群名缓存 `chat-names.json`。
  - 依赖 #{{P_CARD}}：回复规则和内置指令页会显示回复方式。
  - `package.json` 版本为 0.5.21（#{{P_CARD}} 的 0.5.20 之上再加一个 patch）；合并时我会改成当时的上游版本 + 1 个 patch。
  - 提交「WIP: dashboard rule files tab」是中间过程，维护者愿意的话可以 squash 合并。

## Validation

以下都在 Linux x64、Bun 1.3.14 下运行。

- [x] Relevant focused tests pass：`test/unit/dashboard/dashboard-workspace.test.mjs`、`test/unit/dashboard/dashboard-capabilities.test.mjs`、`test/unit/dashboard/dashboard-standing-prompt.test.mjs`、`test/unit/dashboard/dashboard-config-directories.test.mjs`、`test/frontend/dashboard-workbench.test.tsx`、`test/frontend/dashboard-state.test.ts`。
- [x] `bun run build` passes.
- [ ] `bun run test` passes：分步跑了它包含的各项：typecheck 通过；`test:frontend` 40 通过；`test:unit` 969 通过、2 失败、1 跳过；`test:integration` 197 通过、18 跳过；`test:e2e` 22 通过。`test:unit` 的 2 个失败是 #{{P_TEST}} 修的环境问题（这次在 AI agent 终端里运行），上游 main 在同一环境下也是这 2 个失败，其余全部通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.
- [x] 手工验证：在 fork 上用 macOS 打开管理后台验收过 4 个 tab、AGENTS.md 编辑与新建、能力列表、内置指令和工作区文件编辑。

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF
cat > "$WORK/issues/10.md" <<'LARKIN_KIT_EOF'
### Problem or opportunity

Codex 会话现在固定用 `sandbox: "danger-full-access"` 启动，没有其他选择。Agent 在群里被很多人使唤时，任何人都能让它改动这台电脑上的任意文件，风险全落在机器主人身上。

另外，Codex 的部分模型提供 Fast 服务档位（`serviceTier: "fast"`），larkin 目前没有办法按 Agent 开启。

Inbox 巡检的设置也有两套（全局一套、每个 Agent 一套），界面上「跟随全局」的逻辑不好理解，说明文字也和实际行为对不上。

### Desired outcome

- 每个 Agent 可以在两种沙箱之间选择：
  - **不限制**（`danger-full-access`）：默认值，现有 Agent 不受影响，适合只有自己用的 Agent；
  - **只改自己的工作区**（`workspace-write`）：只能写自己的工作区、自己的状态目录、遥测目录和临时目录，其余位置只读，网络保持开启；适合群里很多人都能使唤的 Agent。
- 每个 Agent 可以单独开启 Codex 的 Fast 档位；不支持 Fast 的模型上开关不可用。
- Inbox 巡检只在每个 Agent 的「高级」页设置：一个开关加一个间隔，预填它当前实际生效的值；说明文字写清楚巡检检查什么、什么时候消耗额度。

### Proposed direction

- **沙箱：** Agent 配置新增可选字段 `sandbox`。`workspace-write` 时通过 `config.sandbox_workspace_write = { network_access: true, writable_roots: [...] }` 额外放开 Agent 状态目录（Inbox、提醒、lark-cli 登录信息）和遥测目录，保证 `larkin` 和 lark-cli 仍能工作。审批策略保持 `never`，因为没人在旁边点同意。Agent 不能放宽自己的沙箱：配置目录对它只读，并且 `set-agent-sandbox` 这项修改拒绝来自 Agent 的请求，只有用户能改。
- **Fast：** Agent 配置新增可选字段 `fastMode`，开启时在 `thread/start` 和 `thread/resume` 带上 `serviceTier: "fast"`；关闭时不传，用户自己 `~/.codex/config.toml` 里的 `service_tier` 继续生效。模型目录里读取每个模型是否支持 Fast。
- 两个字段都只在非默认值时写入配置，也只在设置过时进入应用签名，所以升级后不会把任何 Agent 标成「待应用」。修改后的应用方式和改模型一样：Agent 空闲时重启它的 runtime 会话。
- **巡检设置：** 去掉全局设置里的巡检区块；每个 Agent 的设置通过已有的 `set-agent-inbox-audit` 写入。存储的全局 `inboxAudit` 和 `larkin config` 不变，从没单独设置过的 Agent 继续沿用全局值。

### Alternatives considered

- 只提供只读沙箱（`read-only`）：Agent 连自己的工作区都不能写，大部分任务做不了。
- 让 Agent 遇到越权时请求审批：没人在旁边点同意，只会让这一轮卡住。

### Scope and compatibility

- 沙箱和 Fast 只对 Codex runtime 生效；其他 runtime 忽略这两个字段，界面上也会说明。
- 配置新增两个可选字段，默认值下不写入；旧版本不认识这两个字段，回退前需要先删掉。
- `workspace-write` 依赖另一个 issue 里的 Inbox 锁修复（取锁不再调用 `ps`），否则 macOS 上 Agent 领不到消息。
- 在 `workspace-write` 下，Agent 改不了 larkin 的设置，所以 Inbox 巡检无法标记完成，界面上会说明。

### Validation ideas

- 选「只改自己的工作区」后，让 Agent 写工作区外的文件被拒绝，写自己工作区成功，`larkin inbox poll` 和 lark-cli 正常。
- 开启 Fast 后，新会话的 `thread/start` 带上 `serviceTier: "fast"`；关闭后不带。
- 升级到新版本后，已有 Agent 不显示「待应用」。

### Are you willing to contribute an implementation after alignment?

Yes

实现已在 fork 上完成并在 macOS 上实测，会同时提一个 PR，可按维护者的意见调整。

### Checklist

- [x] I searched existing issues and did not find an equivalent proposal.
- [ ] I will wait for maintainer alignment before implementing this non-trivial change.
- [x] This request contains no credentials, private user data, or vulnerability details.

> 第二项没有勾：实现已经写好并同时提交了 PR，但合不合、怎么改，完全听维护者的决定。
LARKIN_KIT_EOF
cat > "$WORK/prs/10.md" <<'LARKIN_KIT_EOF'
## Summary

> **依赖 #{{P_DASH}}（管理后台 Agent 页），间接依赖 #{{P_CARD}}。** 本分支叠在 #{{P_DASH}} 上，GitHub 上的 diff 会包含前两个 PR 的内容；本 PR 自己的改动只有最后一个提交「Let each Agent choose its Codex sandbox and Fast mode」。
>
> **还需要 #{{P_LOCK}}（Inbox 锁不再依赖 `ps`）。** 没有它的话，macOS 上选了「只改自己的工作区」的 Agent 会领不到消息。

两个原本写死的 Codex 会话设置改成可以按 Agent 配置，另外整理了 Inbox 巡检的设置（背景见 issue）。

**沙箱**
- Codex 会话原来固定以 `sandbox: "danger-full-access"` 启动。现在每个 Agent 可以选两种模式：
  - `danger-full-access`（后台显示「不限制」）：默认值，现有 Agent 不变。
  - `workspace-write`（后台显示「只改自己的工作区」）：只能写下面这些位置，其余全部只读，包括 larkin 配置目录、其他 Agent 的目录和 home 下的其他位置；网络保持开启。

  | 可写位置 | 默认路径 | 原因 |
  |---|---|---|
  | Agent 工作区（会话 cwd） | `~/.larkin/agents/<agentId>/` | 工作文件和 AGENTS.md / CLAUDE.md |
  | Agent 状态目录 | `~/.larkin/state/agents/<agentId>/` | Inbox、提醒、lark-cli 登录信息；没有它 `larkin` 和 lark-cli 都用不了 |
  | 遥测目录 | `LARKIN_TELEMETRY_SPOOL_DIR` 或其默认值 | 遥测继续工作 |
  | `/tmp` 等临时目录 | | Codex `workspace-write` 自带 |

  额外的可写目录通过 `config.sandbox_workspace_write = { network_access: true, writable_roots: [...] }` 传给 Codex。设置了 `LARKIN_CONFIG_DIR` 时，同样的结构在那个目录下。
- Agent 不能放宽自己的沙箱：配置目录对它只读，`larkin config` 写不进去；`set-agent-sandbox` 这项修改也直接拒绝来自 Agent 的请求，只有用户能改。
- 审批策略保持 `never`：没人在旁边点同意，请求审批只会让这一轮卡住。
- 后台「高级 → 沙箱」用两张单选卡片展示两种模式，写明各自的含义和适用场景；可以展开查看这个 Agent 实际可写的路径和已知限制。保存后的应用方式和改模型一样。

**Fast 模式**
- Codex app-server 在 `thread/start` 和 `thread/resume` 上接受 `serviceTier: "fast"`；`model/list` 用 `additionalSpeedTiers: ["fast"]` 或 `serviceTiers: [{ id: "priority", name: "Fast" }]` 标出支持 Fast 的模型。
- 「设定 → 模型」里新增按 Agent 的 Fast 开关，只对 Codex 显示；目录里标明不支持 Fast 的模型上，开关不可用。
- 关闭时不传档位，用户自己 `~/.codex/config.toml` 里的 `service_tier` 继续生效。把 Agent 切到其他 runtime 时会去掉这个设置。

**配置**
- `sandbox` 和 `fastMode` 是 v4 Agent 配置的两个新可选字段，只在非默认值时写入，也只在设置过时进入应用签名，所以升级后不会把任何 Agent 标成「待应用」。
- 它们沿 `AgentRuntimeConfig` → `RuntimeSessionCreate` → Codex 线程参数传下去；配置变化时，Agent 空闲后会重启它的 runtime 会话。

**Inbox 巡检的设置**
- 全局设置里去掉巡检区块；每个 Agent 的「高级」页是一个开关加一个间隔，预填它当前实际生效的值，替换原来「跟随全局 / 开启 / 关闭」的下拉框和「间隔跟随全局设置」按钮。保存通过已有的 `set-agent-inbox-audit` 写入这个 Agent 自己的值。
- 存储的全局 `inboxAudit` 和 `larkin config` 不变，从没单独设置过的 Agent 继续沿用全局值。
- 说明文字改成和代码（`observeInboxAuditTarget` 和 heartbeat 的 `shouldDispatch`）一致：只检查有人唤醒过 Agent 的群聊和话题；会重读那里的历史找没回答的问题，需要时回复，否则保持安静；没有新唤醒的那一轮会跳过，不消耗额度。

## Related issue

Closes #{{I10}}

## Scope

- In scope：Codex 的两种沙箱和 Fast 模式（按 Agent）；沙箱设置的界面和说明；Inbox 巡检设置改到每个 Agent 的页面。
- Out of scope：其他 runtime 的沙箱；`read-only` 沙箱；巡检本身的行为。
- Compatibility or migration impact：
  - 配置新增两个可选字段，默认值下不写入；旧版本不认识它们，回退前需要先删掉。
  - 在 `workspace-write` 下，Agent 改不了 larkin 的设置，所以 Inbox 巡检无法标记完成，界面上已说明。
  - `package.json` 版本为 0.5.22（#{{P_DASH}} 的 0.5.21 之上再加一个 patch）；合并时我会改成当时的上游版本 + 1 个 patch。

## Validation

以下都在 Linux x64、Bun 1.3.14 下运行。

- [x] Relevant focused tests pass：`test/unit/platform/config-management.test.mjs`、`test/unit/runtime/runtime-adapters.test.mjs`、`test/unit/runtime/codex-model-catalog.test.mjs`、`test/unit/dashboard/dashboard-config-directories.test.mjs`、`test/integration/dashboard/dashboard-inbox-audit-browser.test.mjs`。
- [x] `bun run build` passes.
- [ ] `bun run test` passes：分步跑了它包含的各项：typecheck 通过；`test:frontend` 41 通过；`test:unit` 973 通过、2 失败、1 跳过；`test:integration` 197 通过、18 跳过；`test:e2e` 22 通过。`test:unit` 的 2 个失败是 #{{P_TEST}} 修的环境问题（这次在 AI agent 终端里运行），上游 main 在同一环境下也是这 2 个失败，其余全部通过。
- [x] `bun run licenses:check` passes.
- [x] `bun run publication:check:tree` passes.
- [x] `git diff --check` passes.
- [x] 手工验证：在 fork 上用 macOS + Codex 验收过在后台保存沙箱和 Fast 设置并应用到 Agent；`workspace-write` 下领取消息需要 #{{P_LOCK}}。

## Safety and publication

- [x] This change contains no credentials, private messages, user data, private filesystem paths, generated `dist/`, or release artifacts.
- [x] Security-sensitive details, if any, were reported privately rather than included in this PR.
- [x] I did not create, move, or replace a release tag as part of this ordinary contribution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
LARKIN_KIT_EOF

# 把正文里的 {{I1}}…{{I10}}、{{P_CARD}} 等占位符换成已经知道的编号；还不知道的写成「待补」。
render() {  # $1 源文件  $2 目标文件
  local src="$1" dst="$2" k v
  cp "$src" "$dst"
  for k in "${KEYS[@]}"; do
    v="$(eval echo "\${ISSUE_$k:-}")"
    sed -i.bak "s/{{I$k}}/${v:-待补}/g" "$dst"
  done
  v="${PR_1:-}"; sed -i.bak "s/{{P_TEST}}/${v:-待补}/g" "$dst"
  v="${PR_2:-}"; sed -i.bak "s/{{P_LOCK}}/${v:-待补}/g" "$dst"
  v="${PR_6:-}"; sed -i.bak "s/{{P_GLOBAL}}/${v:-待补}/g" "$dst"
  v="${PR_8:-}"; sed -i.bak "s/{{P_CARD}}/${v:-待补}/g" "$dst"
  v="${PR_9:-}"; sed -i.bak "s/{{P_DASH}}/${v:-待补}/g" "$dst"
  v="${PR_10:-}"; sed -i.bak "s/{{P_SANDBOX}}/${v:-待补}/g" "$dst"
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

echo "== 3. 检查 fork 上的 10 个分支"
for k in "${KEYS[@]}"; do
  b="${BRANCH[$k]}"
  s="$(gh api "repos/$FORK/branches/$b" --jq .commit.sha 2>/dev/null)" || fail "fork 上找不到分支 $b。"
  [ "$s" = "${EXPECTED_SHA[$k]}" ] || fail "分支 $b 现在是 ${s:0:7}，应该是 ${EXPECTED_SHA[$k]:0:7}。"
  echo "   ✓ $b ${s:0:7}"
done

echo "== 4. 检查上游是否已经有我们开过的 issue / PR（避免重复）"
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
echo "   20 份正文都已生成在 $WORK/rendered/"

if [ "$MODE" = check ]; then
  echo
  echo "检查全部通过。将要创建："
  for k in "${KEYS[@]}"; do echo "   issue: ${ISSUE_TITLE[$k]}"; done
  for k in "${KEYS[@]}"; do echo "   PR:    ${PR_TITLE[$k]}  ← $FORK_OWNER:${BRANCH[$k]}"; done
  echo "下一步：bash $0 submit"
  exit 0
fi

echo "== 6. 创建 10 个 issue"
for k in "${KEYS[@]}"; do
  if [ -n "$(eval echo "\${ISSUE_$k:-}")" ]; then echo "   已存在 #$(eval echo "\${ISSUE_$k}") ${ISSUE_TITLE[$k]}"; continue; fi
  url="$(gh issue create -R $UPSTREAM --title "${ISSUE_TITLE[$k]}" --body-file "$WORK/rendered/issue-$k.md")" || fail "创建 issue「${ISSUE_TITLE[$k]}」失败。"
  n="$(num_from_url "$url")"; save "ISSUE_$k" "$n"; echo "   ✓ #$n ${ISSUE_TITLE[$k]}"
  sleep 2
done

echo "== 7. 创建 10 个 PR"
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
