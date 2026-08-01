#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/../observability-phase-trace/hooks/phase-trace-gate.sh"
export CLAUDE_PLUGIN_ROOT_CORE="/home/jwjung/tokenmaxxxer/tokenmaxxxer-core/core"
pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

# run want name path content statefile_json_or_empty [tool_input_json] [tool_name] [existing_content] [kill_switch_val]
run() {
  want="$1"; name="$2"; path="$3"; content="$4"; state="${5:-}"; ti_override="${6:-}"; tool="${7:-Write}"; existing="${8:-}"; kswitch="${9:-}"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$path")"
  if [ -n "$state" ]; then mkdir -p "$td/.observability-phase1-methods"; printf '%s' "$state" > "$td/.observability-phase1-methods/7.json"; fi
  if [ -n "$existing" ]; then printf '%s' "$existing" > "$td/$path"; fi
  if [ -n "$ti_override" ]; then
    ti="$ti_override"
  else
    ti="$(python3 -c 'import json,sys; print(json.dumps({"file_path": sys.argv[1], "content": sys.argv[2]}))' "$path" "$content")"
  fi
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": json.loads(sys.argv[2]), "cwd": sys.argv[3]}))' "$tool" "$ti" "$td")"
  printf '%s' "$payload" \
    | env CLAUDE_PROJECT_DIR="$td" OBSERVABILITY_PHASE_TRACE_GATE_OFF="$kswitch" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

# run_raw want name path payload_json state [existing_content] [kill_switch_val]
run_raw() {
  want="$1"; name="$2"; path="$3"; payload="$4"; state="${5:-}"; existing="${6:-}"; kswitch="${7:-}"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  if [ -n "$path" ]; then mkdir -p "$(dirname "$td/$path")"; fi
  if [ -n "$state" ]; then mkdir -p "$td/.observability-phase1-methods"; printf '%s' "$state" > "$td/.observability-phase1-methods/7.json"; fi
  if [ -n "$existing" ] && [ -n "$path" ]; then printf '%s' "$existing" > "$td/$path"; fi
  printf '%s' "$payload" \
    | env CLAUDE_PROJECT_DIR="$td" OBSERVABILITY_PHASE_TRACE_GATE_OFF="$kswitch" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

# --- baseline (preserved from before migration) ---
run allow no-state-file docs/issue-7/reports/observability.md 'RED 채택.' ''
run allow state-no-deviation docs/issue-7/reports/observability.md 'RED 채택.' '{"issue":"7","methodology_named":true}'
run allow deviation-with-reason docs/issue-7/reports/observability.md 'USE로 변경. 이유: 표면이 resource-bound로 재분류되었기 때문.' '{"issue":"7","methodology_named":true}'
run deny  deviation-no-reason docs/issue-7/reports/observability.md 'USE로 변경(이탈).' '{"issue":"7","methodology_named":true}'
run allow foreign-path docs/issue-7/reports/pricing.md 'irrelevant' ''

# --- a. Edit tool shape ---
edit_ti_pass='{"file_path":"docs/issue-7/reports/observability.md","old_string":"OLD","new_string":"USE로 변경. 이유: 때문에."}'
run allow edit-shape-pass docs/issue-7/reports/observability.md '' '{"issue":"7","methodology_named":true}' "$edit_ti_pass" Edit 'prefix OLD suffix'
edit_ti_fail='{"file_path":"docs/issue-7/reports/observability.md","old_string":"OLD","new_string":"USE로 변경 단순."}'
run deny  edit-shape-fail docs/issue-7/reports/observability.md '' '{"issue":"7","methodology_named":true}' "$edit_ti_fail" Edit 'prefix OLD suffix'

# --- b. MultiEdit tool shape ---
me_ti_pass='{"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"A","new_string":"A2"},{"old_string":"B","new_string":"USE로 변경. 이유: 때문에."}]}'
run allow multiedit-shape-pass docs/issue-7/reports/observability.md '' '{"issue":"7","methodology_named":true}' "$me_ti_pass" MultiEdit 'A B'
me_ti_fail='{"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"A","new_string":"A2"},{"old_string":"B","new_string":"USE로 변경 단순."}]}'
run deny  multiedit-shape-fail docs/issue-7/reports/observability.md '' '{"issue":"7","methodology_named":true}' "$me_ti_fail" MultiEdit 'A B'

# --- c. replace_all with 2+ occurrences: gate must judge FULLY replaced content ---
# old_string "X" occurs twice; replace_all true -> both become deviation text (with reason nearby each) -> allow
ra_edit_pass='{"file_path":"docs/issue-7/reports/observability.md","old_string":"X","new_string":"USE로 변경. 이유: 때문에.","replace_all":true}'
run allow edit-replace-all-pass docs/issue-7/reports/observability.md '' '{"issue":"7","methodology_named":true}' "$ra_edit_pass" Edit 'X and X'
# replace_all true, replacement lacks reason -> both occurrences deviate without reason -> deny
ra_edit_fail='{"file_path":"docs/issue-7/reports/observability.md","old_string":"X","new_string":"USE로 변경 단순.","replace_all":true}'
run deny  edit-replace-all-fail docs/issue-7/reports/observability.md '' '{"issue":"7","methodology_named":true}' "$ra_edit_fail" Edit 'X and X'
ra_me_pass='{"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"X","new_string":"USE로 변경. 이유: 때문에.","replace_all":true}]}'
run allow multiedit-replace-all-pass docs/issue-7/reports/observability.md '' '{"issue":"7","methodology_named":true}' "$ra_me_pass" MultiEdit 'X and X'

# --- d. Malformed JSON: 3 sub-cases, all deny ---
run_raw deny malformed-truncated docs/issue-7/reports/observability.md '{"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/reports/observability.md","content":"x"' '{"issue":"7","methodology_named":true}'
run_raw deny malformed-non-object docs/issue-7/reports/observability.md '"just a string"' '{"issue":"7","methodology_named":true}'
run_raw deny malformed-empty docs/issue-7/reports/observability.md '' '{"issue":"7","methodology_named":true}'

# --- e. Kill switch: 3 sub-cases ---
run allow kill-switch-on-spelling docs/issue-7/reports/observability.md 'USE로 변경(이탈).' '{"issue":"7","methodology_named":true}' '' Write '' '1'
run deny  kill-switch-off-spelling docs/issue-7/reports/observability.md 'USE로 변경(이탈).' '{"issue":"7","methodology_named":true}' '' Write '' 'off'
run deny  kill-switch-garbage-stays-active docs/issue-7/reports/observability.md 'USE로 변경(이탈).' '{"issue":"7","methodology_named":true}' '' Write '' 'typo-garbage'

# --- f. Absolute path + ./-prefixed relative path variants, same verdict ---
run deny  path-relative-dotslash ./docs/issue-7/reports/observability.md 'USE로 변경(이탈).' '{"issue":"7","methodology_named":true}'

abs_deny_test() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/docs/issue-7/reports"
  mkdir -p "$td/.observability-phase1-methods"; printf '%s' '{"issue":"7","methodology_named":true}' > "$td/.observability-phase1-methods/7.json"
  abspath="$td/docs/issue-7/reports/observability.md"
  ti="$(python3 -c 'import json,sys; print(json.dumps({"file_path": sys.argv[1], "content": sys.argv[2]}))' "$abspath" 'USE로 변경(이탈).')"
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name": "Write", "tool_input": json.loads(sys.argv[1]), "cwd": sys.argv[2]}))' "$ti" "$td")"
  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$td" OBSERVABILITY_PHASE_TRACE_GATE_OFF='' /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" path-absolute
}
abs_deny_test

# --- adjacency-fix proof ---
far_content='USE로 변경.

Some unrelated paragraph text describing methodology context that goes on for a while.

Another unrelated paragraph, still no explanation given here at all.

이유 때문 because reason appear only way down here, in a totally separate paragraph from the deviation marker above.'
run deny  adjacency-far-fails docs/issue-7/reports/observability.md "$far_content" '{"issue":"7","methodology_named":true}'

near_content='Intro paragraph, unrelated.

USE로 변경. 이유: 표면이 resource-bound로 재분류되었기 때문.

Trailing unrelated paragraph.'
run allow adjacency-near-passes docs/issue-7/reports/observability.md "$near_content" '{"issue":"7","methodology_named":true}'

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
