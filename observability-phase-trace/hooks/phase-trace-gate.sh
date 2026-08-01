#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "phase-trace-gate.sh: cannot source gate-lib.sh" >&2; exit 2; }
gate_trap_fail_closed
set -uo pipefail
gate_kill_switch_active "${OBSERVABILITY_PHASE_TRACE_GATE_OFF:-}" || { trap - EXIT; exit 0; }

# PreToolUse gate (Write|Edit|MultiEdit|NotebookEdit) — role-owned, observability-phase-trace only.
#
# On a write whose resolved target is docs/issue-<n>/reports/observability.md
# (the phase-2 record), read the state file that `observability-methodology-
# selector` writes on a passing phase-1 proposal write
# (.observability-phase1-methods/<issue-n>.json, shape
# {"issue": "<n>", "methodology_named": true}) and check whether the phase-2
# text traces back to it. This gate is a CONSUMER of that state file, never
# a writer.
#
# - No state file: informational only — never deny, exit 0 (optionally warn).
# - State file present with methodology_named:true: every line containing a
#   deviation marker ("이탈"/"deviat"/"switch"/"변경") must have a reason
#   marker ("because"/"때문"/"이유"/"reason") nearby (same paragraph, i.e.
#   the contiguous run of non-blank lines around it) — otherwise deny
#   (deviation stated without an adjacent reason). No deviation marker
#   present at all -> nothing to check -> allow.
#
# Kill switch: export OBSERVABILITY_PHASE_TRACE_GATE_OFF=1

role="${CLAUDE_ROLE:-observability}"
deny() { gate_deny "$role" "$1"; }

command -v python3 >/dev/null 2>&1 || deny "phase-trace-gate.sh requires python3, which is not on PATH; denying rather than guessing."

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || deny "phase-trace-gate: empty tool-use payload on stdin; cannot evaluate the phase-trace gate."

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
[ -z "$root" ] && deny "no project root could be determined; failing closed (phase-trace check cannot run)."

PT_PAYLOAD="$payload" PT_ROOT="$root" PT_ROLE="$role" GLPY="$GATE_LIB_PY" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["PT_ROLE"]

    import importlib.util
    _spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GLPY"])
    gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    def allow():
        sys.exit(0)

    raw = os.environ.get("PT_PAYLOAD", "")
    ev = gate_lib.gate_parse_json_or_deny(raw, deny)

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["PT_ROOT"].replace("\\", "/"))
    RECORD_RE = re.compile(r'^docs/issue-([0-9]+)/reports/observability\.md$')

    # Only Write/Edit/MultiEdit/NotebookEdit reach the record in a form
    # whose full resulting content we can read. Everything else is out of
    # scope.
    path = None
    is_bash = False
    if tool in ("Write", "Edit", "MultiEdit"):
        p = ti.get("file_path")
        if isinstance(p, str) and p: path = p
    elif tool == "NotebookEdit":
        p = ti.get("notebook_path")
        if isinstance(p, str) and p: path = p
    elif tool == "Bash":
        cmd = ti.get("command")
        if isinstance(cmd, str) and cmd:
            for token in gate_lib.gate_bash_write_targets(cmd):
                cand_rel = gate_lib.gate_normalize_path(root, token)
                if cand_rel and RECORD_RE.match(cand_rel):
                    path = token
                    is_bash = True
                    break
    if path is None:
        sys.exit(0)

    rel = gate_lib.gate_normalize_path(root, path)
    if rel is None:
        sys.exit(0)
    if not RECORD_RE.match(rel):
        sys.exit(0)  # not the phase-2 observability record — not this gate's business
    if is_bash:
        deny(
            "this Bash command appears to write %s; the produces-shape check cannot inspect "
            "a Bash-authored write's resulting content — use Write/Edit/MultiEdit for this "
            "path instead." % rel
        )
    r = posixpath.join(root, rel) if rel else root
    m = RECORD_RE.match(rel)
    issue_n = m.group(1)

    state_path = os.path.join(root, ".observability-phase1-methods", "%s.json" % issue_n)
    if not os.path.isfile(state_path):
        # Informational only — no phase-1 state to trace against. Never deny.
        sys.stderr.write(
            "%s: note — no phase-1 methodology state found at .observability-phase1-methods/%s.json; "
            "phase-trace check skipped (informational only, not a denial).\n" % (role, issue_n)
        )
        sys.exit(0)

    try:
        with open(state_path, encoding="utf-8-sig") as fh:
            state = json.load(fh)
    except (OSError, ValueError):
        deny(
            ".observability-phase1-methods/%s.json exists but could not be parsed "
            "(corrupt or invalid JSON); failing closed on the phase-trace check "
            "rather than silently skipping it." % issue_n
        )

    if not (isinstance(state, dict) and state.get("methodology_named") is True):
        # State exists but doesn't assert a named methodology — nothing to trace.
        sys.exit(0)

    current = None
    if os.path.isfile(r):
        try:
            with open(r, encoding="utf-8-sig") as fh:
                current = fh.read(1 << 20)
        except OSError:
            deny("%s exists but cannot be read; failing closed on the phase-trace check." % rel)

    new_text, ok = gate_lib.gate_reconstruct_write(tool, ti, current)
    if not ok:
        deny(
            "this write targets %s but the gate cannot determine the resulting content from the tool input "
            "(tool=%r, replace_all honored). Write the full file with Write, or use an Edit/MultiEdit whose "
            "old_string matches, so the shape can be checked." % (rel, tool)
        )

    deviation_markers = ("이탈", "deviat", "switch", "변경")
    reason_markers = ("because", "때문", "이유", "reason")

    def has_any(line_low, *needles):
        return any(nd in line_low for nd in needles)

    lines = new_text.split("\n")
    n = len(lines)
    lines_low = [ln.lower() for ln in lines]

    # Paragraph = contiguous run of non-blank lines. Fallback: a fixed
    # 3-line window (line before, line itself, line after) if paragraph
    # boundaries are degenerate against real fixture prose.
    for i, low in enumerate(lines_low):
        if not has_any(low, *deviation_markers):
            continue
        # find paragraph bounds around line i
        start = i
        while start > 0 and lines[start - 1].strip() != "":
            start -= 1
        end = i
        while end < n - 1 and lines[end + 1].strip() != "":
            end += 1
        window_lo = max(0, i - 1)
        window_hi = min(n - 1, i + 1)
        lo = min(start, window_lo)
        hi = max(end, window_hi)
        nearby = "\n".join(lines_low[lo:hi + 1])
        if not has_any(nearby, *reason_markers):
            deny(
                "record at %s claims a deviation from the phase-1 methodology (contains a deviation "
                "marker such as '이탈'/'deviat'/'switch'/'변경') near line %d but states no nearby reason "
                "(no '때문'/'이유'/'because'/'reason' in the same paragraph/window). Per docs/issue-7/"
                "proposals/2026-07-31-produces-methodology-hook-machine.md plugin #7, a stated deviation "
                "from the phase-1-named methodology must carry an explicit, adjacent reason." % (rel, i + 1)
            )

    sys.exit(0)
except Exception as _fc_e:  # fail-closed-on-internal-error
    _fc_sys.stderr.write("phase-trace-gate.sh: fail-closed: internal error: %r\n" % (_fc_e,))
    _fc_sys.exit(2)
PY
_fc_rc=$?  # fail-closed-on-internal-error
if [ "$_fc_rc" -ne 0 ] && [ "$_fc_rc" -ne 2 ]; then
  echo "${role}: refused — fail-closed: internal error (judge exited $_fc_rc)" >&2
  exit 2
fi
exit "$_fc_rc"
