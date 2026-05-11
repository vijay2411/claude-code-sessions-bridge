#!/bin/bash
# Verify the PostToolUse and Stop hooks exit silently when the per-session
# MCP cache file says "no", and run normally (no error) when it says "yes".

set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAKE_ID="HOOK-TEST-$$"
MCP_FILE="/tmp/cc-bridge-${FAKE_ID}.mcp"

PASS=0
FAIL=0
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
trap "rm -f $MCP_FILE /tmp/cc-bridge-${FAKE_ID}.*" EXIT

INPUT='{"session_id":"'"$FAKE_ID"'"}'

# MCP=no → hook MUST be silent (no stdout)
echo "no" > "$MCP_FILE"

OUT=$(echo "$INPUT" | "$REPO_DIR/hooks/bridge-hook.sh" 2>&1)
[ -z "$OUT" ] && pass "PostToolUse hook silent when MCP=no" || fail "PostToolUse hook produced output: $OUT"

OUT=$(echo "$INPUT" | "$REPO_DIR/hooks/bridge-stop-hook.sh" 2>&1)
[ -z "$OUT" ] && pass "Stop hook silent when MCP=no" || fail "Stop hook produced output: $OUT"

OUT=$(echo "$INPUT" | "$REPO_DIR/hooks/bridge-prompt-hook.sh" 2>&1)
[ -z "$OUT" ] && pass "UserPromptSubmit hook silent when MCP=no" || fail "UserPromptSubmit hook produced output: $OUT"

# MCP=yes, bridge not running → hooks should still not error out
echo "yes" > "$MCP_FILE"
echo "$INPUT" | "$REPO_DIR/hooks/bridge-hook.sh"        >/dev/null 2>&1 && pass "PostToolUse hook exits 0 when MCP=yes" || fail "PostToolUse hook exited non-zero"
echo "$INPUT" | "$REPO_DIR/hooks/bridge-stop-hook.sh"   >/dev/null 2>&1 && pass "Stop hook exits 0 when MCP=yes" || fail "Stop hook exited non-zero"
echo "$INPUT" | "$REPO_DIR/hooks/bridge-prompt-hook.sh" >/dev/null 2>&1 && pass "UserPromptSubmit hook exits 0 when MCP=yes" || fail "UserPromptSubmit hook exited non-zero"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
