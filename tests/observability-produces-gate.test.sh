#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/../observability/hooks/observability-produces-gate.sh"
export CLAUDE_PLUGIN_ROOT_CORE="/home/jwjung/tokenmaxxxer/tokenmaxxxer-core/core"
pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

# Passing content: has all three components.
FULL_CONTENT='## Signal Selection
We use the RED method (rate/errors/duration) for this service.

## Cardinality Budget
카디널리티 후보: user_id는 hash 처리, request_id는 drop.

## Ad-hoc Queries
예시 ad-hoc 쿼리: SELECT ... 탐색 쿼리로 활용.'

MISSING_CONTENT='## Notes
이 문서에는 아무 것도 없습니다.'

DEFAULT_PATH="docs/issue-7/reports/observability.md"

# run want name path content [envline]
run() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$3")"
  pf="$td.payload"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "$3" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$4")" "$td" > "$pf"
  env CLAUDE_PROJECT_DIR="$td" ${5:-} /bin/bash "$GATE" < "$pf" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td" "$pf"; report "$1" "$got" "$2"
}

# run_raw want name payload [envline]
run_raw() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  pf="$td.payload"
  printf '%s' "$3" > "$pf"
  env CLAUDE_PROJECT_DIR="$td" ${4:-} /bin/bash "$GATE" < "$pf" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td" "$pf"; report "$1" "$got" "$2"
}

# run_tool want tool path tool_input_json seed_content envline name
run_tool() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$3")"
  if [ -n "${5:-}" ]; then printf '%s' "$5" > "$td/$3"; fi
  pf="$td.payload"
  printf '{"tool_name":"%s","tool_input":%s,"cwd":"%s"}' "$2" "$4" "$td" > "$pf"
  env CLAUDE_PROJECT_DIR="$td" ${6:-} /bin/bash "$GATE" < "$pf" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td" "$pf"; report "$1" "$got" "$7"
}

jenc() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

# --- baseline whole-doc coverage ---
run allow full-content "$DEFAULT_PATH" "$FULL_CONTENT"
run deny  missing-content "$DEFAULT_PATH" "$MISSING_CONTENT"
run allow foreign-path docs/issue-7/reports/pricing.md 'irrelevant'

# --- a. Edit tool shape ---
SEED="## Notes
placeholder line to edit."
NEW_EDIT_TEXT="## Signal Selection
RED method (rate/errors/duration).

## Cardinality Budget
카디널리티: user_id hash 처리.

## Ad-hoc Queries
ad-hoc 쿼리 예시 포함."
ti="$(python3 -c 'import json,sys; print(json.dumps({"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3]}))' \
  "$DEFAULT_PATH" "placeholder line to edit." "$NEW_EDIT_TEXT")"
run_tool allow Edit "$DEFAULT_PATH" "$ti" "$SEED" "" edit-pass
ti_fail="$(python3 -c 'import json,sys; print(json.dumps({"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3]}))' \
  "$DEFAULT_PATH" "placeholder line to edit." "still nothing relevant.")"
run_tool deny Edit "$DEFAULT_PATH" "$ti_fail" "$SEED" "" edit-fail

# --- b. MultiEdit tool shape ---
SEED2="## Notes
first target.
second target."
edits_pass='[{"old_string":"first target.","new_string":"## Signal Selection\nUSE method applied."},{"old_string":"second target.","new_string":"## Cardinality Budget\n카디널리티: request_id drop.\n\n## Ad-hoc Queries\nad hoc 예시."}]'
ti_me="$(python3 -c 'import json,sys; print(json.dumps({"file_path":sys.argv[1],"edits":json.loads(sys.argv[2])}))' "$DEFAULT_PATH" "$edits_pass")"
run_tool allow MultiEdit "$DEFAULT_PATH" "$ti_me" "$SEED2" "" multiedit-pass
edits_fail='[{"old_string":"first target.","new_string":"still nothing."},{"old_string":"second target.","new_string":"also nothing."}]'
ti_me_fail="$(python3 -c 'import json,sys; print(json.dumps({"file_path":sys.argv[1],"edits":json.loads(sys.argv[2])}))' "$DEFAULT_PATH" "$edits_fail")"
run_tool deny MultiEdit "$DEFAULT_PATH" "$ti_me_fail" "$SEED2" "" multiedit-fail

# --- c. replace_all on repeated old_string ---
SEED3="X X X"
ti_ra="$(python3 -c 'import json,sys; print(json.dumps({"file_path":sys.argv[1],"old_string":"X","new_string":sys.argv[2],"replace_all":True}))' \
  "$DEFAULT_PATH" "## Signal Selection
RED method (rate/errors/duration).
## Cardinality Budget
카디널리티: y hash.
## Ad-hoc Queries
ad-hoc 예시.")"
run_tool allow Edit "$DEFAULT_PATH" "$ti_ra" "$SEED3" "" replace-all-edit

SEED4="Y Y"
edits_ra='[{"old_string":"Y","new_string":"## Signal Selection\nUSE method.\n## Cardinality Budget\n카디널리티: z hash.\n## Ad-hoc Queries\nad hoc query.","replace_all":true}]'
ti_ra_me="$(python3 -c 'import json,sys; print(json.dumps({"file_path":sys.argv[1],"edits":json.loads(sys.argv[2])}))' "$DEFAULT_PATH" "$edits_ra")"
run_tool allow MultiEdit "$DEFAULT_PATH" "$ti_ra_me" "$SEED4" "" replace-all-multiedit

# --- d. Malformed JSON ---
run_raw deny malformed-truncated '{"tool_name":"Write","tool_input":{'
run_raw deny malformed-non-object '["not","an","object"]'
run_raw deny malformed-empty ''

# --- e. Kill switch ---
run allow killswitch-on-recognized "$DEFAULT_PATH" "$MISSING_CONTENT" 'OBSERVABILITY_PRODUCES_GATE_OFF=1'
run deny  killswitch-off-recognized "$DEFAULT_PATH" "$MISSING_CONTENT" 'OBSERVABILITY_PRODUCES_GATE_OFF=off'
run deny  killswitch-garbage-stays-active "$DEFAULT_PATH" "$MISSING_CONTENT" 'OBSERVABILITY_PRODUCES_GATE_OFF=1x'

# --- f. Absolute path / ./-prefixed relative path variants ---
run_abs() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$DEFAULT_PATH")"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "$td/$DEFAULT_PATH" "$(jenc "$FULL_CONTENT")" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report allow "$got" absolute-path-full
}
run_abs

run_dotrel() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$DEFAULT_PATH")"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "./$DEFAULT_PATH" "$(jenc "$FULL_CONTENT")" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report allow "$got" dot-relative-path-full
}
run_dotrel

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
