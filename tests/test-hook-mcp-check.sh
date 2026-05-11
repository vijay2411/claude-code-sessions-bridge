#!/bin/bash
# Verify the PostToolUse, Stop, and UserPromptSubmit hooks correctly handle
# the per-session MCP cache file at /tmp/claude-bridge-${SESSION_ID}.mcp.
#
# Three cases per hook:
#   1. cache=no    → exit silently (no stdout)
#   2. cache=yes   → run normally, exit 0
#   3. cache missing (mid-session install)
#        - if `claude mcp list` shows bridge → seed cache="yes", proceed
#        - if it doesn't                     → seed cache="no", exit silently

set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAKE_ID="HOOK-TEST-$$"
MCP_FILE="/tmp/claude-bridge-${FAKE_ID}.mcp"
STUB_DIR=$(mktemp -d)

PASS=0
FAIL=0
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
trap "rm -rf $STUB_DIR /tmp/claude-bridge-${FAKE_ID}.*" EXIT

INPUT='{"session_id":"'"$FAKE_ID"'"}'

# ── Stub harness ───────────────────────────────────────────────────────────
# Each stub matches the substring grep used in the hook: `grep -q "bridge"`.
make_stub() {
  local mode="$1"  # "present" or "absent"
  cat > "$STUB_DIR/claude" <<EOF
#!/bin/sh
case "\$1 \$2" in
  "mcp list")
$( [ "$mode" = "present" ] && echo '    echo "bridge: SSE → http://localhost:7400/sse"' || echo '    echo "no MCP servers configured"' )
    exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$STUB_DIR/claude"
}

# ── Case 1: cache=no → silent ──────────────────────────────────────────────
echo "no" > "$MCP_FILE"
for hook in bridge-hook.sh bridge-stop-hook.sh bridge-prompt-hook.sh; do
  OUT=$(echo "$INPUT" | "$REPO_DIR/hooks/$hook" 2>&1)
  [ -z "$OUT" ] && pass "${hook%.sh}: cache=no → silent" || fail "${hook%.sh}: cache=no produced output: $OUT"
done

# ── Case 2: cache=yes → exits 0 (bridge not running, fine) ─────────────────
echo "yes" > "$MCP_FILE"
for hook in bridge-hook.sh bridge-stop-hook.sh bridge-prompt-hook.sh; do
  echo "$INPUT" | "$REPO_DIR/hooks/$hook" >/dev/null 2>&1 \
    && pass "${hook%.sh}: cache=yes → exits 0" \
    || fail "${hook%.sh}: cache=yes exited non-zero"
done

# ── Case 3a: cache missing + bridge MCP absent → silent + seed cache="no" ──
rm -f "$MCP_FILE"
make_stub absent
for hook in bridge-hook.sh bridge-stop-hook.sh bridge-prompt-hook.sh; do
  rm -f "$MCP_FILE"
  OUT=$(echo "$INPUT" | PATH="$STUB_DIR:$PATH" "$REPO_DIR/hooks/$hook" 2>&1)
  if [ -z "$OUT" ] && [ "$(cat "$MCP_FILE" 2>/dev/null)" = "no" ]; then
    pass "${hook%.sh}: cache missing + bridge absent → silent + seeds 'no'"
  else
    fail "${hook%.sh}: expected silent + cache='no', got output='$OUT' cache='$(cat "$MCP_FILE" 2>/dev/null)'"
  fi
done

# ── Case 3b: cache missing + bridge MCP present → seed cache="yes", proceed ──
make_stub present
for hook in bridge-hook.sh bridge-stop-hook.sh bridge-prompt-hook.sh; do
  rm -f "$MCP_FILE"
  echo "$INPUT" | PATH="$STUB_DIR:$PATH" "$REPO_DIR/hooks/$hook" >/dev/null 2>&1
  if [ "$(cat "$MCP_FILE" 2>/dev/null)" = "yes" ]; then
    pass "${hook%.sh}: cache missing + bridge present → seeds 'yes'"
  else
    fail "${hook%.sh}: expected cache='yes', got cache='$(cat "$MCP_FILE" 2>/dev/null)'"
  fi
done

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
