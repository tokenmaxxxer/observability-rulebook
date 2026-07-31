#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/../observability-cardinality-budget/hooks/cardinality-budget-gate.sh"
pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }
run() { # want name path content
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$3")"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "$3" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$4")" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$1" "$got" "$2"
}
run allow phase1-mentions-cardinality docs/issue-7/proposals/x-observability.md '예비 고카디널리티 후보: user_id, request_id.'
run deny  phase1-missing docs/issue-7/proposals/x-observability.md '방법론만 언급, 고유 차원 목록 없음.'
run allow phase2-full docs/issue-7/reports/observability.md '카디널리티: user_id는 hash 처리, request_id는 drop.'
run deny  phase2-placeholder docs/issue-7/reports/observability.md '카디널리티: N/A.'
run deny  phase2-missing-policy docs/issue-7/reports/observability.md '카디널리티 후보: user_id.'
run allow foreign-path docs/issue-7/reports/pricing.md 'irrelevant'
printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
