#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh"
gate_trap_fail_closed
set -uo pipefail
gate_kill_switch_active "${OBSERVABILITY_SIGNAL_RED_GATE_OFF:-}" || { trap - EXIT; exit 0; }
# PreToolUse gate (Write|Edit|MultiEdit) — RED signal methodology, phase-2 only.
#
# On a write whose resolved target is docs/issue-<n>/reports/observability.md,
# parse the PROPOSED content. This gate is a no-op unless the resulting text
# mentions RED as the adopted methodology for some surface — other signal
# plugins (USE/Golden Signals) share this same phase-2 record path, and each
# only asserts requirements about its own methodology when mentioned. When
# RED is mentioned, require all three RED signal classes (rate, errors,
# duration) to appear within the record's own RED-topic section (falling
# back to a bounded window around the first mention if no matching heading
# is found), each naming a concrete instrumentation point.
#
# Kill switch: export OBSERVABILITY_SIGNAL_RED_GATE_OFF=1

role="${CLAUDE_ROLE:-observability}"
deny() { gate_deny "$role" "$1"; }

command -v python3 >/dev/null 2>&1 || deny "signal-red-gate.sh requires python3, which is not on PATH; denying rather than guessing."

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || deny "signal-red-gate: empty tool-use payload on stdin; cannot evaluate the RED produces gate."

_target="$(printf '%s' "$payload" | python3 -c '
import json,sys
try: e=json.loads(sys.stdin.read())
except Exception: sys.exit(0)
ti=e.get("tool_input") if isinstance(e,dict) else None
if isinstance(ti,dict):
    for k in ("file_path","notebook_path"):
        v=ti.get(k)
        if isinstance(v,str) and v: print(v); break
' 2>/dev/null || true)"

_plausible() { [ -n "$1" ] && [ -d "$1" ] && { [ -e "$1/.git" ] || [ -f "$1/docs/specs/role-handoff-contract.md" ]; }; }
_under() {
  [ -z "$2" ] && return 0
  python3 -c '
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GATE_LIB_PY"])
gate_lib = importlib.util.module_from_spec(spec); spec.loader.exec_module(gate_lib)
root = os.path.realpath(sys.argv[1])
sys.exit(0 if gate_lib.gate_normalize_path(root, sys.argv[2]) is not None else 1)
' "$1" "$2"
}

root=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && _plausible "$CLAUDE_PROJECT_DIR" && _under "$CLAUDE_PROJECT_DIR" "$_target"; then
  root="$(cd "$CLAUDE_PROJECT_DIR" 2>/dev/null && pwd -P)"
fi
if [ -z "$root" ]; then
  d="$_target"; [ -n "$d" ] || d="$(pwd -P)"; [ -d "$d" ] || d="$(dirname "$d")"
  root="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
fi
[ -z "$root" ] && root="$(git -C "$(pwd -P)" rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$root" ] && deny "no project root could be determined; failing closed (RED produces-shape check cannot run)."

SR_PAYLOAD="$payload" SR_ROOT="$root" SR_ROLE="$role" GLPY="$GATE_LIB_PY" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["SR_ROLE"]

    import importlib.util
    _spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GLPY"])
    gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    def allow():
        sys.exit(0)

    raw = os.environ.get("SR_PAYLOAD", "")
    ev = gate_lib.gate_parse_json_or_deny(raw, deny)

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["SR_ROOT"].replace("\\", "/"))
    RECORD_RE = re.compile(r'^docs/issue-[0-9]+/reports/observability\.md$')

    # Only Write/Edit/MultiEdit/NotebookEdit reach the record in a form
    # whose full resulting content we can read. Everything else is out of
    # this gate's scope and passed through.
    path = None
    if tool in ("Write", "Edit", "MultiEdit"):
        p = ti.get("file_path")
        if isinstance(p, str) and p: path = p
    elif tool == "NotebookEdit":
        p = ti.get("notebook_path")
        if isinstance(p, str) and p: path = p
    if path is None:
        sys.exit(0)

    rel = gate_lib.gate_normalize_path(root, path)
    if rel is None:
        sys.exit(0)
    if not RECORD_RE.match(rel):
        sys.exit(0)  # not the phase-2 observability record — not this gate's business
    r = posixpath.join(root, rel) if rel else root

    current = None
    if os.path.isfile(r):
        try:
            with open(r, encoding="utf-8-sig") as fh:
                current = fh.read(1 << 20)
        except OSError:
            deny("%s exists but cannot be read; failing closed on the RED produces-shape check." % rel)

    new_text, ok = gate_lib.gate_reconstruct_write(tool, ti, current)
    if not ok:
        deny(
            "this write targets %s but the gate cannot determine the resulting content from the tool input "
            "(tool=%r, replace_all honored). Write the full file with Write, or use an Edit/MultiEdit whose "
            "old_string matches, so the shape can be checked." % (rel, tool)
        )

    def has_any(text, *needles):
        low = text.lower()
        return any(nd in low for nd in needles)

    # No-op unless RED is actually mentioned as the adopted methodology for
    # some surface in this record — the record is shared across signal
    # plugins (RED/USE/Golden), each only owns its own mention. This trigger
    # check stays whole-document: cheap, low false-positive risk (detecting
    # the METHODOLOGY NAME itself, not judging its content).
    if not has_any(new_text, "red", "rate/errors/duration"):
        sys.exit(0)

    # Section-scoped: locate the section whose heading names RED, and run
    # the three signal-presence needle checks against that section's body
    # only, not the whole document. If no heading matches, fall back to a
    # bounded 3-line window around the first topic mention.
    HEADING_RE = re.compile(r'^(#{1,6})[ \t]+(.*)$', re.MULTILINE)
    headings = list(HEADING_RE.finditer(new_text))
    scope = None
    for i, m in enumerate(headings):
        heading_text = m.group(2).strip().lower()
        if "red" in heading_text:
            start = m.end()
            end = headings[i + 1].start() if i + 1 < len(headings) else len(new_text)
            scope = new_text[start:end]
            break

    if scope is None:
        lines = new_text.splitlines()
        low_lines = [ln.lower() for ln in lines]
        first_idx = None
        for idx, ln in enumerate(low_lines):
            if "red" in ln or "rate/errors/duration" in ln:
                first_idx = idx
                break
        if first_idx is None:
            scope = new_text
        else:
            lo = max(0, first_idx - 1)
            hi = min(len(lines), first_idx + 2)
            scope = "\n".join(lines[lo:hi])

    missing = []
    if not has_any(scope, "rate", "요청"):
        missing.append("rate (요청 카운터/계측 지점이 명시되어야 함)")
    if not has_any(scope, "error", "에러", "오류"):
        missing.append("errors (에러 분류 기준이 명시되어야 함)")
    if not has_any(scope, "duration", "지연", "latency"):
        missing.append("duration (히스토그램/퍼센타일 계측 지점이 명시되어야 함)")

    if missing:
        deny(
            "RED가 채택 방법론으로 언급되었으나 phase-2 record에서 RED 3신호 중 일부가 "
            "누락됨: %s. observability-signal-red 플러그인은 RED가 언급된 경우 rate/"
            "errors/duration 3신호 모두에 구체적 계측 지점을 요구한다." % "; ".join(missing)
        )

    sys.exit(0)
except Exception as _fc_e:  # fail-closed-on-internal-error
    _fc_sys.stderr.write("signal-red-gate.sh: fail-closed: internal error: %r\n" % (_fc_e,))
    _fc_sys.exit(2)
PY
_fc_rc=$?  # fail-closed-on-internal-error
if [ "$_fc_rc" -ne 0 ] && [ "$_fc_rc" -ne 2 ]; then
  echo "${role}: refused — fail-closed: internal error (judge exited $_fc_rc)" >&2
  exit 2
fi
exit "$_fc_rc"
