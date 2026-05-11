#!/usr/bin/env node
// claude-bridge CLI — npm-published wrapper around install.sh + bridge-server.mjs.
//
// The npm package ships the same files as the repo (bridge-server.mjs, hooks/,
// skill/, install.sh). `install` copies them to a stable location
// (~/.local/share/claude-bridge) before running install.sh, so the absolute
// paths written into ~/.claude/settings.json survive npm cache cleanup.

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PKG_ROOT = path.resolve(__dirname, "..");
const INSTALL_DIR =
  process.env.CLAUDE_BRIDGE_HOME ??
  path.join(os.homedir(), ".local/share/claude-bridge");

const COPY_ITEMS = [
  "bridge-server.mjs",
  "bridge-stdio.mjs",
  "hooks",
  "skill",
  "install.sh",
  "package.json",
  "BRIDGE.md",
];

function copyPkgToInstallDir() {
  fs.mkdirSync(INSTALL_DIR, { recursive: true });
  for (const item of COPY_ITEMS) {
    const src = path.join(PKG_ROOT, item);
    const dst = path.join(INSTALL_DIR, item);
    if (!fs.existsSync(src)) continue;
    fs.cpSync(src, dst, { recursive: true, force: true });
  }
  // Ensure hook scripts and install.sh are executable
  fs.chmodSync(path.join(INSTALL_DIR, "install.sh"), 0o755);
  const hooksDir = path.join(INSTALL_DIR, "hooks");
  if (fs.existsSync(hooksDir)) {
    for (const f of fs.readdirSync(hooksDir)) {
      fs.chmodSync(path.join(hooksDir, f), 0o755);
    }
  }
}

function runInstallSh(flag) {
  if (!fs.existsSync(path.join(INSTALL_DIR, "install.sh"))) {
    console.error(`claude-bridge not installed yet.`);
    console.error(`Run: npx @vijay2411/claude-bridge install`);
    process.exit(1);
  }
  const r = spawnSync(path.join(INSTALL_DIR, "install.sh"), flag ? [flag] : [], {
    stdio: "inherit",
  });
  return r.status ?? 1;
}

function help() {
  console.log(`claude-bridge — real-time Q&A between Claude sessions

Usage:
  npx @vijay2411/claude-bridge <command>

Commands:
  install      Copy files to ${INSTALL_DIR} and configure hooks, MCP, skill, Desktop
  uninstall    Reverse all install steps (hooks, MCP, skill, Desktop)
  start        Start the bridge server (PID at /tmp/cc-bridge.pid)
  stop         Graceful stop (SIGTERM — sends SSE close event)
  restart      Stop then start
  check        Show status of every component
  serve        Run the bridge in the foreground (no hooks, useful for testing)
  help         Show this message

Env:
  CLAUDE_BRIDGE_HOME    Override install location (default: ~/.local/share/claude-bridge)
  CC_BRIDGE_PORT        Bridge port (default 7400)
  CC_BRIDGE_SESSION     Friendly session name (default: <dir>-<4hex>)

Site:   https://vijay2411.github.io/claude-bridge/
Source: https://github.com/vijay2411/claude-bridge`);
}

const cmd = process.argv[2] ?? "help";

switch (cmd) {
  case "install":
    copyPkgToInstallDir();
    process.exit(runInstallSh());
    break;
  case "uninstall":
    process.exit(runInstallSh("--uninstall"));
    break;
  case "start":
  case "stop":
  case "restart":
  case "check":
    process.exit(runInstallSh(`--${cmd}`));
    break;
  case "serve": {
    // Run from package directly — no persistence needed.
    const server = path.join(PKG_ROOT, "bridge-server.mjs");
    const r = spawnSync("node", [server], { stdio: "inherit" });
    process.exit(r.status ?? 1);
    break;
  }
  case "help":
  case "-h":
  case "--help":
    help();
    process.exit(0);
    break;
  default:
    console.error(`Unknown command: ${cmd}\n`);
    help();
    process.exit(1);
}
