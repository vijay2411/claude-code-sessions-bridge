# cc-bridge

**Real-time Q&A between Claude Code sessions -- no copy-paste, no context switching, no human message routing.**

```
Terminal 1 (api-builder)                          Terminal 2 (frontend)
────────────────────────                          ────────────────────
Building auth middleware...                       Need JWT config from api-builder...

                                                  > ask(to="api-builder",
                                                  >   question="What middleware validates
                                                  >   JWT tokens and where is the signing
                                                  >   secret configured?")

  BRIDGE QUESTION from "frontend":                (blocked, waiting...)
  "What middleware validates JWT tokens..."

  > reply(message_id="a1b2c3d4",
  >   answer="Auth middleware is in
  >   /src/middleware/auth.ts, JWT_SECRET
  >   from .env, 24h access / 7d refresh...")
                                                  Got answer! Continuing with auth
                                                  integration using the exact config...
```

Two sessions. One question. Zero human involvement.

---

## ✨ What this is

- **MCP server** connecting Claude Code sessions via blocking ask/reply
- **Auto-registration** via hooks -- sessions join the bridge automatically on start
- **Three-layer question delivery** -- PostToolUse + Stop hook + manual poke covers ~95% of cases
- **Thread history with deduplication** -- no repeated questions, full conversation context
- **Scratchpad broadcasting** -- async context sharing for decisions and constraints
- **Self-healing reconnection** -- hooks detect dropped registrations and re-register
- **SSE keepalive** -- 25s pings prevent idle disconnects
- **Zero dependencies** -- pure Node.js stdlib, no npm install needed

## ❌ What this isn't

- :no_entry_sign: Not a multi-machine or networked solution (localhost only)
- :no_entry_sign: Not persistent storage (in-memory, 30-day GC, lost on server restart)
- :no_entry_sign: Not a general MCP server framework
- :no_entry_sign: Not a message queue or pub/sub system
- :no_entry_sign: Not a replacement for shared files/git for large artifacts
- :no_entry_sign: Not Windows-compatible (uses /tmp, bash hooks)
- :no_entry_sign: Not a Claude Code plugin/extension -- it's hooks + standalone MCP server

## :muscle: Why this exists

You're running 2-5 Claude Code sessions on the same codebase. They make conflicting decisions. They duplicate work. One blocks on a question only another can answer. You become the human message router -- copy-pasting between terminals, losing your own train of thought, context-switching until you forget what *you* were doing.

| Alternative | Limitation |
|---|---|
| Copy-paste between terminals | Manual, error-prone, you become the bottleneck |
| Shared CLAUDE.md file | Async only, no blocking Q&A, no interruption when updated |
| Git commits as messages | Too slow, requires commit-push-pull per question |
| Worktrees with shared notes | No interruption mechanism, idle sessions never see updates |
| Custom scripts + file watchers | No blocking semantics, no thread history, no dedup |

I wanted sessions to talk to each other without me in the loop. So I built it.

## :busts_in_silhouette: Who this is for

### ✅ Use this if you:
- Run 2+ Claude Code sessions on the same machine simultaneously
- Want sessions to coordinate decisions without your intervention
- Work on multi-component projects (API + frontend + infra + tests)
- Want blocking Q&A -- asker waits for a real answer, not a stale file
- Prefer zero-dependency tools that just work

### ❌ Don't use this if you:
- Only ever run one Claude Code session at a time
- Need cross-machine or team-wide collaboration
- Want persistent message history across server restarts
- Need Windows support
- Want a production message broker (this is a dev tool)

## :wrench: Tech stack

| Layer | Tech |
|---|---|
| Runtime | Node.js >= 18 |
| Server transport | MCP over SSE + HTTP REST |
| Hook integration | Bash (jq + curl) |
| IPC | /tmp files (name files, stamp files) |
| Dependencies | None (Node.js stdlib only) |
| State | In-memory (30-day GC) |

## :warning: Requirements

| Requirement | Why | How to verify |
|---|---|---|
| Node.js >= 18 | Uses `node:` imports, `crypto.randomUUID` | `node -e "console.log(process.version)"` |
| jq | Hook scripts parse JSON from Claude Code's stdin | `jq --version` |
| curl | Hook scripts call bridge REST endpoints | `curl --version` |
| Claude Code CLI | Hooks API is the integration layer; `claude mcp add` registers the server | `claude --version` |
| macOS or Linux | Uses /tmp for IPC, bash for hooks | `uname` |

## :brain: How it works under the hood

### Big picture

```
Session A (Claude Code)        cc-bridge (:7400)           Session B (Claude Code)
───────────────────────        ─────────────────           ───────────────────────

SessionStart hook ──────────→  (bridge running)  ←──────── SessionStart hook
  register(name, sid)             MCP over SSE       register(name, sid)

User asks something...         7 MCP tools:            User asks something...
Claude works, calls tools      register, ask,          Claude works, calls tools
                               reply, list_sessions,
                               get_thread, broadcast,
                               read_scratchpad

ask(to="B", question) ──────→ queue question ──────────→ PostToolUse hook fires
  (blocks, waiting)            messages Map              curl /pending → sees Q
                               ┌──────────┐              injects into context
                               │ question │              via additionalContext
                               │ (no ans) │
                               └──────────┘
                                                         B reads Q, calls reply()
                               ┌──────────┐
                               │ question │  ←────────── reply(id, answer)
                               │ answer ✓ │
                               └──────────┘
  ←──── answer returned ──────
  (continues work)

If B is idle:                  Stop hook fires ─────────→ blocks idle, re-injects Q
                               {"decision":"block",       B wakes up, answers
                                "reason": "..."}
```

### In one paragraph

cc-bridge runs a single Node.js HTTP server speaking two protocols. MCP over SSE provides tools (ask, reply, register, broadcast) that Claude Code sessions call directly. Plain HTTP REST (`/pending`, `/whoami`, `/health`) serves bash hook scripts that can't speak MCP. When session A calls `ask()`, the server queues the question and blocks A's tool call for up to 5 minutes. B's PostToolUse hook polls `/pending` on every tool use, discovers the question, and injects it into B's context via `additionalContext` JSON. If B finishes a turn before answering, the Stop hook catches the transition and blocks it. B calls `reply()`, which unblocks A instantly.

### Why this architecture works

- **Single server, two protocols** -- bash hooks can't speak MCP (no SSE client), so they use REST. Both read/write the same in-memory Maps.
- **Blocking `ask()` with server-side long-poll** -- avoids client-side polling loops. Asker's tool call simply doesn't return until the answer arrives.
- **Stop hook catches the idle gap** -- PostToolUse only fires during active tool use. The Stop hook fires right before Claude goes idle, covering the ~90% case.
- **In-memory state with 30-day GC** -- no persistence layer to manage, no database dependency. Hourly sweep prunes stale data.
- **25s SSE keepalive pings** -- Claude Code's MCP client drops idle connections after ~5 minutes. Server-side comment pings keep TCP warm.

### Things you can configure

```bash
# Port (default 7400)
export CC_BRIDGE_PORT=8888
node bridge-server.mjs --port 8888

# Override auto-generated session name
export CC_BRIDGE_SESSION=api-builder
```

## :book: More

- **[USAGE.md](USAGE.md)** -- installation, configuration, tool reference, troubleshooting
- **[BRIDGE.md](BRIDGE.md)** -- protocol docs (what Claude reads to know how to use the bridge)
- **[LICENSE](LICENSE)** -- MIT

## :construction: Status

Works. Built and battle-tested across 2-5 concurrent sessions daily. macOS primary, Linux should work (untested). In-memory only -- server restart loses state. PRs welcome.
