#!/usr/bin/env bash
# Regression guard (issue-13 section g): assert stale role-names/ghost
# filenames from before the core-canon reference switch (issue-2) never
# reappear in README.md or observability/.claude-plugin/plugin.json as if
# naming a currently-shipped file. As of issue-13 these names appear only
# in README.md's past-tense history note ("no longer vendored here") —
# this test pins that: the files those names would refer to must not
# exist under this repo's observability*/ trees.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$HERE/.." && pwd -P)"
pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-40s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-40s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

GHOSTS="trailer-gate.sh record-fields-gate.sh handbook-trigger-gate.sh warrant-hunter"

for name in $GHOSTS; do
  hit="$(find "$ROOT" -path "$ROOT/.git" -prune -o -type f -name "$name" -print 2>/dev/null | head -1)"
  got="absent"; [ -n "$hit" ] && got="present"
  report absent "$got" "no-shipped-file:$name"
done

# README.md/plugin.json may still mention the names in past-tense history
# prose (e.g. "no longer vendored here"), but never as a present-tense
# "## Layout"-style bullet claiming the file ships today. Heuristic: any
# mention must be accompanied by one of these qualifying phrases nearby.
QUALIFIERS="no longer vendored|core canon now|no longer ship|removed"

check_mentions() {
  f="$1"
  [ -f "$f" ] || return 0
  for name in $GHOSTS; do
    grep -n "$name" "$f" >/dev/null 2>&1 || continue
    n="$(grep -n "$name" "$f" | head -1 | cut -d: -f1)"
    window="$(sed -n "${n},$((n+2))p" "$f")"
    if echo "$window" | grep -qiE "$QUALIFIERS"; then
      echo "ok"
    else
      echo "bad:$f:$name"
    fi
  done
}

bad="$(check_mentions "$ROOT/README.md"; check_mentions "$ROOT/observability/.claude-plugin/plugin.json")"
got="clean"; echo "$bad" | grep -q '^bad:' && got="unqualified-mention-found"
report clean "$got" "ghost-name-mentions-are-qualified-history-only"

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
