#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "cardinality-budget-gate.sh: cannot source gate-lib.sh" >&2; exit 2; }
gate_trap_fail_closed
set -uo pipefail
gate_kill_switch_active "${OBSERVABILITY_CARDINALITY_BUDGET_GATE_OFF:-}" || { trap - EXIT; exit 0; }
# PreToolUse gate (Write|Edit|MultiEdit) — cross-cutting cardinality-budget
# norm, methodology-agnostic. Covers BOTH write surfaces in one gate:
#
#   phase-1 (proposal): docs/issue-<n>/proposals/*observability*.md
#     — require a mention of "cardinality"/"카디널리티" (preliminary
#     high-cardinality candidate list).
#   phase-2 (record):   docs/issue-<n>/reports/observability.md
#     — require "cardinality"/"카디널리티" present, NOT immediately
#     adjacent to a placeholder token ("N/A"/"해당 없음"/"TBD"), and an
#     explicit handling-policy keyword (drop/hash/bucket/aggregate/
#     버킷/해시/제거) present on the SAME dimension line as the dimension
#     it governs.
#
# Per docs/issue-7/proposals/2026-07-31-produces-methodology-hook-machine.md
# plugin #5 — this gate is the first to turn the issue-1 proposal's
# placeholder failure signal into an actual gate check.
#
# This gate is built on the shared core gate-lib (docs/issue-10/proposals/
# 2026-08-01-gate-a-plus-hardening.md) — trap/kill-switch/path-normalize/
# JSON-parse/write-reconstruct machinery is sourced from gate-lib.sh /
# gate-lib.py rather than hand-rolled.
#
# Kill switch: export OBSERVABILITY_CARDINALITY_BUDGET_GATE_OFF=1 (or true/
# yes/on). Any other value, including an unset/empty var or a typo, leaves
# the gate active (gate_kill_switch_active fail-closed convention).

role="${CLAUDE_ROLE:-observability}"
deny() { gate_deny "$role" "$1"; }

command -v python3 >/dev/null 2>&1 || deny "cardinality-budget-gate.sh requires python3, which is not on PATH; denying rather than guessing."

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || deny "cardinality-budget-gate: empty tool-use payload on stdin; cannot evaluate the gate."

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
[ -z "$root" ] && deny "no project root could be determined; failing closed (cardinality-budget check cannot run)."

CB_PAYLOAD="$payload" CB_ROOT="$root" CB_ROLE="$role" GLPY="$GATE_LIB_PY" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["CB_ROLE"]

    import importlib.util
    _spec = importlib.util.spec_from_file_location("gate_lib", os.environ["GLPY"])
    gate_lib = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gate_lib)

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    def allow():
        sys.exit(0)

    raw = os.environ.get("CB_PAYLOAD", "")
    ev = gate_lib.gate_parse_json_or_deny(raw, deny)

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["CB_ROOT"].replace("\\", "/"))
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
                if cand_rel and (RECORD_RE.match(cand_rel) or PROPOSAL_RE.match(cand_rel)):
                    path = token
                    is_bash = True
                    break
    if path is None:
        allow()

    rel = gate_lib.gate_normalize_path(root, path)
    if rel is None:
        sys.exit(0)
    if not RECORD_RE.match(rel) and not PROPOSAL_RE.match(rel):
        sys.exit(0)  # not a surface this gate owns
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
            deny("%s exists but cannot be read; failing closed on the cardinality-budget check." % rel)

    new_text, ok = gate_lib.gate_reconstruct_write(tool, ti, current)
    if not ok:
        deny(
            "this write targets %s but the gate cannot determine the resulting content from the tool input "
            "(tool=%r, replace_all honored). Write the full file with Write, or use an Edit/MultiEdit whose "
            "old_string matches, so the shape can be checked." % (rel, tool)
        )

    CARD_RE = re.compile(r'(cardinality|카디널리티)', re.IGNORECASE)

    if not CARD_RE.search(new_text):
        if phase == 1:
            deny(
                "%s is missing a cardinality mention: phase-1 proposals must include a "
                "preliminary list of candidate high-cardinality dimensions (e.g. user_id, "
                "request_id, raw URL path)." % rel
            )
        else:
            deny(
                "%s is missing a cardinality mention: phase-2 records must include the "
                "confirmed high-cardinality dimension list and an explicit handling policy "
                "per dimension." % rel
            )

    if phase == 1:
        sys.exit(0)

    # phase 2: placeholder-adjacency check — look at the line containing
    # each cardinality mention and deny if it also carries a placeholder.
    PLACEHOLDER_NEEDLES = ("n/a", "tbd", "해당 없음")
    lines = new_text.splitlines()
    placeholder_hit = False
    for ln in lines:
        if CARD_RE.search(ln):
            low_ln = ln.lower()
            if any(nd in low_ln for nd in PLACEHOLDER_NEEDLES):
                placeholder_hit = True
                break
    if placeholder_hit:
        deny(
            "%s: the cardinality statement is immediately adjacent to a placeholder "
            "('N/A'/'해당 없음'/'TBD') — phase-2 requires the CONFIRMED high-cardinality "
            "dimension list plus an explicit handling policy, not a placeholder." % rel
        )

    # phase 2: structural per-dimension policy-needle check. Find the
    # cardinality section (split on markdown headings, use the section
    # whose heading mentions "cardinality"; if none matches, use the whole
    # document). Within that section, a "dimension line" is a list item
    # ("- <identifier>:") or table row ("| <identifier> |"); require the
    # SAME line to also carry a policy needle, not merely present anywhere
    # in the document.
    POLICY_NEEDLES = ("drop", "hash", "bucket", "aggregate", "버킷", "해시", "제거")
    HEADING_RE = re.compile(r'^#{1,6}\s+.*$', re.MULTILINE)
    DIM_RE = re.compile(r'^\s*(?:[-*]\s+`?([A-Za-z0-9_.\-]+)`?\s*:|\|\s*`?([A-Za-z0-9_.\-]+)`?\s*\|)')

    headings = list(HEADING_RE.finditer(new_text))
    section_text = new_text
    if headings:
        chosen = None
        for i, h in enumerate(headings):
            if "cardinality" in h.group(0).lower() or "카디널리티" in h.group(0):
                start = h.end()
                end = headings[i + 1].start() if i + 1 < len(headings) else len(new_text)
                chosen = new_text[start:end]
                break
        if chosen is not None:
            section_text = chosen

    missing_dims = []
    dim_lines_found = False
    for ln in section_text.splitlines():
        m = DIM_RE.match(ln)
        if not m:
            continue
        dim_lines_found = True
        dim = m.group(1) or m.group(2)
        low_ln = ln.lower()
        if not any(nd in low_ln for nd in POLICY_NEEDLES):
            missing_dims.append(dim)

    if dim_lines_found:
        if missing_dims:
            deny(
                "handling-policy-missing: %s lists high-cardinality dimension(s) %s without a "
                "handling policy (expected one of drop/hash/bucket/aggregate/버킷/해시/제거) on "
                "that same line/list item." % (rel, ", ".join(missing_dims))
            )
    else:
        # No structured (list/table) dimension lines were found in the
        # cardinality section — fall back to the prior whole-document
        # needle check rather than silently passing prose-only records.
        low_full = new_text.lower()
        if not any(nd in low_full for nd in POLICY_NEEDLES):
            deny(
                "handling-policy-missing: %s mentions cardinality but names no handling policy "
                "(expected one of drop/hash/bucket/aggregate/버킷/해시/제거) for the confirmed "
                "high-cardinality dimensions." % rel
            )

    sys.exit(0)
except Exception as _fc_e:  # fail-closed-on-internal-error
    _fc_sys.stderr.write("cardinality-budget-gate.sh: fail-closed: internal error: %r\n" % (_fc_e,))
    _fc_sys.exit(2)
PY
_fc_rc=$?  # fail-closed-on-internal-error
if [ "$_fc_rc" -ne 0 ] && [ "$_fc_rc" -ne 2 ]; then
  echo "${role}: refused — fail-closed: internal error (judge exited $_fc_rc)" >&2
  exit 2
fi
exit "$_fc_rc"
