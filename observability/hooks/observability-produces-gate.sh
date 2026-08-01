#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "observability-produces-gate.sh: cannot source gate-lib.sh" >&2; exit 2; }
gate_trap_fail_closed
set -uo pipefail
gate_kill_switch_active "${OBSERVABILITY_PRODUCES_GATE_OFF:-}" || { trap - EXIT; exit 0; }
# PreToolUse gate (Write|Edit|MultiEdit) — role-owned, observability only.
#
# On a write whose resolved target is docs/issue-<n>/reports/observability.md,
# parse the PROPOSED content and require the three phase-2 `produces`
# components this rulebook's proposal (docs/issue-1/proposals/
# 2026-07-31-observability-rulebook-norms.md, section (b)) commits to:
# a named signal-selection methodology (RED/USE/Golden Signals), an explicit
# cardinality budget, and an ad-hoc/explorable query example. This is a
# role-specific produces-shape check, independent of core canon's
# role-agnostic §20 field check (record-fields-gate.sh) — it does not
# replace that gate and does not duplicate its fields.
#
# Sources core/hooks/lib/gate-lib.sh/gate-lib.py (gate-house standard,
# issue-72) for the trap/kill-switch/path-normalize/reconstruct/deny
# machinery; only this gate's own record path and needle vocabulary are
# role-specific.
#
# Kill switch: export OBSERVABILITY_PRODUCES_GATE_OFF=1

role="${CLAUDE_ROLE:-observability}"
deny() { gate_deny "$role" "$1"; }

command -v python3 >/dev/null 2>&1 || deny "observability-produces-gate.sh requires python3, which is not on PATH; denying rather than guessing."

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || deny "observability-produces-gate: empty tool-use payload on stdin; cannot evaluate the produces gate."

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

OG_PAYLOAD="$payload" OG_ROOT="$root" OG_ROLE="$role" GLPY="$GATE_LIB_PY" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["OG_ROLE"]

    import importlib.util
    _spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GLPY"])
    gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    raw = os.environ.get("OG_PAYLOAD", "")
    ev = gate_lib.gate_parse_json_or_deny(raw, deny)

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["OG_ROOT"].replace("\\", "/"))
    RECORD_RE = re.compile(r'^docs/issue-[0-9]+/reports/observability\.md$')

    # Only Write/Edit/MultiEdit/NotebookEdit reach the record in a form
    # whose full resulting content we can read. Everything else is out of
    # this gate's scope and passed through.
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
        sys.exit(0)  # not this role's own record — not this gate's business
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
            deny("%s exists but cannot be read; failing closed on the produces-shape check." % rel)

    new_text, ok = gate_lib.gate_reconstruct_write(tool, ti, current)
    if not ok:
        deny(
            "this write targets %s but the gate cannot determine the resulting content from the tool input "
            "(tool=%r, replace_all honored). Write the full file with Write, or use an Edit/MultiEdit whose "
            "old_string matches, so the shape can be checked." % (rel, tool)
        )

    def has_any(text, *needles):
        return any(nd in text for nd in needles)

    HEADING_RE = re.compile(r'^#{1,6}\s+(.*)$', re.MULTILINE)

    def section_body(topic_substr):
        """Return the lowercased body of the first heading whose text
        contains topic_substr (case-insensitive), or None if no heading
        matches."""
        matches = list(HEADING_RE.finditer(new_text))
        for i, m in enumerate(matches):
            heading = m.group(1).lower()
            if topic_substr in heading:
                start = m.end()
                end = matches[i + 1].start() if i + 1 < len(matches) else len(new_text)
                return new_text[start:end].lower()
        return None

    def bounded_window(needles):
        """Fallback: a 3-line window around the first mention of any needle
        in the whole document, or None if no mention at all."""
        lines = new_text.splitlines()
        low_lines = [ln.lower() for ln in lines]
        for i, ln in enumerate(low_lines):
            if any(nd in ln for nd in needles):
                lo = max(0, i - 1)
                hi = min(len(low_lines), i + 2)
                return "\n".join(low_lines[lo:hi])
        return None

    def check_component(heading_topic, needles):
        """SECTION-SCOPED check: find the section whose heading matches
        heading_topic and require a needle within that section's body. If
        no matching heading exists, fall back to a bounded window around
        the first topic-adjacent mention anywhere in the document. If
        there is no mention at all, treat as missing."""
        body = section_body(heading_topic)
        if body is not None:
            return has_any(body, *needles)
        window = bounded_window(needles)
        if window is not None:
            return has_any(window, *needles)
        return False

    METHOD_NEEDLES = ("red method", "use method", "golden signals", "rate/errors/duration",
                       "red (rate", "red(rate", " red/", "/red ", "red 방법", "use 방법",
                       "golden signal")
    CARDINALITY_NEEDLES = ("cardinality", "카디널리티")
    ADHOC_NEEDLES = ("ad-hoc", "adhoc", "ad hoc", "애드혹", "탐색 쿼리", "explorability", "탐색가능")

    missing = []
    if not check_component("signal", METHOD_NEEDLES) and not check_component("method", METHOD_NEEDLES):
        missing.append("signal-selection-methodology (RED/USE/Golden Signals 중 하나를 명명하고 근거를 진술해야 함)")
    if not check_component("cardinality", CARDINALITY_NEEDLES):
        missing.append("cardinality-budget (고카디널리티 차원 목록과 처리 방침을 명시해야 함 — 'N/A' 류 무의미한 자리표시자는 별도 리뷰에서 실질 위반으로 취급)")
    if not check_component("ad-hoc", ADHOC_NEEDLES) and not check_component("ad hoc", ADHOC_NEEDLES) and not check_component("explor", ADHOC_NEEDLES):
        missing.append("ad-hoc-query-example (사전에 정의하지 않은 질문에 답하는 애드혹 쿼리 예시가 최소 하나 있어야 함)")

    if missing:
        deny(
            "record is missing required phase-2 produces component(s): %s. Per "
            "docs/issue-1/proposals/2026-07-31-observability-rulebook-norms.md section (b), "
            "every observability phase-2 record must name its signal-selection methodology, "
            "state an explicit cardinality budget, and show an ad-hoc query example." % "; ".join(missing)
        )

    sys.exit(0)
except Exception as _fc_e:  # fail-closed-on-internal-error
    _fc_sys.stderr.write("observability-produces-gate.sh: fail-closed: internal error: %r\n" % (_fc_e,))
    _fc_sys.exit(2)
PY
_fc_rc=$?  # fail-closed-on-internal-error
if [ "$_fc_rc" -ne 0 ] && [ "$_fc_rc" -ne 2 ]; then
  echo "${role}: refused — fail-closed: internal error (judge exited $_fc_rc)" >&2
  exit 2
fi
exit "$_fc_rc"
