#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/../observability-explorability/hooks/explorability-gate.sh"
export CLAUDE_PLUGIN_ROOT_CORE="${CLAUDE_PLUGIN_ROOT_CORE:-/home/jwjung/.claude/plugins/marketplaces/tokenmaxxxer/runs/rulebooks/tokenmaxxxer-core/core}"
pass=0; fail=0
report() { if [ "$2" = "$1" ]; then pass=$((pass+1)); printf 'ok     %-34s %s\n' "$3" "$2"; else fail=$((fail+1)); printf 'FAIL   %-34s want=%s got=%s\n' "$3" "$1" "$2"; fi; }

# send <name> <want> <json-payload> [extra-env...] — POSTs a raw JSON
# tool-use payload to the gate in a fresh throwaway git repo, reports the
# verdict.
send() {
  name="$1"; want="$2"; json="$3"; shift 3
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"
  printf '%s' "$json" | env "$@" CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

# run want name path content [tool-shape] [extra-env...]
#   tool-shape: "write" (default), "edit", "multiedit", "edit-replaceall",
#   "multiedit-replaceall"
run() {
  want="$1"; name="$2"; path="$3"; content="$4"; shape="${5:-write}"; shift 5 2>/dev/null || shift $#
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$path")"
  case "$shape" in
    write)
      json="$(python3 -c 'import json,sys; p,c=sys.argv[1],sys.argv[2]; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":p,"content":c}}))' "$path" "$content")"
      ;;
    edit-pass)
      old=""; printf '%s' "$content" > "$td/$path.new"
      json="$(python3 -c '
import json,sys
path,new=sys.argv[1],sys.argv[2]
existing=""
print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":path,"old_string":existing,"new_string":new}}))
' "$path" "$content")"
      ;;
    *) json="" ;;
  esac
  printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$want" "$got" "$name"
}

# ---- existing baseline fixtures (Write tool) ----
run allow phase1-mentions-explorability docs/issue-7/proposals/x-observability.md '탐색가능성 확보: 사전 미정의 질문에도 답할 수 있다.'
run deny  phase1-missing docs/issue-7/proposals/x-observability.md '방법론만 언급.'
run allow phase2-with-example docs/issue-7/reports/observability.md '애드혹 쿼리 예시: SELECT count(*) FROM spans WHERE status=500 GROUP BY route;'
run deny  phase2-no-example docs/issue-7/reports/observability.md '애드혹 쿼리 지원한다.'
run deny  phase2-missing docs/issue-7/reports/observability.md '방법론만 언급.'
run allow foreign-path docs/issue-7/reports/pricing.md 'irrelevant'

# ---- adjacency (same-paragraph) semantics ----
run allow phase2-adjacent-same-paragraph docs/issue-7/reports/observability.md \
'애드혹 쿼리 예시입니다.
쿼리: SELECT * FROM spans WHERE status=500;

다른 문단입니다.'
run deny  phase2-marker-far-away-different-paragraph docs/issue-7/reports/observability.md \
'애드혹 쿼리를 지원합니다.

전혀 다른 섹션 설명입니다.

SELECT * FROM unrelated_table;'

# ==== helper for building generic tool_input payloads ====
mkrepo() { td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$1")"; printf '%s' "$td"; }

# (a) Edit tool shape — passing + failing
td="$(mkrepo docs/issue-7/reports/observability.md)"
printf '%s' 'placeholder
설명: 애드혹 예시 준비중' > "$td/docs/issue-7/reports/observability.md"
json='{"tool_name":"Edit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","old_string":"설명: 애드혹 예시 준비중","new_string":"애드혹 쿼리: SELECT * FROM spans WHERE status=500;"}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" edit-shape-pass

td="$(mkrepo docs/issue-7/reports/observability.md)"
printf '%s' 'placeholder
설명: 아직 없음' > "$td/docs/issue-7/reports/observability.md"
json='{"tool_name":"Edit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","old_string":"설명: 아직 없음","new_string":"설명: 여전히 없음"}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" edit-shape-fail

# (b) MultiEdit tool shape — passing + failing
td="$(mkrepo docs/issue-7/reports/observability.md)"
printf '%s' 'placeholder A
placeholder B' > "$td/docs/issue-7/reports/observability.md"
json='{"tool_name":"MultiEdit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"placeholder A","new_string":"애드혹 쿼리 예시"},{"old_string":"placeholder B","new_string":"쿼리: SELECT * FROM spans WHERE status=500;"}]}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" multiedit-shape-pass

td="$(mkrepo docs/issue-7/reports/observability.md)"
printf '%s' 'placeholder A
placeholder B' > "$td/docs/issue-7/reports/observability.md"
json='{"tool_name":"MultiEdit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"placeholder A","new_string":"애드혹 쿼리 지원"},{"old_string":"placeholder B","new_string":"본문 계속"}]}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" multiedit-shape-fail

# (c) replace_all: true on Edit/MultiEdit whose old_string occurs 2+ times
#     — assert gate judges FULLY replaced content.
td="$(mkrepo docs/issue-7/reports/observability.md)"
printf '%s' 'X marker
X marker' > "$td/docs/issue-7/reports/observability.md"
json='{"tool_name":"Edit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","old_string":"X marker","new_string":"애드혹 쿼리: SELECT * FROM spans WHERE 1=1;","replace_all":true}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" edit-replaceall-both-replaced

td="$(mkrepo docs/issue-7/reports/observability.md)"
printf '%s' 'Y marker
Y marker' > "$td/docs/issue-7/reports/observability.md"
json='{"tool_name":"MultiEdit","tool_input":{"file_path":"docs/issue-7/reports/observability.md","edits":[{"old_string":"Y marker","new_string":"애드혹 쿼리: SELECT * FROM spans WHERE 1=1;","replace_all":true}]}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" multiedit-replaceall-both-replaced

# (d) Malformed JSON — 3 sub-cases — all deny
send truncated-json deny '{"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/reports/observability.md","content":'
send non-object-json deny '"just a string"'
send empty-stdin deny ''

# (e) Kill switch — 3 sub-cases
# on-spelling: gate exits 0 without evaluating, even on a failing case
td="$(mkrepo docs/issue-7/reports/observability.md)"
json='{"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/reports/observability.md","content":"방법론만 언급."}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" OBSERVABILITY_EXPLORABILITY_GATE_OFF=true /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" kill-switch-on-spelling

# off-spelling: normal enforcement (failing case still denies)
td="$(mkrepo docs/issue-7/reports/observability.md)"
json='{"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/reports/observability.md","content":"방법론만 언급."}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" OBSERVABILITY_EXPLORABILITY_GATE_OFF=off /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" kill-switch-off-spelling

# garbage/typo: STAYS ACTIVE, still denies failing case
td="$(mkrepo docs/issue-7/reports/observability.md)"
json='{"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/reports/observability.md","content":"방법론만 언급."}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" OBSERVABILITY_EXPLORABILITY_GATE_OFF=tru3 /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" kill-switch-garbage-typo-stays-active

# (f) Absolute path + ./-prefixed relative path variants of an
#     already-covered fixture, same verdict.
td="$(mkrepo docs/issue-7/reports/observability.md)"
json="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":"애드혹 쿼리 예시: SELECT count(*) FROM spans WHERE status=500 GROUP BY route;"}}))' "$td/docs/issue-7/reports/observability.md")"
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" absolute-path-variant

td="$(mkrepo docs/issue-7/reports/observability.md)"
json='{"tool_name":"Write","tool_input":{"file_path":"./docs/issue-7/reports/observability.md","content":"애드혹 쿼리 예시: SELECT count(*) FROM spans WHERE status=500 GROUP BY route;"}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" dot-relative-path-variant

# (g) missing core lib — CLAUDE_PLUGIN_ROOT_CORE points at a nonexistent
#     path; gate must fail closed (deny/exit-2).
td="$(mkrepo docs/issue-7/reports/observability.md)"
json='{"tool_name":"Write","tool_input":{"file_path":"docs/issue-7/reports/observability.md","content":"애드혹 쿼리 예시: SELECT * FROM spans;"}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" CLAUDE_PLUGIN_ROOT_CORE="/nonexistent/no-such-core" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" missing-core-lib-fails-closed

# (h) Bash-write coverage — a Bash command targeting the guarded
#     proposal/record path must deny (produces-shape check cannot inspect
#     Bash-authored content); an unrelated Bash command must allow.
td="$(mkrepo docs/issue-7/reports/observability.md)"
json='{"tool_name":"Bash","tool_input":{"command":"echo hi >> docs/issue-7/reports/observability.md"}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" bash-write-record-path-denied

td="$(mkrepo docs/issue-7/proposals/x-observability.md)"
json='{"tool_name":"Bash","tool_input":{"command":"cat docs/issue-7/proposals/x-observability.md > /tmp/whatever"}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report deny "$got" bash-write-proposal-path-denied

td="$(mkrepo docs/issue-7/reports/observability.md)"
json='{"tool_name":"Bash","tool_input":{"command":"ls -la docs/issue-7/reports/"}}'
printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
rm -rf "$td"; report allow "$got" bash-unrelated-command-allowed

printf '\n== %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
