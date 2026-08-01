#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "methodology-selector-status.sh: cannot source gate-lib.sh" >&2; exit 2; }
gate_trap_fail_closed
set -uo pipefail
gate_kill_switch_active "${OBSERVABILITY_METHODOLOGY_SELECTOR_STATUS_OFF:-}" || { trap - EXIT; exit 0; }
# PostToolUse status recorder (Write|Edit|MultiEdit|NotebookEdit|Bash, matcher ".*")
# — methodology-selector only, sibling to methodology-selector-gate.sh.
#
# A PreToolUse gate cannot safely record state describing a write: a later
# gate in the same PreToolUse chain may still deny the write after this one
# allowed it, so any state written at PreToolUse time could describe a
# write that never actually happened. This script re-derives the same
# pass/fail judgment independently, but at PostToolUse time — after the
# write has already completed (or failed) — by re-reading the file's
# now-current on-disk content. It is purely informational: it never
# denies, since a PostToolUse hook cannot undo a completed tool call, and
# on any failure (bad JSON, unwritable state dir, wrong tool, non-matching
# path, non-success tool_response, file unreadable, content fails the
# needle checks) it exits 0 silently.
#
# Kill switch: export OBSERVABILITY_METHODOLOGY_SELECTOR_STATUS_OFF=1 (or
# true/yes/on, case-insensitive) to disable. Any other value, including an
# unrecognized typo, keeps this script active (fail closed on kill-switch
# ambiguity — see gate-lib.sh gate_kill_switch_active). Note: "active"
# here just means "may write state"; this script never denies regardless.

role="${CLAUDE_ROLE:-observability}"

command -v python3 >/dev/null 2>&1 || exit 0

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

MSG_PAYLOAD="$payload" MSG_ROLE="$role" GLPY="$GATE_LIB_PY" \
python3 <<'PY' 2>/dev/null || exit 0
try:
    import json, os, posixpath, re, sys

    import importlib.util
    _spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GLPY"])
    gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

    raw = os.environ.get("MSG_PAYLOAD", "")
    try:
        ev = json.loads(raw)
    except Exception:
        sys.exit(0)
    if not isinstance(ev, dict):
        sys.exit(0)

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        sys.exit(0)

    tr = ev.get("tool_response")
    # Success signal: tool_response for a successful Write/Edit/MultiEdit/
    # NotebookEdit carries no error/is_error indicator; an errored one does.
    is_success = isinstance(tr, dict) and not tr.get("error") and not tr.get("is_error")
    if not is_success:
        sys.exit(0)

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

    cwd = ev.get("cwd") if isinstance(ev.get("cwd"), str) else None
    root = ""
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR")
    for candidate in (project_dir, cwd, os.path.dirname(path) or None):
        if candidate and os.path.isdir(candidate):
            root = os.path.realpath(candidate)
            break
    if not root:
        sys.exit(0)

    PROPOSAL_RE = re.compile(r'^docs/issue-[0-9]+/proposals/.*observability.*\.md$')
    ISSUE_RE = re.compile(r'issue-([0-9]+)')

    rel = gate_lib.gate_normalize_path(root, path)
    if rel is None:
        sys.exit(0)
    if not PROPOSAL_RE.match(rel):
        sys.exit(0)

    r = posixpath.join(root, rel) if rel else root
    if not os.path.isfile(r):
        sys.exit(0)
    try:
        with open(r, encoding="utf-8-sig") as fh:
            new_text = fh.read(1 << 20)
    except OSError:
        sys.exit(0)

    # --- needle-matching logic, copied verbatim from methodology-selector-gate.sh ---
    HEADING_RE = re.compile(r'^#{1,6}\s+(.*)$', re.MULTILINE)

    def split_sections(text):
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
        lines = text.split("\n")
        for i, line in enumerate(lines):
            low_line = line.lower()
            if any(w in low_line for w in topic_words):
                start = max(0, i - 1)
                end = min(len(lines), i + 2)
                return "\n".join(lines[start:end])
        return ""

    def has_any(text, *needles):
        low = text.lower()
        return any(nd in low for nd in needles)

    methodology_needles = (
        "red method", "use method", "golden signals", "golden signal",
        "rate/errors/duration", "red (rate", "red(rate", " red/", "/red ",
        "red 방법", "use 방법",
    )
    methodology_topic_words = ("methodology", "method", "signal", "red", "use", "golden")
    if not has_any(section_scoped(new_text, methodology_topic_words), *methodology_needles):
        sys.exit(0)

    surface_needles = (
        "request-driven", "request driven", "resource-bound", "resource bound",
        "service-rollup", "service rollup", "요청 기반", "자원 기반", "서비스 롤업",
    )
    surface_topic_words = ("surface", "classification", "classify", "표면", "분류")
    if not has_any(section_scoped(new_text, surface_topic_words), *surface_needles):
        sys.exit(0)

    m = ISSUE_RE.search(rel)
    if not m:
        sys.exit(0)
    issue_n = m.group(1)
    try:
        state_dir = posixpath.join(root, ".observability-phase1-methods")
        os.makedirs(state_dir, exist_ok=True)
        state_path = posixpath.join(state_dir, "%s.json" % issue_n)
        with open(state_path, "w", encoding="utf-8") as fh:
            json.dump({"issue": issue_n, "methodology_named": True}, fh)
    except OSError:
        pass  # best-effort only

    sys.exit(0)
except SystemExit:
    raise
except Exception:
    sys.exit(0)
PY
exit 0
