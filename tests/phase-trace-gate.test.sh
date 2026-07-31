#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/../observability-phase-trace/hooks/phase-trace-gate.sh"
pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }
run() { # want name path content statefile_json_or_empty
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$3")"
  if [ -n "${5:-}" ]; then mkdir -p "$td/.observability-phase1-methods"; printf '%s' "$5" > "$td/.observability-phase1-methods/7.json"; fi
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "$3" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$4")" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$1" "$got" "$2"
}
run allow no-state-file docs/issue-7/reports/observability.md 'RED 채택.' ''
run allow state-no-deviation docs/issue-7/reports/observability.md 'RED 채택.' '{"issue":"7","methodology_named":true}'
run allow deviation-with-reason docs/issue-7/reports/observability.md 'USE로 변경. 이유: 표면이 resource-bound로 재분류되었기 때문.' '{"issue":"7","methodology_named":true}'
run deny  deviation-no-reason docs/issue-7/reports/observability.md 'USE로 변경(이탈).' '{"issue":"7","methodology_named":true}'
run allow foreign-path docs/issue-7/reports/pricing.md 'irrelevant' ''
printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
