// Verify SIGTERM sends `event: close` to SSE clients before exiting,
// rather than terminating the connection with a TCP reset. This is what
// prevents connected Claude Code sessions from crashing on bridge restart.

import { TestBridge, assert, reportAndExit, sleep } from "./lib.mjs";
import http from "node:http";
import fs from "node:fs";

const LOG = "/tmp/claude-bridge-sse-close-test.log";
fs.writeFileSync(LOG, "");

const bridge = new TestBridge(7403);
await bridge.start();

// Open a second SSE connection that we'll watch for the close event
const sseTap = http.get(`http://localhost:7403/sse`, (res) => {
  res.on("data", (chunk) => fs.appendFileSync(LOG, chunk.toString()));
});
await sleep(500);

await bridge.stop({ signal: "SIGTERM" });
await sleep(500);

const log = fs.readFileSync(LOG, "utf8");
assert("graceful shutdown emits 'event: close'", log.includes("event: close"), `log was: ${log.slice(0, 200)}`);
assert("close event includes shutdown reason", /data: bridge shutting down/.test(log), `log was: ${log.slice(0, 200)}`);

try { sseTap.destroy(); } catch {}
fs.unlinkSync(LOG);

reportAndExit();
