#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/../observability-cardinality-budget/hooks/cardinality-budget-gate.sh"
export CLAUDE_PLUGIN_ROOT_CORE="${CLAUDE_PLUGIN_ROOT_CORE:-/home/jwjung/.claude/plugins/marketplaces/tokenmaxxxer/runs/rulebooks/tokenmaxxxer-core/core}"
pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

# run want name path content [tool_input_json] [env_kv...]
# If tool_input_json is given, it is used verbatim as the "tool_input"
# object (must itself embed file_path/content/old_string/etc); content and
# path args are still used to seed the pre-existing file on disk (path) and
# are otherwise ignored when tool_input_json is set. Extra args after that
# are NAME=VALUE pairs exported into the gate's environment for the run.
_mark() { mkdir -p "$1/docs/specs"; : > "$1/docs/specs/role-handoff-contract.md"; }

run() {
  local want="$1" name="$2" path="$3" content="$4" ti="${5:-}"
  shift; shift; shift; shift
  [ $# -gt 0 ] && shift
  td="$(cd "$(mktemp -d)" && pwd -P)"; _mark "$td"; mkdir -p "$(dirname "$td/$path")"
  local envargs=()
  for kv in "$@"; do envargs+=(env "$kv"); done
  if [ -z "$ti" ]; then
    ti="$(python3 -c 'import json,sys; print(json.dumps({"file_path":sys.argv[1],"content":sys.argv[2]}))' "$path" "$content")"
  fi
  printf '{"tool_name":"%s","tool_input":%s,"cwd":"%s"}' \
    "${TOOL_NAME:-Write}" "$ti" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" "${envargs[@]}" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

# run_raw want name raw_payload [env_kv...] -- feed a literal raw payload
# (for malformed-JSON / empty-stdin cases) directly to the gate.
run_raw() {
  local want="$1" name="$2" raw="$3"; shift; shift; shift
  td="$(cd "$(mktemp -d)" && pwd -P)"; _mark "$td"
  local envargs=()
  for kv in "$@"; do envargs+=(env "$kv"); done
  printf '%s' "$raw" | env CLAUDE_PROJECT_DIR="$td" "${envargs[@]}" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

# --- original coverage ---
run allow phase1-mentions-cardinality docs/issue-7/proposals/x-observability.md '예비 고카디널리티 후보: user_id, request_id.'
run deny  phase1-missing docs/issue-7/proposals/x-observability.md '방법론만 언급, 고유 차원 목록 없음.'
run allow phase2-full docs/issue-7/reports/observability.md '카디널리티: user_id는 hash 처리, request_id는 drop.'
run deny  phase2-placeholder docs/issue-7/reports/observability.md '카디널리티: N/A.'
run deny  phase2-missing-policy docs/issue-7/reports/observability.md '카디널리티 후보: user_id.'
run allow foreign-path docs/issue-7/reports/pricing.md 'irrelevant'

# --- a. Edit tool shape ---
edit_pass_ti='{"file_path":"%PATH%","old_string":"OLD","new_string":"## Cardinality\n- user_id: hash\n- request_id: drop"}'
edit_fail_ti='{"file_path":"%PATH%","old_string":"OLD","new_string":"## Cardinality\n- user_id: no policy here"}'

run_edit() {
  local want="$1" name="$2" path="$3" seed="$4" ti_tmpl="$5"
  td="$(cd "$(mktemp -d)" && pwd -P)"; _mark "$td"; mkdir -p "$(dirname "$td/$path")"
  printf '%s' "$seed" > "$td/$path"
  local ti="${ti_tmpl//%PATH%/$path}"
  printf '{"tool_name":"Edit","tool_input":%s,"cwd":"%s"}' "$ti" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}
run_edit allow edit-shape-pass docs/issue-7/reports/observability.md 'OLD' "$edit_pass_ti"
run_edit deny  edit-shape-fail docs/issue-7/reports/observability.md 'OLD' "$edit_fail_ti"

# --- b. MultiEdit tool shape ---
me_pass_ti='{"file_path":"%PATH%","edits":[{"old_string":"OLD1","new_string":"## Cardinality"},{"old_string":"OLD2","new_string":"- user_id: bucket"}]}'
me_fail_ti='{"file_path":"%PATH%","edits":[{"old_string":"OLD1","new_string":"## Cardinality"},{"old_string":"OLD2","new_string":"- user_id: unmanaged"}]}'
run_edit_multi() {
  local want="$1" name="$2" path="$3" seed="$4" ti_tmpl="$5"
  td="$(cd "$(mktemp -d)" && pwd -P)"; _mark "$td"; mkdir -p "$(dirname "$td/$path")"
  printf '%s' "$seed" > "$td/$path"
  local ti="${ti_tmpl//%PATH%/$path}"
  printf '{"tool_name":"MultiEdit","tool_input":%s,"cwd":"%s"}' "$ti" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}
run_edit_multi allow multiedit-shape-pass docs/issue-7/reports/observability.md 'OLD1
OLD2' "$me_pass_ti"
run_edit_multi deny  multiedit-shape-fail docs/issue-7/reports/observability.md 'OLD1
OLD2' "$me_fail_ti"

# --- c. replace_all with 2+ occurrences ---
ra_edit_ti='{"file_path":"%PATH%","old_string":"TBD","new_string":"drop","replace_all":true}'
run_edit allow replace-all-edit-fully-replaced docs/issue-7/reports/observability.md '카디널리티: TBD TBD TBD' "$ra_edit_ti"

ra_multi_ti='{"file_path":"%PATH%","edits":[{"old_string":"TBD","new_string":"drop","replace_all":true}]}'
run_edit_multi allow replace-all-multiedit-fully-replaced docs/issue-7/reports/observability.md '카디널리티: TBD TBD TBD' "$ra_multi_ti"

# --- d. Malformed JSON ---
run_raw deny malformed-json-truncated '{"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/reports/observability.md","content":"x"'
run_raw deny malformed-json-non-object '["not","an","object"]'
run_raw deny malformed-json-empty-stdin ''

# --- e. Kill switch ---
denying_payload='{"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/reports/observability.md","content":"카디널리티: N/A"}}'
run_raw allow kill-switch-on-spelling "$denying_payload" 'OBSERVABILITY_CARDINALITY_BUDGET_GATE_OFF=1'
run_raw deny  kill-switch-off-spelling "$denying_payload" 'OBSERVABILITY_CARDINALITY_BUDGET_GATE_OFF=0'
run_raw deny  kill-switch-garbage-typo "$denying_payload" 'OBSERVABILITY_CARDINALITY_BUDGET_GATE_OFF=yse'

# --- f. absolute vs ./-prefixed relative path, same verdict ---
run deny path-relative docs/issue-7/reports/observability.md '카디널리티: N/A.'
run_abs() {
  local want="$1" name="$2" relpath="$3" content="$4"
  td="$(cd "$(mktemp -d)" && pwd -P)"; _mark "$td"; mkdir -p "$(dirname "$td/$relpath")"
  ti="$(python3 -c 'import json,sys; print(json.dumps({"file_path":sys.argv[1],"content":sys.argv[2]}))' "$td/$relpath" "$content")"
  printf '{"tool_name":"Write","tool_input":%s,"cwd":"%s"}' "$ti" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}
run_abs deny path-absolute docs/issue-7/reports/observability.md '카디널리티: N/A.'

run_dotrel() {
  local want="$1" name="$2" relpath="$3" content="$4"
  td="$(cd "$(mktemp -d)" && pwd -P)"; _mark "$td"; mkdir -p "$(dirname "$td/$relpath")"
  ti="$(python3 -c 'import json,sys; print(json.dumps({"file_path":sys.argv[1],"content":sys.argv[2]}))' "./$relpath" "$content")"
  printf '{"tool_name":"Write","tool_input":%s,"cwd":"%s"}' "$ti" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}
run_dotrel deny path-dot-relative docs/issue-7/reports/observability.md '카디널리티: N/A.'

# --- g. missing core (CLAUDE_PLUGIN_ROOT_CORE points at nonexistent path) ---
run deny missing-core docs/issue-7/reports/observability.md '카디널리티: user_id는 hash 처리.' '' 'CLAUDE_PLUGIN_ROOT_CORE=/nonexistent/does/not/exist/core'

# --- h. Bash-write coverage ---
run_bash() {
  local want="$1" name="$2" cmd="$3"
  td="$(cd "$(mktemp -d)" && pwd -P)"; _mark "$td"
  ti="$(python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1]}))' "$cmd")"
  printf '{"tool_name":"Bash","tool_input":%s,"cwd":"%s"}' "$ti" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}
run_bash deny  bash-write-record  'echo "카디널리티: user_id는 hash 처리." > docs/issue-7/reports/observability.md'
run_bash deny  bash-write-proposal 'echo "예비 고카디널리티 후보: user_id." > docs/issue-7/proposals/x-observability.md'
run_bash allow bash-write-unrelated 'echo "hello" > docs/issue-7/reports/pricing.md'

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
