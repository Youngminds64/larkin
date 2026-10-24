import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "bun:test";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const configApi = require("../../../dist/platform/config.cjs");
const { ContextPromptBuilder } = await import("../../../dist/agent/context-prompt.mjs");
const APP = "cli_replyModeA1";
const OTHER = "cli_replyModeB2";

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "larkin-reply-mode-config-"));
  fs.writeFileSync(path.join(root, "config.json"), `${JSON.stringify({
    version: 4, serverId: "server-reply-mode", mentionPolicy: "require", activeAgent: APP,
    agents: { [APP]: { runtime: "codex", model: "gpt-5.6-sol" }, [OTHER]: { runtime: "claude", model: "sonnet" } },
  }, null, 2)}\n`, { mode: 0o600 });
  return { root, env: { LARKIN_CONFIG_DIR: root } };
}

test("global reply mode is stored once, projected onto every Agent and requires re-apply", () => {
  const { root, env } = fixture();
  try {
    const before = configApi.loadConfig(env).config;
    assert.equal(before.replyMode, undefined);
    assert.equal(before.agents[APP].replyMode, undefined);
    assert.equal(configApi.safeConfigView(before).replyMode, null);
    const signatureBefore = configApi.runtimeConfigSignature(before, APP);

    const result = configApi.mutateConfig(env, { kind: "set-global-reply-mode", value: "cli" }, { kind: "user" });
    assert.equal(result.changedScope, "global");
    assert.equal(result.applyState, "saved_not_applied");
    const stored = JSON.parse(fs.readFileSync(path.join(root, "config.json"), "utf8"));
    assert.equal(stored.replyMode, "cli");
    assert.equal("replyMode" in stored.agents[APP], false);

    const after = configApi.loadConfig(env).config;
    assert.equal(after.replyMode, "cli");
    assert.equal(after.agents[APP].replyMode, "cli");
    assert.equal(after.agents[OTHER].replyMode, "cli");
    assert.equal(configApi.safeConfigView(after).replyMode, "cli");
    assert.notEqual(configApi.runtimeConfigSignature(after, APP), signatureBefore);

    assert.throws(() => configApi.mutateConfig(env, { kind: "set-global-reply-mode", value: "both" }, { kind: "user" }), /card\/cli/);
    fs.writeFileSync(path.join(root, "config.json"), `${JSON.stringify({ ...stored, replyMode: "bogus" })}\n`, { mode: 0o600 });
    assert.throws(() => configApi.loadConfig(env), /config\.replyMode/);
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});

test("a per-session reply mode overrides the prompt builder default", () => {
  const builder = new ContextPromptBuilder({ replyMode: "card" });
  const input = { agentId: APP, runtime: "codex" };
  assert.equal(builder.build(input).version, "larkin-standing-v35-card");
  assert.equal(builder.build({ ...input, replyMode: "cli" }).version, "larkin-standing-v34");
  assert.equal(new ContextPromptBuilder().build({ ...input, replyMode: "card" }).version, "larkin-standing-v35-card");
});
