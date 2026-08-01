#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "signal-use-gate.sh: cannot source gate-lib.sh" >&2; exit 2; }
gate_trap_fail_closed
set -uo pipefail
gate_kill_switch_active "${OBSERVABILITY_SIGNAL_USE_GATE_OFF:-}" || { trap - EXIT; exit 0; }

# PreToolUse gate (Write|Edit|MultiEdit|NotebookEdit) — observability-signal-use only.
#
# On a write whose resolved target is docs/issue-<n>/reports/observability.md
# (the phase-2 record), parse the PROPOSED content. If the record does not
# mention USE being adopted as the methodology for some surface, this gate
# is a no-op (another signal plugin, e.g. observability-signal-red or
# observability-signal-golden, may own that record). If USE is mentioned as
# adopted, require all three USE signal classes (utilization/saturation/
# errors) to appear within the record's USE-topic section, each with SOME
# concrete mention.
#
# Kill switch: export OBSERVABILITY_SIGNAL_USE_GATE_OFF=1 (or true/yes/on,
# case-insensitive). Any other value, including unrecognized garbage,
# leaves the gate active (fail closed on kill-switch typos).

role="${CLAUDE_ROLE:-observability-signal-use}"
deny() { gate_deny "$role" "$1"; }

command -v python3 >/dev/null 2>&1 || deny "signal-use-gate.sh requires python3, which is not on PATH; denying rather than guessing."

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || deny "signal-use-gate: empty tool-use payload on stdin; cannot evaluate the gate."

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
[ -z "$root" ] && deny "no project root could be determined; failing closed (signal-use check cannot run)."

SUG_PAYLOAD="$payload" SUG_ROOT="$root" SUG_ROLE="$role" GLPY="$GATE_LIB_PY" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["SUG_ROLE"]

    import importlib.util
    _spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GLPY"])
    gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    def allow():
        sys.exit(0)

    raw = os.environ.get("SUG_PAYLOAD", "")
    ev = gate_lib.gate_parse_json_or_deny(raw, deny)

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["SUG_ROOT"].replace("\\", "/"))
    RECORD_RE = re.compile(r'^docs/issue-[0-9]+/reports/observability\.md$')

    path = None
    is_bash = False
    if tool in ("Write", "Edit", "MultiEdit"):
        p = ti.get("file_path")
        if isinstance(p, str) and p:
            path = p
    elif tool == "NotebookEdit":
        p = ti.get("notebook_path")
        if isinstance(p, str) and p:
            path = p
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

    current = None
    if os.path.isfile(r):
        try:
            with open(r, encoding="utf-8-sig") as fh:
                current = fh.read(1 << 20)
        except OSError:
            deny("%s exists but cannot be read; failing closed on the signal-use check." % rel)

    new_text, ok = gate_lib.gate_reconstruct_write(tool, ti, current)
    if not ok:
        deny(
            "this write targets %s but the gate cannot determine the resulting content from the tool input "
            "(tool=%r, replace_all honored). Write the full file with Write, or use an Edit/MultiEdit whose "
            "old_string matches, so the shape can be checked." % (rel, tool)
        )

    low = new_text.lower()

    def has_any(text, *needles):
        low_t = text.lower()
        return any(nd in low_t for nd in needles)

    # Trigger: does this record adopt USE as the methodology for some
    # surface? Requires a specific USE-as-methodology phrase, not the bare
    # English verb "use", so ordinary prose containing "use" doesn't
    # false-positive this gate on. Whole-document check (cheap, low
    # false-positive risk — detecting the methodology name itself, not
    # judging its content).
    use_adopted = has_any(
        new_text,
        "use method", "use(", "use 방법", "use 채택", "utilization/saturation",
        "utilization / saturation",
    )
    if not use_adopted:
        sys.exit(0)  # USE not adopted here — another signal plugin (or none) owns this record

    # Section-scoped check: split on markdown heading lines and find the
    # section whose heading matches this gate's topic ("use"). Run the
    # three signal-presence needle checks against that section's body
    # only, not the whole document. Fall back to a bounded 3-line window
    # around the first topic mention if no heading matches.
    heading_re = re.compile(r'^#{1,6}\s+(.*)$', re.MULTILINE)
    headings = list(heading_re.finditer(new_text))
    section_body = None
    for i, m in enumerate(headings):
        heading_text = m.group(1)
        if "use" in heading_text.lower():
            start = m.end()
            end = headings[i + 1].start() if i + 1 < len(headings) else len(new_text)
            section_body = new_text[start:end]
            break

    if section_body is None:
        # Fallback: bounded 3-line window around the first topic mention.
        lines = new_text.splitlines()
        first_idx = None
        for i, line in enumerate(lines):
            if has_any(
                line,
                "use method", "use(", "use 방법", "use 채택",
                "utilization/saturation", "utilization / saturation",
            ):
                first_idx = i
                break
        if first_idx is None:
            section_body = new_text
        else:
            lo = max(0, first_idx - 1)
            hi = min(len(lines), first_idx + 2)
            section_body = "\n".join(lines[lo:hi])

    missing = []
    if not has_any(section_body, "utilization", "사용률"):
        missing.append("utilization (어떤 리소스 지표를 볼 것인지 명시)")
    if not has_any(section_body, "saturation", "포화", "queue", "backlog"):
        missing.append("saturation (어떤 큐/백로그 신호를 볼 것인지 명시)")
    if not has_any(section_body, "error", "에러", "오류"):
        missing.append("errors (어떤 리소스 레벨 에러를 볼 것인지 명시)")

    if missing:
        deny(
            "record adopts USE but is missing required USE signal(s): %s. Per "
            "docs/issue-7/proposals/2026-07-31-produces-methodology-hook-machine.md, "
            "a phase-2 record adopting USE must name all three signals (utilization/"
            "saturation/errors) with a concrete instrumentation point each." % "; ".join(missing)
        )

    sys.exit(0)
except Exception as _fc_e:  # fail-closed-on-internal-error
    _fc_sys.stderr.write("signal-use-gate.sh: fail-closed: internal error: %r\n" % (_fc_e,))
    _fc_sys.exit(2)
PY
_fc_rc=$?  # fail-closed-on-internal-error
if [ "$_fc_rc" -ne 0 ] && [ "$_fc_rc" -ne 2 ]; then
  echo "${role}: refused — fail-closed: internal error (judge exited $_fc_rc)" >&2
  exit 2
fi
exit "$_fc_rc"
