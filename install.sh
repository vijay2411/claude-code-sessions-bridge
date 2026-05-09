#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
PORT="${CC_BRIDGE_PORT:-7400}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

# ── Argument parsing ────────────────────────────────────────────────────────

ACTION="install"
case "${1:-}" in
  --uninstall) ACTION="uninstall" ;;
  --check)     ACTION="check" ;;
  --help|-h)
    echo "Usage: ./install.sh [--uninstall | --check | --help]"
    echo ""
    echo "  (no args)    Install cc-bridge hooks, MCP server, and protocol docs"
    echo "  --uninstall  Remove all cc-bridge configuration"
    echo "  --check      Verify installation without changing anything"
    exit 0
    ;;
esac

# ── Prerequisites ───────────────────────────────────────────────────────────

check_prereqs() {
  local all_ok=true

  if command -v node &>/dev/null; then
    local ver
    ver=$(node -e "console.log(process.version.slice(1).split('.')[0])")
    if [ "$ver" -ge 18 ] 2>/dev/null; then
      ok "Node.js v$(node -e "process.stdout.write(process.version)")"
    else
      fail "Node.js >= 18 required (found v$(node -e "process.stdout.write(process.version)"))"
      all_ok=false
    fi
  else
    fail "Node.js not found (install from https://nodejs.org)"
    all_ok=false
  fi

  if command -v jq &>/dev/null; then
    ok "jq $(jq --version 2>&1)"
  else
    fail "jq not found (brew install jq)"
    all_ok=false
  fi

  if command -v curl &>/dev/null; then
    ok "curl available"
  else
    fail "curl not found"
    all_ok=false
  fi

  if command -v claude &>/dev/null; then
    ok "Claude Code CLI available"
  else
    fail "Claude Code CLI not found (install from https://docs.anthropic.com/en/docs/claude-code)"
    all_ok=false
  fi

  $all_ok
}

# ── Hook configuration ─────────────────────────────────────────────────────

HOOK_MAP='
{
  "SessionStart": "bridge-start-hook.sh",
  "UserPromptSubmit": "bridge-prompt-hook.sh",
  "PostToolUse": "bridge-hook.sh",
  "Stop": "bridge-stop-hook.sh",
  "SessionEnd": "bridge-end-hook.sh"
}
'

install_hooks() {
  mkdir -p "$(dirname "$SETTINGS")"

  if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
  fi

  local tmp
  tmp=$(mktemp)
  cp "$SETTINGS" "$tmp"

  for event in SessionStart UserPromptSubmit PostToolUse Stop SessionEnd; do
    local script
    script=$(echo "$HOOK_MAP" | jq -r --arg e "$event" '.[$e]')
    local cmd="$REPO_DIR/hooks/$script"

    # Check if bridge hook already exists for this event
    local existing
    existing=$(jq -r --arg e "$event" '
      .hooks[$e] // [] | map(select(.hooks[]?.command | test("bridge"))) | length
    ' "$tmp" 2>/dev/null || echo "0")

    if [ "$existing" != "0" ]; then
      # Update existing bridge hook path
      jq --arg e "$event" --arg cmd "$cmd" '
        .hooks[$e] = [.hooks[$e][] | if (.hooks[]?.command | test("bridge")) then .hooks[0].command = $cmd else . end]
      ' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
    else
      # Add new hook entry
      jq --arg e "$event" --arg cmd "$cmd" '
        .hooks //= {} |
        .hooks[$e] //= [] |
        .hooks[$e] += [{"matcher": "", "hooks": [{"type": "command", "command": $cmd}]}]
      ' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
    fi
  done

  mv "$tmp" "$SETTINGS"
  ok "Hooks configured in $SETTINGS"
}

remove_hooks() {
  if [ ! -f "$SETTINGS" ]; then
    warn "No settings.json found"
    return
  fi

  local tmp
  tmp=$(mktemp)

  jq '
    .hooks //= {} |
    .hooks |= with_entries(
      .value |= map(select(.hooks | all(.command | test("bridge") | not)))
    ) |
    .hooks |= with_entries(select(.value | length > 0))
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  ok "Bridge hooks removed from $SETTINGS"
}

check_hooks() {
  if [ ! -f "$SETTINGS" ]; then
    fail "No settings.json found"
    return 1
  fi

  local count
  count=$(jq '[.hooks // {} | to_entries[] | .value[] | select(.hooks[]?.command | test("bridge"))] | length' "$SETTINGS" 2>/dev/null || echo "0")

  if [ "$count" -eq 5 ]; then
    ok "All 5 hooks configured"
  elif [ "$count" -gt 0 ]; then
    warn "$count/5 hooks configured (run install to fix)"
  else
    fail "No bridge hooks found"
    return 1
  fi
}

# ── MCP server ──────────────────────────────────────────────────────────────

install_mcp() {
  if claude mcp list 2>/dev/null | grep -q "bridge"; then
    ok "MCP server already registered"
  else
    claude mcp add --transport sse --scope user bridge "http://localhost:${PORT}/sse" 2>/dev/null
    ok "MCP server registered (scope: user, port: $PORT)"
  fi
}

remove_mcp() {
  claude mcp remove bridge 2>/dev/null && ok "MCP server removed" || warn "MCP server was not registered"
}

check_mcp() {
  if claude mcp list 2>/dev/null | grep -q "bridge"; then
    ok "MCP server registered"
  else
    fail "MCP server not registered"
    return 1
  fi
}

# ── CLAUDE.md protocol docs ────────────────────────────────────────────────

install_claude_md() {
  mkdir -p "$(dirname "$CLAUDE_MD")"

  if [ -f "$CLAUDE_MD" ] && grep -q "Bridge Communication Protocol" "$CLAUDE_MD" 2>/dev/null; then
    ok "BRIDGE.md already in CLAUDE.md"
  else
    echo "" >> "$CLAUDE_MD"
    cat "$REPO_DIR/BRIDGE.md" >> "$CLAUDE_MD"
    ok "BRIDGE.md appended to $CLAUDE_MD"
  fi
}

remove_claude_md() {
  if [ ! -f "$CLAUDE_MD" ]; then
    warn "No CLAUDE.md found"
    return
  fi

  # Remove everything from "# Bridge Communication Protocol" to the next top-level heading or EOF
  local tmp
  tmp=$(mktemp)
  awk '
    /^# Bridge Communication Protocol/ { skip=1; next }
    skip && /^# / { skip=0 }
    !skip { print }
  ' "$CLAUDE_MD" > "$tmp" && mv "$tmp" "$CLAUDE_MD"

  ok "Bridge protocol docs removed from $CLAUDE_MD"
}

check_claude_md() {
  if [ -f "$CLAUDE_MD" ] && grep -q "Bridge Communication Protocol" "$CLAUDE_MD" 2>/dev/null; then
    ok "Protocol docs in CLAUDE.md"
  else
    fail "Protocol docs not in CLAUDE.md"
    return 1
  fi
}

# ── Claude Desktop app ──────────────────────────────────────────────────────

install_desktop() {
  # Only on macOS
  if [ "$(uname)" != "Darwin" ]; then
    warn "Claude Desktop app config skipped (not macOS)"
    return
  fi

  local config_dir
  config_dir="$(dirname "$DESKTOP_CONFIG")"

  if [ ! -d "$config_dir" ]; then
    warn "Claude Desktop app not found (no config directory)"
    return
  fi

  if [ ! -f "$DESKTOP_CONFIG" ]; then
    echo '{}' > "$DESKTOP_CONFIG"
  fi

  # Check if cc-bridge is already configured
  if jq -e '.mcpServers["cc-bridge"]' "$DESKTOP_CONFIG" &>/dev/null; then
    # Update the path in case repo moved
    local tmp
    tmp=$(mktemp)
    jq --arg path "$REPO_DIR/bridge-stdio.mjs" '
      .mcpServers["cc-bridge"].args = [$path]
    ' "$DESKTOP_CONFIG" > "$tmp" && mv "$tmp" "$DESKTOP_CONFIG"
    ok "Desktop app config updated (path refreshed)"
  else
    local tmp
    tmp=$(mktemp)
    jq --arg path "$REPO_DIR/bridge-stdio.mjs" '
      .mcpServers //= {} |
      .mcpServers["cc-bridge"] = {
        "command": "node",
        "args": [$path]
      }
    ' "$DESKTOP_CONFIG" > "$tmp" && mv "$tmp" "$DESKTOP_CONFIG"
    ok "Desktop app config added (relaunch the app to activate)"
  fi
}

remove_desktop() {
  if [ ! -f "$DESKTOP_CONFIG" ]; then
    warn "No Desktop app config found"
    return
  fi

  if jq -e '.mcpServers["cc-bridge"]' "$DESKTOP_CONFIG" &>/dev/null; then
    local tmp
    tmp=$(mktemp)
    jq 'del(.mcpServers["cc-bridge"]) | if .mcpServers == {} then del(.mcpServers) else . end' "$DESKTOP_CONFIG" > "$tmp" && mv "$tmp" "$DESKTOP_CONFIG"
    ok "Desktop app config removed (relaunch the app)"
  else
    warn "cc-bridge not in Desktop app config"
  fi
}

check_desktop() {
  if [ "$(uname)" != "Darwin" ]; then
    warn "Claude Desktop app check skipped (not macOS)"
    return
  fi

  if [ ! -f "$DESKTOP_CONFIG" ]; then
    warn "No Desktop app config found"
    return
  fi

  if jq -e '.mcpServers["cc-bridge"]' "$DESKTOP_CONFIG" &>/dev/null; then
    local configured_path
    configured_path=$(jq -r '.mcpServers["cc-bridge"].args[0]' "$DESKTOP_CONFIG")
    if [ -f "$configured_path" ]; then
      ok "Desktop app configured (stdio adapter: $configured_path)"
    else
      fail "Desktop app configured but stdio adapter not found at: $configured_path"
    fi
  else
    warn "Desktop app not configured (optional — run install to add)"
  fi
}

# ── Bridge server status ───────────────────────────────────────────────────

check_bridge() {
  if curl -sf --max-time 1 "http://localhost:${PORT}/health" &>/dev/null; then
    local sessions
    sessions=$(curl -sf --max-time 1 "http://localhost:${PORT}/health" | jq '.sessions | length')
    ok "Bridge running on port $PORT ($sessions active sessions)"
  else
    warn "Bridge not running (start with: node $REPO_DIR/bridge-server.mjs)"
  fi
}

# ── Main ────────────────────────────────────────────────────────────────────

case "$ACTION" in
  install)
    echo ""
    echo "cc-bridge installer"
    echo "==================="
    echo ""
    echo "Checking prerequisites..."
    if ! check_prereqs; then
      echo ""
      fail "Missing prerequisites. Install them and try again."
      exit 1
    fi
    echo ""
    echo "Installing..."
    chmod +x "$REPO_DIR"/hooks/*.sh
    echo ""
    echo "Claude Code CLI:"
    install_hooks
    install_mcp
    install_claude_md
    echo ""
    echo "Claude Desktop App:"
    install_desktop
    echo ""
    echo "Done! Start the bridge:"
    echo ""
    echo "  node $REPO_DIR/bridge-server.mjs"
    echo ""
    echo "CLI sessions auto-register. Desktop app needs a relaunch,"
    echo "then tell it: \"Register on the bridge as 'desktop'\""
    echo ""
    ;;

  uninstall)
    echo ""
    echo "cc-bridge uninstaller"
    echo "====================="
    echo ""
    remove_hooks
    remove_mcp
    remove_claude_md
    remove_desktop
    rm -f /tmp/cc-bridge-*
    ok "Temp files cleaned"
    echo ""
    echo "Done. Stop any running bridge server manually (kill the process)."
    echo "Relaunch Claude Desktop app if it was configured."
    echo ""
    ;;

  check)
    echo ""
    echo "cc-bridge status"
    echo "================"
    echo ""
    echo "Prerequisites:"
    check_prereqs || true
    echo ""
    echo "Claude Code CLI:"
    check_hooks || true
    check_mcp || true
    check_claude_md || true
    echo ""
    echo "Claude Desktop App:"
    check_desktop
    echo ""
    echo "Server:"
    check_bridge
    echo ""
    ;;
esac
