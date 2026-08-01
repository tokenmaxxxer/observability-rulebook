#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh"
gate_trap_fail_closed
set -uo pipefail
gate_kill_switch_active "${OBSERVABILITY_METHODOLOGY_SELECTOR_GATE_OFF:-}" || { trap - EXIT; exit 0; }
# PreToolUse gate (Write|Edit|MultiEdit|NotebookEdit) — methodology-selector only.
#
# On a write whose resolved target is docs/issue-<n>/proposals/*observability*.md
# (the phase-1 proposal surface only — this plugin does not touch the
# phase-2 record), parse the PROPOSED content and require both a named
# signal methodology (RED/USE/Golden Signals) and a named surface
# classification (request-driven/resource-bound/service-rollup). On a
# passing write, best-effort record the pass into
# .observability-phase1-methods/<issue-n>.json for observability-phase-trace
# to consume later.
#
# Kill switch: export OBSERVABILITY_METHODOLOGY_SELECTOR_GATE_OFF=1 (or
# true/yes/on, case-insensitive) to disable. Any other value, including an
# unrecognized typo, keeps the gate active (fail closed on kill-switch
# ambiguity — see gate-lib.sh gate_kill_switch_active).

role="${CLAUDE_ROLE:-observability}"
deny() { gate_deny "$role" "$1"; }

command -v python3 >/dev/null 2>&1 || deny "methodology-selector-gate.sh requires python3, which is not on PATH; denying rather than guessing."

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || deny "methodology-selector-gate: empty tool-use payload on stdin; cannot evaluate the produces gate."

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

MSG_PAYLOAD="$payload" MSG_ROOT="$root" MSG_ROLE="$role" GLPY="$GATE_LIB_PY" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["MSG_ROLE"]

    import importlib.util
    _spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GLPY"])
    gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    def allow():
        sys.exit(0)

    raw = os.environ.get("MSG_PAYLOAD", "")
    ev = gate_lib.gate_parse_json_or_deny(raw, deny)

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["MSG_ROOT"].replace("\\", "/"))
    PROPOSAL_RE = re.compile(r'^docs/issue-[0-9]+/proposals/.*observability.*\.md$')
    ISSUE_RE = re.compile(r'issue-([0-9]+)')

    # Only Write/Edit/MultiEdit/NotebookEdit reach the record in a form
    # whose full resulting content we can read. Everything else is out of
    # this gate's scope and passed through.
    path = None
    if tool in ("Write", "Edit", "MultiEdit"):
        p = ti.get("file_path")
        if isinstance(p, str) and p:
            path = p
    elif tool == "NotebookEdit":
        p = ti.get("notebook_path")
        if isinstance(p, str) and p:
            path = p
    if path is None:
        sys.exit(0)

    rel = gate_lib.gate_normalize_path(root, path)
    if rel is None:
        sys.exit(0)
    if not PROPOSAL_RE.match(rel):
        sys.exit(0)  # not the phase-1 proposal surface — not this gate's business
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

    # --- semantic check: section-scoped, with bounded-window fallback ---
    #
    # This record type (a phase-1 proposal) has no fixed heading set, so a
    # heading match is the exception rather than the rule for this gate.
    # We first try to find a markdown section (^#{1,6}\s+heading) whose
    # heading text names the topic; if none matches — the common case —
    # we fall back to a bounded 3-line window around the first
    # topic-adjacent mention anywhere in the document. Only if the topic
    # is not mentioned at all do we treat it as missing, unchanged from
    # the pre-migration whole-document behavior.
    HEADING_RE = re.compile(r'^#{1,6}\s+(.*)$', re.MULTILINE)

    def split_sections(text):
        """Return [(heading_text_or_None, body_text), ...]. The first
        element covers any preamble before the first heading (heading is
        None)."""
        matches = list(HEADING_RE.finditer(text))
        if not matches:
            return [(None, text)]
        sections = []
        pre = text[:matches[0].start()]
        if pre.strip():
            sections.append((None, pre))
        for i, m in enumerate(matches):
            heading = m.group(1)
            body_start = m.end()
            body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
            sections.append((heading, text[body_start:body_end]))
        return sections

    def section_scoped(text, topic_words):
        for heading, body in split_sections(text):
            if heading and any(w in heading.lower() for w in topic_words):
                return body
        # Fallback: bounded 3-line window around the first topic-adjacent
        # mention in the whole document (primary path for this gate).
        lines = text.split("\n")
        for i, line in enumerate(lines):
            low_line = line.lower()
            if any(w in low_line for w in topic_words):
                start = max(0, i - 1)
                end = min(len(lines), i + 2)
                return "\n".join(lines[start:end])
        return ""  # no mention at all — treated as missing, same as before

    def has_any(text, *needles):
        low = text.lower()
        return any(nd in low for nd in needles)

    missing = []

    methodology_needles = (
        "red method", "use method", "golden signals", "golden signal",
        "rate/errors/duration", "red (rate", "red(rate", " red/", "/red ",
        "red 방법", "use 방법",
    )
    methodology_topic_words = ("methodology", "method", "signal", "red", "use", "golden")
    if not has_any(section_scoped(new_text, methodology_topic_words), *methodology_needles):
        missing.append("signal-methodology-name (RED/USE/Golden Signals 중 하나를 명명해야 함)")

    surface_needles = (
        "request-driven", "request driven", "resource-bound", "resource bound",
        "service-rollup", "service rollup", "요청 기반", "자원 기반", "서비스 롤업",
    )
    surface_topic_words = ("surface", "classification", "classify", "표면", "분류")
    if not has_any(section_scoped(new_text, surface_topic_words), *surface_needles):
        missing.append("surface-classification (request-driven/resource-bound/service-rollup 중 하나로 표면을 분류해야 함)")

    if missing:
        deny(
            "proposal is missing required phase-1 methodology-selection component(s): %s. Per "
            "docs/issue-7/proposals/2026-07-31-produces-methodology-hook-machine.md, every "
            "phase-1 proposal must classify each touched surface and name exactly one signal "
            "methodology for it." % "; ".join(missing)
        )

    # Passing write: best-effort record state for observability-phase-trace to consume later.
    m = ISSUE_RE.search(rel)
    if m:
        issue_n = m.group(1)
        try:
            state_dir = posixpath.join(root, ".observability-phase1-methods")
            os.makedirs(state_dir, exist_ok=True)
            state_path = posixpath.join(state_dir, "%s.json" % issue_n)
            with open(state_path, "w", encoding="utf-8") as fh:
                json.dump({"issue": issue_n, "methodology_named": True}, fh)
        except OSError:
            pass  # best-effort only; does not fail the gate

    sys.exit(0)
except Exception as _fc_e:  # fail-closed-on-internal-error
    _fc_sys.stderr.write("methodology-selector-gate.sh: fail-closed: internal error: %r\n" % (_fc_e,))
    _fc_sys.exit(2)
PY
_fc_rc=$?  # fail-closed-on-internal-error
if [ "$_fc_rc" -ne 0 ] && [ "$_fc_rc" -ne 2 ]; then
  echo "${role}: refused — fail-closed: internal error (judge exited $_fc_rc)" >&2
  exit 2
fi
exit "$_fc_rc"
