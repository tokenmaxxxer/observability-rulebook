#!/usr/bin/env bash
__fc(){ rc=$?; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "fail-closed: gate aborted (rc=$rc)" >&2; exit 2; fi; }
trap __fc EXIT
# PreToolUse gate (Write|Edit|MultiEdit) — role-owned, observability-phase-trace only.
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
# - State file present with methodology_named:true: if the phase-2 text
#   contains a deviation marker ("이탈"/"deviat"/"switch"/"변경") anywhere,
#   it must also contain a reason marker ("because"/"때문"/"이유"/"reason")
#   somewhere in the text — otherwise deny (deviation stated without reason).
#   No deviation marker present at all -> nothing to check -> allow.
#
# Kill switch: export OBSERVABILITY_PHASE_TRACE_GATE_OFF=1
set -uo pipefail

role="${CLAUDE_ROLE:-observability}"
deny() { echo "${role}: refused — $1" >&2; exit 2; }

case "${OBSERVABILITY_PHASE_TRACE_GATE_OFF:-}" in
  ""|0|false|no|off) ;;
  *) exit 0 ;;
esac

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
import os,posixpath,sys
r,t=sys.argv[1],sys.argv[2]
try: rr=posixpath.normpath(os.path.realpath(r).replace("\\","/"))
except Exception: sys.exit(1)
n=t.replace("\\","/"); a=n if posixpath.isabs(n) else posixpath.join(rr,n)
a=posixpath.normpath(a); real=posixpath.normpath(os.path.realpath(a).replace("\\","/"))
sys.exit(0 if (real==rr or real.startswith(rr+"/")) else 1)
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

PT_PAYLOAD="$payload" PT_ROOT="$root" PT_ROLE="$role" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["PT_ROLE"]

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    raw = os.environ.get("PT_PAYLOAD", "")
    try:
        ev = json.loads(raw) if raw else {}
    except ValueError:
        deny("the tool-call payload is not valid JSON; the gate cannot judge phase-trace on an unparseable write.")
    if not isinstance(ev, dict):
        deny("the tool-call payload is not a JSON object; failing closed on phase-trace.")

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["PT_ROOT"].replace("\\", "/"))
    RECORD_RE = re.compile(r'^docs/issue-([0-9]+)/reports/observability\.md$')

    def resolve(p):
        n = p.replace("\\", "/")
        a = n if posixpath.isabs(n) else posixpath.join(root, n)
        a = posixpath.normpath(a)
        try:
            return posixpath.normpath(os.path.realpath(a).replace("\\", "/"))
        except OSError:
            return a

    # Only Write/Edit/MultiEdit reach the record in a form whose full
    # resulting content we can read. Everything else is out of scope.
    path = None
    if tool in ("Write", "Edit", "MultiEdit"):
        p = ti.get("file_path")
        if isinstance(p, str) and p:
            path = p
    if path is None:
        sys.exit(0)

    r = resolve(path)
    if not r.startswith(root + "/"):
        sys.exit(0)
    rel = r[len(root):].lstrip("/")
    m = RECORD_RE.match(rel)
    if not m:
        sys.exit(0)  # not the phase-2 observability record — not this gate's business
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
        # State file exists but is unreadable/invalid — treat as no usable state, informational only.
        sys.stderr.write(
            "%s: note — .observability-phase1-methods/%s.json exists but could not be parsed; "
            "phase-trace check skipped (informational only, not a denial).\n" % (role, issue_n)
        )
        sys.exit(0)

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

    new_text = None
    if tool == "Write":
        c = ti.get("content")
        if isinstance(c, str):
            new_text = c
    elif tool == "Edit":
        o, n = ti.get("old_string"), ti.get("new_string")
        if isinstance(o, str) and isinstance(n, str) and current is not None and o in current:
            new_text = current.replace(o, n, 1)
    elif tool == "MultiEdit":
        edits = ti.get("edits")
        text = current
        if isinstance(edits, list) and text is not None:
            ok = True
            for e in edits:
                if not isinstance(e, dict):
                    ok = False; break
                o, n = e.get("old_string"), e.get("new_string")
                if not isinstance(o, str) or not isinstance(n, str) or o not in text:
                    ok = False; break
                text = text.replace(o, n, 1)
            if ok:
                new_text = text

    if new_text is None:
        deny(
            "this write targets %s but the gate cannot determine the resulting content "
            "from the tool input (tool=%r). Write the full record with Write, or use an "
            "Edit/MultiEdit whose old_string matches, so the phase-trace check can run." % (rel, tool)
        )

    low = new_text.lower()

    def has_any(*needles):
        return any(nd in low for nd in needles)

    deviation_markers = ("이탈", "deviat", "switch", "변경")
    reason_markers = ("because", "때문", "이유", "reason")

    if has_any(*deviation_markers) and not has_any(*reason_markers):
        deny(
            "record at %s claims a deviation from the phase-1 methodology (contains a deviation "
            "marker such as '이탈'/'deviat'/'switch'/'변경') but states no reason (no '때문'/'이유'/"
            "'because'/'reason' anywhere in the text). Per docs/issue-7/proposals/"
            "2026-07-31-produces-methodology-hook-machine.md plugin #7, a stated deviation from the "
            "phase-1-named methodology must carry an explicit reason." % rel
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
