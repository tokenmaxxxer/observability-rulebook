#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/../observability-methodology-selector/hooks/methodology-selector-gate.sh"
STATUS="$HERE/../observability-methodology-selector/hooks/methodology-selector-status.sh"
export CLAUDE_PLUGIN_ROOT_CORE="${CLAUDE_PLUGIN_ROOT_CORE:-/home/jwjung/.claude/plugins/marketplaces/tokenmaxxxer/runs/rulebooks/tokenmaxxxer-core/core}"
pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

PASS_TEXT='RED 방법론 채택, request-driven 표면'
FAIL_TEXT='request-driven 표면 분류만 있음'

# run want name path content [tool_shape] [extra_env...]
# tool_shape: write (default) | edit | edit-replace-all | multiedit | multiedit-replace-all
run() {
  want="$1"; name="$2"; path="$3"; content="$4"; shape="${5:-write}"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$path")"
  case "$shape" in
    write)
      body="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]},"cwd":sys.argv[3]}))' "$path" "$content" "$td")"
      ;;
    edit|edit-replace-all)
      old="SEED_OLD"
      printf 'preamble %s more %s end\n' "$old" "$old" > "$td/$path"
      ra=false; [ "$shape" = "edit-replace-all" ] && ra=true
      body="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":"SEED_OLD","new_string":sys.argv[2],"replace_all":sys.argv[3]=="true"},"cwd":sys.argv[4]}))' "$path" "$content" "$ra" "$td")"
      ;;
    multiedit|multiedit-replace-all)
      printf 'preamble SEED_A more SEED_A and SEED_B end\n' > "$td/$path"
      ra=false; [ "$shape" = "multiedit-replace-all" ] && ra=true
      body="$(python3 -c '
import json,sys
content, ra = sys.argv[1], sys.argv[2] == "true"
edits=[{"old_string":"SEED_A","new_string":content,"replace_all":ra},{"old_string":"SEED_B","new_string":"","replace_all":False}]
print(json.dumps({"tool_name":"MultiEdit","tool_input":{"file_path":sys.argv[3],"edits":edits},"cwd":sys.argv[4]}))
' "$content" "$ra" "$path" "$td")"
      ;;
  esac
  printf '%s' "$body" | /bin/bash -c "cd '$td' && env CLAUDE_PROJECT_DIR='$td' CLAUDE_PLUGIN_ROOT_CORE='$CLAUDE_PLUGIN_ROOT_CORE' /bin/bash '$GATE'" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

run_raw() {
  want="$1"; name="$2"; raw="$3"
  shift 4 2>/dev/null || shift 3
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  printf '%s' "$raw" | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" "$@" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

# --- original coverage ---
run allow both-present docs/issue-7/proposals/x-observability.md "$PASS_TEXT"
run deny  missing-methodology docs/issue-7/proposals/x-observability.md "$FAIL_TEXT"
run deny  missing-surface docs/issue-7/proposals/x-observability.md 'RED 방법론만 언급'
run allow foreign-path docs/issue-7/proposals/x-pricing.md 'irrelevant'

# --- a. Edit tool shape ---
run allow edit-passing docs/issue-7/proposals/x-observability.md "$PASS_TEXT" edit
run deny  edit-failing docs/issue-7/proposals/x-observability.md "$FAIL_TEXT" edit

# --- b. MultiEdit tool shape ---
run allow multiedit-passing docs/issue-7/proposals/x-observability.md "$PASS_TEXT" multiedit
run deny  multiedit-failing docs/issue-7/proposals/x-observability.md "$FAIL_TEXT" multiedit

# --- c. replace_all with 2+ occurrences: content fully replaced (both occurrences of
# SEED_OLD/SEED_A become the new text, so the resulting doc has the passing content
# duplicated -> still allow; and for the failing text, still deny).
run allow edit-replace-all-passing docs/issue-7/proposals/x-observability.md "$PASS_TEXT" edit-replace-all
run deny  edit-replace-all-failing docs/issue-7/proposals/x-observability.md "$FAIL_TEXT" edit-replace-all
run allow multiedit-replace-all-passing docs/issue-7/proposals/x-observability.md "$PASS_TEXT" multiedit-replace-all
run deny  multiedit-replace-all-failing docs/issue-7/proposals/x-observability.md "$FAIL_TEXT" multiedit-replace-all

# --- d. Malformed JSON: 3 sub-cases, all deny ---
run_raw deny malformed-truncated '{"tool_name":"Write","tool_input":{"file_pat'
run_raw deny malformed-non-object '"just a string, not an object"'
run_raw deny malformed-empty-stdin ''

# --- e. Kill switch: on-spelling exits 0 without evaluating (even a failing case
# passes through); off-spelling enforces normally; garbage/typo stays active. ---
fail_body="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/proposals/x-observability.md","content":sys.argv[1]},"cwd":sys.argv[2]}))' "$FAIL_TEXT" "/tmp/nonexistent-cwd-placeholder")"

kill_switch_case() {
  want="$1"; name="$2"; envval="$3"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/docs/issue-7/proposals"
  body="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/proposals/x-observability.md","content":sys.argv[1]},"cwd":sys.argv[2]}))' "$FAIL_TEXT" "$td")"
  printf '%s' "$body" | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="$CLAUDE_PLUGIN_ROOT_CORE" OBSERVABILITY_METHODOLOGY_SELECTOR_GATE_OFF="$envval" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}
kill_switch_case allow kill-switch-on-spelling "true"
kill_switch_case deny  kill-switch-off-spelling "false"
kill_switch_case deny  kill-switch-garbage-typo "totally-bogus-value"

# --- f. Absolute path + ./-prefixed relative path variants, same verdict ---
abspath_case() {
  want="$1"; name="$2"; variant="$3"
  td="$(cd "$(mktemp -d)" && pwd -P)"; mkdir -p "$td/docs/issue-7/proposals"; git init -q "$td"
  case "$variant" in
    absolute) p="$td/docs/issue-7/proposals/x-observability.md" ;;
    dot-relative) p="./docs/issue-7/proposals/x-observability.md" ;;
  esac
  body="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]},"cwd":sys.argv[3]}))' "$p" "$PASS_TEXT" "$td")"
  printf '%s' "$body" | /bin/bash -c "cd '$td' && env CLAUDE_PROJECT_DIR='$td' CLAUDE_PLUGIN_ROOT_CORE='$CLAUDE_PLUGIN_ROOT_CORE' /bin/bash '$GATE'" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}
abspath_case allow abspath-variant absolute
abspath_case allow dot-relative-variant dot-relative

# --- g. missing-core: guarded source must deny, not silently allow ---
missing_core_case() {
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/docs/issue-7/proposals"
  body="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]},"cwd":sys.argv[3]}))' \
    "docs/issue-7/proposals/x-observability.md" "$FAIL_TEXT" "$td")"
  printf '%s' "$body" | /bin/bash -c "cd '$td' && env CLAUDE_PROJECT_DIR='$td' CLAUDE_PLUGIN_ROOT_CORE='/nonexistent-core-path-xyz' /bin/bash '$GATE'" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report deny "$got" missing-core-denies
}
missing_core_case

# --- h. Bash-write coverage: a Bash command targeting the proposal path must deny;
# an unrelated Bash command must allow. ---
bash_write_case() {
  want="$1"; name="$2"; cmd="$3"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$td/docs/issue-7/proposals"
  body="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$cmd" "$td")"
  printf '%s' "$body" | /bin/bash -c "cd '$td' && env CLAUDE_PROJECT_DIR='$td' CLAUDE_PLUGIN_ROOT_CORE='$CLAUDE_PLUGIN_ROOT_CORE' /bin/bash '$GATE'" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}
bash_write_case deny bash-write-denies "cat > docs/issue-7/proposals/x-observability.md"
bash_write_case allow bash-unrelated-allows "ls -la"

# --- i. PostToolUse status script: independently re-derives the pass/fail
# judgment after the write, and records/skips state accordingly. Never
# denies (always exit 0). ---
status_case() {
  name="$1"; path="$2"; content="$3"; response_json="$4"; expect_state="$5"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$path")"
  printf '%s' "$content" > "$td/$path"
  body="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]},"tool_response":json.loads(sys.argv[3]),"cwd":sys.argv[4]}))' \
    "$path" "$content" "$response_json" "$td")"
  printf '%s' "$body" | /bin/bash -c "cd '$td' && env CLAUDE_PROJECT_DIR='$td' CLAUDE_PLUGIN_ROOT_CORE='$CLAUDE_PLUGIN_ROOT_CORE' /bin/bash '$STATUS'" >/dev/null 2>&1
  rc=$?
  state_file="$td/.observability-phase1-methods/7.json"
  ok=true
  [ "$rc" -eq 0 ] || ok=false
  if [ "$expect_state" = "present" ]; then
    [ -f "$state_file" ] || ok=false
  else
    [ ! -f "$state_file" ] || ok=false
  fi
  rm -rf "$td"
  if $ok; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$name" "rc=$rc state=$expect_state"
  else fail=$((fail+1)); printf 'FAIL   %-34s rc=%s state-expect=%s\n' "$name" "$rc" "$expect_state"; fi
}
status_case status-success-records docs/issue-7/proposals/x-observability.md "$PASS_TEXT" '{}' present
status_case status-error-response-skips docs/issue-7/proposals/x-observability.md "$PASS_TEXT" '{"error":"boom"}' absent
status_case status-missing-methodology-skips docs/issue-7/proposals/x-observability.md "$FAIL_TEXT" '{}' absent

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
