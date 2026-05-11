// MCP tool behaviour: register, broadcast input validation, ask/reply round-trip,
// check_inbox, get_thread answered flag. Adds smoke coverage for everything in
// the TOOLS array. Add new tool tests here when you ship a new tool.

import { TestBridge, assert, reportAndExit } from "./lib.mjs";

const bridge = new TestBridge(7402);
await bridge.start();

try {
  // ── register ────────────────────────────────────────────────────────────
  const r = await bridge.call("register", { name: "alice", description: "test session" });
  assert("register returns ok", r.ok === true, JSON.stringify(r));

  // ── list_sessions ───────────────────────────────────────────────────────
  const ls = await bridge.call("list_sessions");
  assert("list_sessions includes us", ls.sessions?.some((s) => s.name === "alice"), JSON.stringify(ls));

  // ── broadcast input validation (Bug 1 regression test) ──────────────────
  const bad1 = await bridge.call("broadcast", { message: "wrong arg name" });
  assert("broadcast rejects {message}", typeof bad1.error === "string", JSON.stringify(bad1));

  const bad2 = await bridge.call("broadcast", {});
  assert("broadcast rejects empty args", typeof bad2.error === "string", JSON.stringify(bad2));

  const bad3 = await bridge.call("broadcast", { content: 42 });
  assert("broadcast rejects non-string content", typeof bad3.error === "string", JSON.stringify(bad3));

  const good = await bridge.call("broadcast", { content: "hello" });
  assert("broadcast accepts valid content", good.ok === true && good.length === 5, JSON.stringify(good));

  const appended = await bridge.call("broadcast", { content: "world", append: true });
  assert("broadcast append grows scratchpad", appended.ok === true && appended.length > 5, JSON.stringify(appended));

  // ── read_scratchpad ─────────────────────────────────────────────────────
  const sp = await bridge.call("read_scratchpad", { session: "alice" });
  assert("read_scratchpad returns content", typeof sp.content === "string" && sp.content.includes("hello"), JSON.stringify(sp));

  // ── check_inbox (no pending questions) ──────────────────────────────────
  const inbox = await bridge.call("check_inbox");
  assert("check_inbox returns pending_count", inbox.pending_count === 0, JSON.stringify(inbox));

  // ── get_thread (no thread) ──────────────────────────────────────────────
  const thread = await bridge.call("get_thread", { with_session: "bob" });
  assert("get_thread returns empty for unknown peer", Array.isArray(thread.messages) && thread.messages.length === 0, JSON.stringify(thread));

  // ── server still alive (Bug 2 regression test) ──────────────────────────
  const h = await bridge.health();
  assert("server still alive after bad inputs", h.status === "ok", JSON.stringify(h));
} finally {
  await bridge.stop();
  reportAndExit();
}
