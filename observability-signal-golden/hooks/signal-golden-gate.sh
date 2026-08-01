#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh"
gate_trap_fail_closed
set -uo pipefail
gate_kill_switch_active "${OBSERVABILITY_SIGNAL_GOLDEN_GATE_OFF:-}" || { trap - EXIT; exit 0; }

# PreToolUse gate (Write|Edit|MultiEdit|NotebookEdit) — role-owned, single
# methodology (Golden Signals: Latency/Traffic/Errors/Saturation),
# phase-2 only.
#
# On a write whose resolved target is docs/issue-<n>/reports/observability.md,
# parse the PROPOSED content. If the text does not mention Golden Signals
# being adopted for some surface, this gate is a no-op (other methodology
# plugins own that record's other content). If Golden Signals is mentioned
# as adopted, require all four signal classes (latency/traffic/errors/
# saturation) to appear explicitly within the record's Golden Signals
# section (or a bounded window around the first mention, if no matching
# heading exists).
#
# Kill switch: export OBSERVABILITY_SIGNAL_GOLDEN_GATE_OFF=1 (or
# true/yes/on, case-insensitive; any other value, including a typo, keeps
# the gate active).

role="${CLAUDE_ROLE:-observability}"
deny() { gate_deny "$role" "$1"; }

command -v python3 >/dev/null 2>&1 || deny "signal-golden-gate.sh requires python3, which is not on PATH; denying rather than guessing."

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || deny "signal-golden-gate: empty tool-use payload on stdin; cannot evaluate the produces gate."

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
[ -z "$root" ] && deny "no project root could be determined; failing closed (produces-shape check cannot run)."

SG_PAYLOAD="$payload" SG_ROOT="$root" SG_ROLE="$role" GLPY="$GATE_LIB_PY" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["SG_ROLE"]

    import importlib.util
    _spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GLPY"])
    gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    def allow():
        sys.exit(0)

    raw = os.environ.get("SG_PAYLOAD", "")
    ev = gate_lib.gate_parse_json_or_deny(raw, deny)

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["SG_ROOT"].replace("\\", "/"))
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
            deny("%s exists but cannot be read; failing closed on the Golden Signals produces check." % rel)

    new_text, ok = gate_lib.gate_reconstruct_write(tool, ti, current)
    if not ok:
        deny(
            "this write targets %s but the gate cannot determine the resulting content "
            "from the tool input (tool=%r, replace_all honored). Write the full file with "
            "Write, or use an Edit/MultiEdit whose old_string matches, so the Golden "
            "Signals produces shape can be checked." % (rel, tool)
        )

    def has_any_in(text, *needles):
        t = text.lower()
        return any(nd in t for nd in needles)

    # Only applies if Golden Signals is mentioned as the adopted methodology
    # for some surface. Other methodologies (RED/USE) are out of scope for
    # this plugin — no-op rather than false-positive deny. This trigger
    # check stays whole-document: cheap, low false-positive risk, and it is
    # detecting the methodology name itself, not judging its content.
    if not has_any_in(new_text, "golden signal", "golden signals"):
        sys.exit(0)

    # Locate the section whose heading matches this gate's topic, and run
    # the four signal-presence checks against that section's body only.
    HEADING_RE = re.compile(r'^#{1,6}\s+(.*)$', re.MULTILINE)
    heads = list(HEADING_RE.finditer(new_text))
    section_body = None
    for i, m in enumerate(heads):
        heading_text = m.group(1)
        if "golden signal" in heading_text.lower():
            start = m.end()
            end = heads[i + 1].start() if i + 1 < len(heads) else len(new_text)
            section_body = new_text[start:end]
            break

    if section_body is None:
        # Fallback: no matching heading — use a bounded 3-line window
        # around the first topic mention.
        lines = new_text.splitlines()
        low_lines = [ln.lower() for ln in lines]
        idx = None
        for i, ln in enumerate(low_lines):
            if "golden signal" in ln:
                idx = i
                break
        if idx is None:
            section_body = new_text
        else:
            lo = max(0, idx - 1)
            hi = min(len(lines), idx + 2)
            section_body = "\n".join(lines[lo:hi])

    missing = []
    if not has_any_in(section_body, "latency", "지연"):
        missing.append("latency (지연 계측 지점 명시 필요)")
    if not has_any_in(section_body, "traffic", "트래픽", "throughput"):
        missing.append("traffic (트래픽/throughput 계측 지점 명시 필요)")
    if not has_any_in(section_body, "error", "에러", "오류"):
        missing.append("errors (에러/오류 계측 지점 명시 필요)")
    if not has_any_in(section_body, "saturation", "포화"):
        missing.append("saturation (포화 계측 지점 명시 필요)")

    if missing:
        deny(
            "record adopts Golden Signals but is missing required signal(s): %s. "
            "Per the observability-signal-golden methodology plugin, a phase-2 record "
            "that adopts Golden Signals must name all four signals — Latency/Traffic/"
            "Errors/Saturation — each with a concrete instrumentation point." % "; ".join(missing)
        )

    sys.exit(0)
except Exception as _fc_e:  # fail-closed-on-internal-error
    _fc_sys.stderr.write("signal-golden-gate.sh: fail-closed: internal error: %r\n" % (_fc_e,))
    _fc_sys.exit(2)
PY
_fc_rc=$?  # fail-closed-on-internal-error
if [ "$_fc_rc" -ne 0 ] && [ "$_fc_rc" -ne 2 ]; then
  echo "${role}: refused — fail-closed: internal error (judge exited $_fc_rc)" >&2
  exit 2
fi
exit "$_fc_rc"
