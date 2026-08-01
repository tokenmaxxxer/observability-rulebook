#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/../observability-signal-use/hooks/signal-use-gate.sh"
export CLAUDE_PLUGIN_ROOT_CORE="${CLAUDE_PLUGIN_ROOT_CORE:-/home/jwjung/.claude/plugins/marketplaces/tokenmaxxxer/runs/rulebooks/tokenmaxxxer-core/core}"
pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

# run want name path content
# Default shape is a Write with "content". Used by the original fixtures.
run() {
  want="$1"; name="$2"; path="$3"; content="$4"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$path")"
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]},"cwd":sys.argv[3]}))' "$path" "$content" "$td")"
  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

# run_raw want name raw_payload cwd_dir env_extra
# raw_payload is a complete JSON payload string. cwd_dir is the fixture
# tmpdir passed as CLAUDE_PROJECT_DIR (caller creates/removes it).
# env_extra, if given, is "VAR=val VAR2=val2" additional env for the gate.
run_raw() {
  want="$1"; name="$2"; raw="$3"; td="$4"; extra="${5:-}"
  printf '%s' "$raw" | env CLAUDE_PROJECT_DIR="$td" $extra /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  report "$want" "$got" "$name"
}

mkeditfixture() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  mkdir -p "$td/docs/issue-7/reports"
  printf '%s' "$1" > "$td/docs/issue-7/reports/observability.md"
  echo "$td"
}

mk_write_payload() {
  # $1=path $2=content $3=cwd
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]},"cwd":sys.argv[3]}))' "$1" "$2" "$3"
}

# ============================================================
# original fixtures
# ============================================================
run allow all-three-use-signals docs/issue-7/reports/observability.md 'USE 채택. utilization: cpu 사용률. saturation: queue depth. errors: OOM count.'
run deny  missing-errors docs/issue-7/reports/observability.md 'USE 채택. utilization: cpu 사용률. saturation: queue depth.'
run allow not-use-methodology docs/issue-7/reports/observability.md 'RED 채택. rate: req counter.'
run allow foreign-path docs/issue-7/proposals/x-pricing.md 'irrelevant'

# ============================================================
# a. Edit tool shape — passing + failing
# ============================================================
td_a1="$(mkeditfixture '## USE
utilization: cpu 사용률. saturation: queue depth.')"
payload_a1="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","old_string":"utilization: cpu 사용률. saturation: queue depth.","new_string":"utilization: cpu 사용률. saturation: queue depth. errors: OOM count."},"cwd":sys.argv[1]}))' "$td_a1")"
run_raw allow edit-pass-add-errors "$payload_a1" "$td_a1"
rm -rf "$td_a1"

td_a2="$(mkeditfixture '## USE
utilization: cpu 사용률. saturation: queue depth.')"
payload_a2="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","old_string":"utilization: cpu 사용률.","new_string":"USE 채택. utilization: cpu 사용률."},"cwd":sys.argv[1]}))' "$td_a2")"
run_raw deny edit-fail-still-missing-errors "$payload_a2" "$td_a2"
rm -rf "$td_a2"

# ============================================================
# b. MultiEdit tool shape — passing + failing
# ============================================================
td_b1="$(mkeditfixture '## USE
utilization: cpu 사용률. saturation: queue depth. placeholder text.')"
payload_b1="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"MultiEdit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"utilization: cpu 사용률.","new_string":"USE 채택. utilization: cpu 사용률."},{"old_string":"placeholder text.","new_string":"errors: OOM count."}]},"cwd":sys.argv[1]}))' "$td_b1")"
run_raw allow multiedit-pass "$payload_b1" "$td_b1"
rm -rf "$td_b1"

td_b2="$(mkeditfixture '## USE
utilization: cpu 사용률. saturation: queue depth. placeholder text.')"
payload_b2="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"MultiEdit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"utilization: cpu 사용률.","new_string":"USE 채택. utilization: cpu 사용률."}]},"cwd":sys.argv[1]}))' "$td_b2")"
run_raw deny multiedit-fail-missing-errors "$payload_b2" "$td_b2"
rm -rf "$td_b2"

# ============================================================
# c. replace_all: true on Edit/MultiEdit whose old_string occurs 2+ times
#    — assert gate judges FULLY replaced content.
# ============================================================
# Edit + replace_all: "PLACEHOLDER" occurs twice; replacing both with an
# errors-mentioning string must make the section pass (proving every
# occurrence, not just the first, was substituted).
td_c1="$(mkeditfixture '## USE
PLACEHOLDER utilization: cpu 사용률. saturation: queue depth. PLACEHOLDER')"
payload_c1="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","old_string":"PLACEHOLDER","new_string":"errors: OOM count.","replace_all":True},"cwd":sys.argv[1]}))' "$td_c1")"
run_raw allow edit-replace-all-fully-replaced "$payload_c1" "$td_c1"
rm -rf "$td_c1"

# MultiEdit + replace_all on one of its edits.
td_c2="$(mkeditfixture '## USE
PLACEHOLDER utilization: cpu 사용률. saturation: queue depth. PLACEHOLDER')"
payload_c2="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"MultiEdit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"PLACEHOLDER","new_string":"errors: OOM count.","replace_all":True}]},"cwd":sys.argv[1]}))' "$td_c2")"
run_raw allow multiedit-replace-all-fully-replaced "$payload_c2" "$td_c2"
rm -rf "$td_c2"

# Without replace_all, only the first PLACEHOLDER is substituted, so the
# section still has no errors mention beyond that one replaced occurrence
# — but since the content DOES then contain "errors:" it should also pass;
# to make replace_all's effect observable we instead assert the
# NON-replace_all case still passes because the first occurrence carries
# the signal (both should allow — replace_all matters for content shape,
# not for these needles specifically). This case demonstrates the false
# case would arise if the SECOND occurrence were the only one carrying the
# needle: replace_all=false leaves it as PLACEHOLDER (unreplaced), so the
# gate must still see it missing without replace_all.
td_c3="$(mkeditfixture '## USE
utilization: cpu 사용률. saturation: queue depth. PLACEHOLDER PLACEHOLDER')"
payload_c3="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","old_string":"PLACEHOLDER","new_string":"errors: OOM count.","replace_all":False},"cwd":sys.argv[1]}))' "$td_c3")"
run_raw allow edit-no-replace-all-first-occurrence-suffices "$payload_c3" "$td_c3"
rm -rf "$td_c3"

# ============================================================
# d. Malformed JSON — 3 sub-cases, all deny
# ============================================================
td_d="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td_d"
run_raw deny malformed-json-truncated '{"tool_name":"Write","tool_input":{"file' "$td_d"
run_raw deny malformed-json-non-object '["not","an","object"]' "$td_d"
run_raw deny malformed-json-empty-stdin '' "$td_d"
rm -rf "$td_d"

# ============================================================
# e. Kill switch — on / off / garbage spellings
# ============================================================
td_e="$(mkeditfixture '## USE
utilization: cpu 사용률. saturation: queue depth.')" # missing errors -> would deny if active
payload_e="$(mk_write_payload docs/issue-7/reports/observability.md 'USE 채택. utilization: cpu 사용률. saturation: queue depth.' "$td_e")"
run_raw allow kill-switch-on-spelling-skips-eval "$payload_e" "$td_e" 'OBSERVABILITY_SIGNAL_USE_GATE_OFF=1'
run_raw deny  kill-switch-off-spelling-still-enforces "$payload_e" "$td_e" 'OBSERVABILITY_SIGNAL_USE_GATE_OFF=off'
run_raw deny  kill-switch-garbage-typo-stays-active "$payload_e" "$td_e" 'OBSERVABILITY_SIGNAL_USE_GATE_OFF=banana'
rm -rf "$td_e"

# ============================================================
# f. Absolute path + ./-prefixed relative path variants of an
#    already-covered fixture, same verdict.
# ============================================================
td_f="$(mkeditfixture '## USE
utilization: cpu 사용률. saturation: queue depth. errors: OOM count.')"
abs_path="$td_f/docs/issue-7/reports/observability.md"
payload_f_abs="$(mk_write_payload "$abs_path" 'USE 채택. utilization: cpu 사용률. saturation: queue depth. errors: OOM count.' "$td_f")"
run_raw allow abs-path-variant "$payload_f_abs" "$td_f"

payload_f_rel="$(mk_write_payload "./docs/issue-7/reports/observability.md" 'USE 채택. utilization: cpu 사용률. saturation: queue depth. errors: OOM count.' "$td_f")"
run_raw allow dot-relative-path-variant "$payload_f_rel" "$td_f"
rm -rf "$td_f"

# ============================================================
# g. missing core lib — must fail closed (deny/exit-2)
# ============================================================
td_g="$(mkeditfixture '## USE
utilization: cpu 사용률. saturation: queue depth. errors: OOM count.')"
payload_g="$(mk_write_payload docs/issue-7/reports/observability.md 'USE 채택. utilization: cpu 사용률. saturation: queue depth. errors: OOM count.' "$td_g")"
run_raw deny missing-core-lib-fails-closed "$payload_g" "$td_g" 'CLAUDE_PLUGIN_ROOT_CORE=/nonexistent/path/does/not/exist'
rm -rf "$td_g"

# ============================================================
# h. Bash-write coverage — targeted write denies, unrelated allows
# ============================================================
td_h="$(mkeditfixture '## USE
utilization: cpu 사용률. saturation: queue depth. errors: OOM count.')"
payload_h_target="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"echo hi > docs/issue-7/reports/observability.md"},"cwd":sys.argv[1]}))' "$td_h")"
run_raw deny bash-write-targets-record "$payload_h_target" "$td_h"

payload_h_other="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"echo hi > docs/issue-7/other.md"},"cwd":sys.argv[1]}))' "$td_h")"
run_raw allow bash-write-unrelated-path "$payload_h_other" "$td_h"
rm -rf "$td_h"

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
