#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/../observability-signal-golden/hooks/signal-golden-gate.sh"
export CLAUDE_PLUGIN_ROOT_CORE="${CLAUDE_PLUGIN_ROOT_CORE:-/home/jwjung/.claude/plugins/marketplaces/tokenmaxxxer/runs/rulebooks/tokenmaxxxer-core/core}"
pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

# run want name path content [tool] [env_k=v ...]
# tool: write (default) | edit | multiedit | replace_all
run() {
  want="$1"; name="$2"; path="$3"; content="$4"; tool="${5:-write}"
  shift 5 2>/dev/null || shift $#
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$path")"

  case "$tool" in
    write)
      payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]},"cwd":sys.argv[3]}))' "$path" "$content" "$td")"
      ;;
    edit)
      old="$1"; new="$2"
      printf '%s' "$content" > "$td/$path"
      payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3]},"cwd":sys.argv[4]}))' "$path" "$old" "$new" "$td")"
      ;;
    multiedit)
      # remaining args: old1 new1 [old2 new2 ...]
      printf '%s' "$content" > "$td/$path"
      edits_json="$(python3 -c '
import json,sys
args = sys.argv[1:]
edits = [{"old_string": args[i], "new_string": args[i+1]} for i in range(0, len(args), 2)]
print(json.dumps(edits))
' "$@")"
      payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"MultiEdit","tool_input":{"file_path":sys.argv[1],"edits":json.loads(sys.argv[2])},"cwd":sys.argv[3]}))' "$path" "$edits_json" "$td")"
      ;;
    edit-replace-all)
      old="$1"; new="$2"
      printf '%s' "$content" > "$td/$path"
      payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3],"replace_all":True},"cwd":sys.argv[4]}))' "$path" "$old" "$new" "$td")"
      ;;
    multiedit-replace-all)
      old="$1"; new="$2"
      printf '%s' "$content" > "$td/$path"
      edits_json="$(python3 -c 'import json,sys; print(json.dumps([{"old_string":sys.argv[1],"new_string":sys.argv[2],"replace_all":True}]))' "$old" "$new")"
      payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"MultiEdit","tool_input":{"file_path":sys.argv[1],"edits":json.loads(sys.argv[2])},"cwd":sys.argv[3]}))' "$path" "$edits_json" "$td")"
      ;;
    raw)
      payload="$content"
      ;;
    *)
      echo "unknown tool shape: $tool" >&2; exit 1
      ;;
  esac

  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$td" ${EXTRA_ENV:-} /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

# run-env want name path content tool env_var env_val -- tool_args...
run_env() {
  want="$1"; name="$2"; path="$3"; content="$4"; tool="$5"; ev_k="$6"; ev_v="$7"; shift 7
  local had_prev=0 prev_val=""
  if [ "${!ev_k+set}" = "set" ]; then had_prev=1; prev_val="${!ev_k}"; fi
  export "$ev_k"="$ev_v"
  run "$want" "$name" "$path" "$content" "$tool" "$@"
  if [ "$had_prev" -eq 1 ]; then export "$ev_k"="$prev_val"; else unset "$ev_k"; fi
}

RECORD="docs/issue-7/reports/observability.md"
ALL_FOUR='Golden Signals 채택. latency: p99. traffic: rps. errors: 5xx rate. saturation: cpu.'
MISSING_SAT='Golden Signals 채택. latency: p99. traffic: rps. errors: 5xx rate.'

# --- original baseline cases ---
run allow all-four-golden-signals "$RECORD" "$ALL_FOUR"
run deny  missing-saturation "$RECORD" "$MISSING_SAT"
run allow not-golden-methodology "$RECORD" 'RED 채택. rate: req counter.'
run allow foreign-path docs/issue-7/proposals/x-pricing.md 'irrelevant'

# --- (a) Edit tool shape ---
run allow edit-passing "$RECORD" 'Intro text.
## Golden Signals
placeholder' edit 'placeholder' "$ALL_FOUR"
run deny  edit-failing "$RECORD" 'Intro text.
## Golden Signals
placeholder' edit 'placeholder' "$MISSING_SAT"

# --- (b) MultiEdit tool shape ---
run allow multiedit-passing "$RECORD" 'Intro text.
## Golden Signals
p1
p2' multiedit 'p1' 'Golden Signals 채택. latency: p99. traffic: rps.' 'p2' 'errors: 5xx rate. saturation: cpu.'
run deny  multiedit-failing "$RECORD" 'Intro text.
## Golden Signals
p1
p2' multiedit 'p1' 'Golden Signals 채택. latency: p99. traffic: rps.' 'p2' 'errors: 5xx rate.'

# --- (c) replace_all with old_string occurring 2+ times ---
run allow edit-replace-all-full "$RECORD" 'Golden Signals 채택.
X
more text
X
end' edit-replace-all 'X' "$ALL_FOUR"
run allow multiedit-replace-all-full "$RECORD" 'Golden Signals 채택.
X
more text
X
end' multiedit-replace-all 'X' "$ALL_FOUR"

# --- (d) malformed JSON: 3 sub-cases, all deny ---
run deny malformed-json-truncated "$RECORD" '{"tool_name":"Write","tool_input":{' raw
run deny malformed-json-non-object "$RECORD" '["not","an","object"]' raw
run deny malformed-json-empty-stdin "$RECORD" '' raw

# --- (e) kill switch: on / off / garbage ---
run_env allow kill-switch-on "$RECORD" "$MISSING_SAT" write OBSERVABILITY_SIGNAL_GOLDEN_GATE_OFF 1
run_env deny  kill-switch-off "$RECORD" "$MISSING_SAT" write OBSERVABILITY_SIGNAL_GOLDEN_GATE_OFF off
run_env deny  kill-switch-garbage "$RECORD" "$MISSING_SAT" write OBSERVABILITY_SIGNAL_GOLDEN_GATE_OFF wat

# --- (f) absolute path + ./-prefixed relative path variants ---
# Need td-relative absolute path; construct inline since run() creates td internally.
run_abs_variant() {
  want="$1"; name="$2"; path="$3"; content="$4"
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$path")"
  abspath="$td/$path"
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]},"cwd":sys.argv[3]}))' "$abspath" "$content" "$td")"
  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name-absolute"

  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$path")"
  relpath="./$path"
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]},"cwd":sys.argv[3]}))' "$relpath" "$content" "$td")"
  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name-dot-relative"
}
run_abs_variant allow path-variant-allow "$RECORD" "$ALL_FOUR"
run_abs_variant deny  path-variant-deny "$RECORD" "$MISSING_SAT"

# --- (g) missing CLAUDE_PLUGIN_ROOT_CORE: gate-lib.sh cannot be sourced ---
run_env deny missing-core "$RECORD" "$ALL_FOUR" write CLAUDE_PLUGIN_ROOT_CORE /nonexistent/core-path

# --- (h) Bash-write coverage: a Bash write targeting the record must deny,
# an unrelated Bash command must allow ---
run() {
  want="$1"; name="$2"; path="$3"; content="$4"; tool="${5:-write}"
  shift 5 2>/dev/null || shift $#
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$path")"

  case "$tool" in
    write)
      payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]},"cwd":sys.argv[3]}))' "$path" "$content" "$td")"
      ;;
    edit)
      old="$1"; new="$2"
      printf '%s' "$content" > "$td/$path"
      payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3]},"cwd":sys.argv[4]}))' "$path" "$old" "$new" "$td")"
      ;;
    multiedit)
      # remaining args: old1 new1 [old2 new2 ...]
      printf '%s' "$content" > "$td/$path"
      edits_json="$(python3 -c '
import json,sys
args = sys.argv[1:]
edits = [{"old_string": args[i], "new_string": args[i+1]} for i in range(0, len(args), 2)]
print(json.dumps(edits))
' "$@")"
      payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"MultiEdit","tool_input":{"file_path":sys.argv[1],"edits":json.loads(sys.argv[2])},"cwd":sys.argv[3]}))' "$path" "$edits_json" "$td")"
      ;;
    edit-replace-all)
      old="$1"; new="$2"
      printf '%s' "$content" > "$td/$path"
      payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3],"replace_all":True},"cwd":sys.argv[4]}))' "$path" "$old" "$new" "$td")"
      ;;
    multiedit-replace-all)
      old="$1"; new="$2"
      printf '%s' "$content" > "$td/$path"
      edits_json="$(python3 -c 'import json,sys; print(json.dumps([{"old_string":sys.argv[1],"new_string":sys.argv[2],"replace_all":True}]))' "$old" "$new")"
      payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"MultiEdit","tool_input":{"file_path":sys.argv[1],"edits":json.loads(sys.argv[2])},"cwd":sys.argv[3]}))' "$path" "$edits_json" "$td")"
      ;;
    raw)
      payload="$content"
      ;;
    bash)
      payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$content" "$td")"
      ;;
    *)
      echo "unknown tool shape: $tool" >&2; exit 1
      ;;
  esac

  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$td" ${EXTRA_ENV:-} /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

run deny bash-write-to-record "$RECORD" "cat > $RECORD <<'EOF'
$ALL_FOUR
EOF" bash
run allow bash-write-unrelated "$RECORD" "git status" bash

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
