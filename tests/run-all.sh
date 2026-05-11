#!/bin/bash
# Runs every test in tests/ in sequence. Returns non-zero if any test fails.
# Add new tests by dropping them in tests/ — this script auto-discovers them.

set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

OVERALL=0
RESULTS=()

run() {
  local name="$1" cmd="$2"
  echo ""
  echo "── $name ────────────────────────────────────────────────"
  if eval "$cmd"; then
    RESULTS+=("✓ $name")
  else
    RESULTS+=("✗ $name")
    OVERALL=1
  fi
}

chmod +x tests/*.sh hooks/*.sh

for f in tests/test-*.mjs; do
  [ -f "$f" ] || continue
  run "$(basename "$f")" "node '$f'"
done

for f in tests/test-*.sh; do
  [ -f "$f" ] || continue
  run "$(basename "$f")" "'$f'"
done

echo ""
echo "══════════════════════════════════════════════════════════"
echo "Summary:"
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo "══════════════════════════════════════════════════════════"

exit $OVERALL
