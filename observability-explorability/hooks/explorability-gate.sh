#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "explorability-gate.sh: cannot source gate-lib.sh" >&2; exit 2; }
gate_trap_fail_closed
set -uo pipefail
gate_kill_switch_active "${OBSERVABILITY_EXPLORABILITY_GATE_OFF:-}" || { trap - EXIT; exit 0; }

# PreToolUse gate (Write|Edit|MultiEdit|NotebookEdit) — cross-cutting
# explorability norm, methodology-agnostic. Covers BOTH write surfaces in
# one gate:
#
#   phase-1 (proposal): docs/issue-<n>/proposals/*observability*.md
#     — require an explorability mention (explorability/탐색가능/
#     ad-hoc/adhoc/ad hoc/애드혹) — a one-line check that the design
#     keeps exploration open, not just fixed dashboards.
#   phase-2 (record):   docs/issue-<n>/reports/observability.md
#     — require the explorability mention AND a concrete query-shape
#     marker (SELECT/select /query:/쿼리:/backtick code fence/WHERE/
#     group by) found in the SAME paragraph as the mention — an actual
#     ad-hoc query example adjacent to the claim, not just the word
#     anywhere in the document.
#
# Per docs/issue-7/proposals/2026-07-31-produces-methodology-hook-machine.md
# plugin #6. Migrated to core gate-lib per
# docs/issue-10/proposals/2026-08-01-gate-a-plus-hardening.md.
#
# Kill switch: export OBSERVABILITY_EXPLORABILITY_GATE_OFF=1 (recognized
# on-spellings only: 1/true/yes/on, case-insensitive; anything else,
# including unrecognized garbage, stays active).

role="${CLAUDE_ROLE:-observability}"
deny() { gate_deny "$role" "$1"; }

command -v python3 >/dev/null 2>&1 || deny "explorability-gate.sh requires python3, which is not on PATH; denying rather than guessing."

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || deny "explorability-gate: empty tool-use payload on stdin; cannot evaluate the gate."

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
[ -z "$root" ] && deny "no project root could be determined; failing closed (explorability check cannot run)."

EX_PAYLOAD="$payload" EX_ROOT="$root" EX_ROLE="$role" GLPY="$GATE_LIB_PY" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["EX_ROLE"]

    import importlib.util
    _spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GLPY"])
    gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    def allow():
        sys.exit(0)

    raw = os.environ.get("EX_PAYLOAD", "")
    ev = gate_lib.gate_parse_json_or_deny(raw, deny)

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["EX_ROOT"].replace("\\", "/"))
    PROPOSAL_RE = re.compile(r'^docs/issue-[0-9]+/proposals/.*observability.*\.md$')
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
                if cand_rel and (PROPOSAL_RE.match(cand_rel) or RECORD_RE.match(cand_rel)):
                    path = token
                    is_bash = True
                    break
    if path is None:
        sys.exit(0)

    rel = gate_lib.gate_normalize_path(root, path)
    if rel is None:
        sys.exit(0)
    if not (PROPOSAL_RE.match(rel) or RECORD_RE.match(rel)):
        sys.exit(0)
    if is_bash:
        deny(
            "this Bash command appears to write %s; the produces-shape check cannot inspect "
            "a Bash-authored write's resulting content — use Write/Edit/MultiEdit for this "
            "path instead." % rel
        )
    r = posixpath.join(root, rel) if rel else root

    phase = 1 if PROPOSAL_RE.match(rel) else 2

    current = None
    if os.path.isfile(r):
        try:
            with open(r, encoding="utf-8-sig") as fh:
                current = fh.read(1 << 20)
        except OSError:
            deny("%s exists but cannot be read; failing closed on the explorability check." % rel)

    new_text, ok = gate_lib.gate_reconstruct_write(tool, ti, current)
    if not ok:
        deny(
            "this write targets %s but the gate cannot determine the resulting content from the tool input "
            "(tool=%r, replace_all honored). Write the full file with Write, or use an Edit/MultiEdit whose "
            "old_string matches, so the shape can be checked." % (rel, tool)
        )

    EXPLORABILITY_NEEDLES = ("explorability", "탐색가능", "ad-hoc", "adhoc", "ad hoc", "애드혹")
    QUERY_SHAPE_NEEDLES = ("select", "query:", "쿼리:", "```", "where", "group by")

    lines = new_text.split("\n")
    low_lines = [ln.lower() for ln in lines]

    def has_any(text, *needles):
        return any(nd in text for nd in needles)

    has_explorability = any(has_any(ln, *EXPLORABILITY_NEEDLES) for ln in low_lines)

    def paragraph_bounds(i):
        start = i
        while start > 0 and lines[start - 1].strip() != "":
            start -= 1
        end = i
        while end < len(lines) - 1 and lines[end + 1].strip() != "":
            end += 1
        return start, end

    def adjacency_has_query_shape():
        for i, ln in enumerate(low_lines):
            if has_any(ln, *EXPLORABILITY_NEEDLES):
                start, end = paragraph_bounds(i)
                # fixed 3-line window fallback in case paragraph splitting
                # is degenerate (e.g. single huge paragraph with no blank
                # lines around the mention).
                if end - start > 6:
                    start = max(0, i - 1)
                    end = min(len(lines) - 1, i + 1)
                window = low_lines[start:end + 1]
                if any(has_any(wln, *QUERY_SHAPE_NEEDLES) for wln in window):
                    return True
        return False

    if phase == 1:
        if not has_explorability:
            deny(
                "explorability-check-missing: %s does not mention explorability "
                "(explorability/탐색가능/ad-hoc/adhoc/ad hoc/애드혹) — phase-1 proposals "
                "must include a one-line check that the design keeps exploration open, "
                "not just fixed dashboards." % rel
            )
        allow()

    # phase 2: needs both the explorability mention AND a concrete
    # query-shape marker found adjacent to it (same paragraph, or a
    # 3-line fallback window).
    if not has_explorability:
        deny(
            "explorability-check-missing: %s does not mention explorability "
            "(explorability/탐색가능/ad-hoc/adhoc/ad hoc/애드혹) — phase-2 records must "
            "show at least one concrete ad-hoc query example that answers a question not "
            "pre-defined by a dashboard." % rel
        )
    if not adjacency_has_query_shape():
        deny(
            "ad-hoc-example-missing: %s mentions explorability but shows no concrete query "
            "example near that mention (expected a query-shape marker such as "
            "SELECT/query:/쿼리:/a code fence/WHERE/GROUP BY in the same paragraph) — the "
            "word alone, or a marker elsewhere in the document, is not a phase-2 ad-hoc "
            "query example." % rel
        )

    allow()
except SystemExit:
    raise
except Exception as _fc_e:  # fail-closed-on-internal-error
    _fc_sys.stderr.write("explorability-gate.sh: fail-closed: internal error: %r\n" % (_fc_e,))
    _fc_sys.exit(2)
PY
_fc_rc=$?  # fail-closed-on-internal-error
if [ "$_fc_rc" -ne 0 ] && [ "$_fc_rc" -ne 2 ]; then
  echo "${role}: refused — fail-closed: internal error (judge exited $_fc_rc)" >&2
  exit 2
fi
exit "$_fc_rc"
