#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/../observability-explorability/hooks/explorability-gate.sh"
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
run allow phase1-mentions-explorability docs/issue-7/proposals/x-observability.md '탐색가능성 확보: 사전 미정의 질문에도 답할 수 있다.'
run deny  phase1-missing docs/issue-7/proposals/x-observability.md '방법론만 언급.'
run allow phase2-with-example docs/issue-7/reports/observability.md '애드혹 쿼리 예시: SELECT count(*) FROM spans WHERE status=500 GROUP BY route;'
run deny  phase2-no-example docs/issue-7/reports/observability.md '애드혹 쿼리 지원한다.'
run deny  phase2-missing docs/issue-7/reports/observability.md '방법론만 언급.'
run allow foreign-path docs/issue-7/reports/pricing.md 'irrelevant'
printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
