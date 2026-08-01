#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/../observability-signal-red/hooks/signal-red-gate.sh"
export CLAUDE_PLUGIN_ROOT_CORE="${CLAUDE_PLUGIN_ROOT_CORE:-/home/jwjung/.claude/plugins/marketplaces/tokenmaxxxer/runs/rulebooks/tokenmaxxxer-core/core}"
pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

# run want name path content [tool_input_json] [extra_env...]
# tool_input_json, if given, overrides the default Write shape; caller
# passes a full JSON object literal for "tool_input" (e.g. Edit/MultiEdit
# shapes). extra_env, if given, is a space-separated VAR=val list applied
# on top of CLAUDE_PROJECT_DIR for the invocation (e.g. kill-switch cases).
run() {
  want="$1"; name="$2"; path="$3"; content="${4-}"; ti_override="${5-}"; extra_env="${6-}"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$path")"
  if [ -n "$content" ] && [ -f "$td/$path" ]; then :; fi
  if [ -n "$ti_override" ]; then
    ti="$ti_override"
  else
    ti="$(python3 -c 'import json,sys; print(json.dumps({"file_path": sys.argv[1], "content": sys.argv[2]}))' "$path" "$content")"
  fi
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": json.loads(sys.argv[2]), "cwd": sys.argv[3]}))' \
    "${TOOL_NAME:-Write}" "$ti" "$td")"
  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$td" $extra_env /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

# run_raw want name raw_payload [extra_env...]  — for malformed-JSON cases
run_raw() {
  want="$1"; name="$2"; raw="$3"; extra_env="${4-}"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  printf '%s' "$raw" | env CLAUDE_PROJECT_DIR="$td" $extra_env /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

# run_preseed want name path pre_content tool_input_json [extra_env]  — for
# Edit/MultiEdit cases against an already-existing file
run_preseed() {
  want="$1"; name="$2"; path="$3"; pre="$4"; ti="$5"; extra_env="${6-}"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$path")"
  printf '%s' "$pre" > "$td/$path"
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": json.loads(sys.argv[2]), "cwd": sys.argv[3]}))' \
    "$TOOL_NAME" "$ti" "$td")"
  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$td" $extra_env /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

RED_PASS='## RED

RED 채택. rate 계측: req counter. error 분류: 5xx. duration: p99 histogram.'
RED_FAIL='## RED

RED 채택. rate 계측: req counter. error 분류: 5xx.'

# --- baseline (pre-existing shape, still via Write) ---
run allow all-three-red-signals docs/issue-7/reports/observability.md "$RED_PASS"
run deny  missing-duration docs/issue-7/reports/observability.md "$RED_FAIL"
run allow not-red-methodology docs/issue-7/reports/observability.md 'USE 채택. utilization: cpu.'
run allow foreign-path docs/issue-7/proposals/x-pricing.md 'irrelevant'

# --- (a) Edit tool shape ---
TOOL_NAME=Edit run_preseed allow edit-shape-passing docs/issue-7/reports/observability.md \
  '## Intro

placeholder' \
  "$(python3 -c 'import json; print(json.dumps({"file_path":"docs/issue-7/reports/observability.md","old_string":"placeholder","new_string":"## RED\n\nRED 채택. rate 계측: req counter. error 분류: 5xx. duration: p99 histogram."}))')"

TOOL_NAME=Edit run_preseed deny edit-shape-failing docs/issue-7/reports/observability.md \
  '## Intro

placeholder' \
  "$(python3 -c 'import json; print(json.dumps({"file_path":"docs/issue-7/reports/observability.md","old_string":"placeholder","new_string":"## RED\n\nRED 채택. rate 계측: req counter. error 분류: 5xx."}))')"

# --- (b) MultiEdit tool shape ---
TOOL_NAME=MultiEdit run_preseed allow multiedit-shape-passing docs/issue-7/reports/observability.md \
  '## RED

AAA
BBB' \
  "$(python3 -c 'import json; print(json.dumps({"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"AAA","new_string":"RED 채택. rate 계측: req counter."},{"old_string":"BBB","new_string":"error 분류: 5xx. duration: p99 histogram."}]}))')"

TOOL_NAME=MultiEdit run_preseed deny multiedit-shape-failing docs/issue-7/reports/observability.md \
  '## RED

AAA
BBB' \
  "$(python3 -c 'import json; print(json.dumps({"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"AAA","new_string":"RED 채택. rate 계측: req counter."},{"old_string":"BBB","new_string":"error 분류: 5xx."}]}))')"

# --- (c) replace_all with a 2+ occurrence old_string ---
TOOL_NAME=Edit run_preseed allow edit-replace-all-full-replace docs/issue-7/reports/observability.md \
  '## RED

TODO rate. TODO error. TODO duration.' \
  "$(python3 -c 'import json; print(json.dumps({"file_path":"docs/issue-7/reports/observability.md","old_string":"TODO","new_string":"RED 채택.","replace_all":True}))')"
# After replacing every "TODO" -> "RED 채택." the section body becomes:
# "RED 채택. rate. RED 채택. error. RED 채택. duration." — all three needles present.

TOOL_NAME=MultiEdit run_preseed allow multiedit-replace-all-full-replace docs/issue-7/reports/observability.md \
  '## RED

X rate counter. X error class. X duration hist.' \
  "$(python3 -c 'import json; print(json.dumps({"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"X","new_string":"RED 채택.","replace_all":True}]}))')"

# --- (d) Malformed JSON: 3 sub-cases, all deny ---
run_raw deny malformed-json-truncated '{"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/reports/observability.md","content":"RED'
run_raw deny malformed-json-non-object '["not","an","object"]'
run_raw deny malformed-json-empty-stdin ''

# --- (e) Kill switch: on / off / garbage ---
FAILING_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/reports/observability.md","content":"RED 채택. rate 계측: req counter. error 분류: 5xx."}}'

td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
printf '%s' "$FAILING_PAYLOAD" | env CLAUDE_PROJECT_DIR="$td" OBSERVABILITY_SIGNAL_RED_GATE_OFF=1 /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" kill-switch-on-spelling

td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
printf '%s' "$FAILING_PAYLOAD" | env CLAUDE_PROJECT_DIR="$td" OBSERVABILITY_SIGNAL_RED_GATE_OFF=off /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" kill-switch-off-spelling

td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
printf '%s' "$FAILING_PAYLOAD" | env CLAUDE_PROJECT_DIR="$td" OBSERVABILITY_SIGNAL_RED_GATE_OFF=typoxyz /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" kill-switch-garbage-stays-active

# --- (f) Absolute path + ./-prefixed relative path variants ---
run_abs_and_dotrel() {
  want="$1"; base_path="$2"; content="$3"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$base_path")"
  ti="$(python3 -c 'import json,sys; print(json.dumps({"file_path": sys.argv[1], "content": sys.argv[2]}))' "$td/$base_path" "$content")"
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":json.loads(sys.argv[1]),"cwd":sys.argv[2]}))' "$ti" "$td")"
  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  report "$want" "$got" "absolute-path-variant"

  ti="$(python3 -c 'import json,sys; print(json.dumps({"file_path": "./"+sys.argv[1], "content": sys.argv[2]}))' "$base_path" "$content")"
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":json.loads(sys.argv[1]),"cwd":sys.argv[2]}))' "$ti" "$td")"
  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "dot-relative-path-variant"
}
run_abs_and_dotrel allow docs/issue-7/reports/observability.md "$RED_PASS"

# --- (g) missing/invalid CLAUDE_PLUGIN_ROOT_CORE fails closed ---
td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
printf '%s' "$FAILING_PAYLOAD" | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE=/nonexistent/path/core /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" missing-core-fails-closed

# --- (h) Bash write coverage ---
TOOL_NAME=Bash run deny bash-write-to-record docs/issue-7/reports/observability.md '' \
  "$(python3 -c 'import json; print(json.dumps({"command":"echo hi > docs/issue-7/reports/observability.md"}))')"

TOOL_NAME=Bash run allow bash-write-unrelated docs/issue-7/reports/observability.md '' \
  "$(python3 -c 'import json; print(json.dumps({"command":"echo hi > docs/issue-7/other.md"}))')"

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
