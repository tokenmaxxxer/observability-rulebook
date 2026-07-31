#!/usr/bin/env bash
__fc(){ rc=$?; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "fail-closed: gate aborted (rc=$rc)" >&2; exit 2; fi; }
trap __fc EXIT
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
#     버킷/해시/제거) present somewhere in the document.
#
# Per docs/issue-7/proposals/2026-07-31-produces-methodology-hook-machine.md
# plugin #5 — this gate is the first to turn the issue-1 proposal's
# placeholder failure signal into an actual gate check.
#
# Kill switch: export OBSERVABILITY_CARDINALITY_BUDGET_GATE_OFF=1
set -uo pipefail

role="${CLAUDE_ROLE:-observability}"
deny() { echo "${role}: refused — $1" >&2; exit 2; }

case "${OBSERVABILITY_CARDINALITY_BUDGET_GATE_OFF:-}" in
  ""|0|false|no|off) ;;
  *) exit 0 ;;
esac

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
[ -z "$root" ] && deny "no project root could be determined; failing closed (cardinality-budget check cannot run)."

CB_PAYLOAD="$payload" CB_ROOT="$root" CB_ROLE="$role" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["CB_ROLE"]

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    raw = os.environ.get("CB_PAYLOAD", "")
    try:
        ev = json.loads(raw) if raw else {}
    except ValueError:
        deny("the tool-call payload is not valid JSON; the gate cannot judge the cardinality-budget shape on an unparseable write.")
    if not isinstance(ev, dict):
        deny("the tool-call payload is not a JSON object; failing closed on cardinality-budget shape.")

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["CB_ROOT"].replace("\\", "/"))
    PROPOSAL_RE = re.compile(r'^docs/issue-[0-9]+/proposals/.*observability.*\.md$')
    RECORD_RE = re.compile(r'^docs/issue-[0-9]+/reports/observability\.md$')

    def resolve(p):
        n = p.replace("\\", "/")
        a = n if posixpath.isabs(n) else posixpath.join(root, n)
        a = posixpath.normpath(a)
        try:
            return posixpath.normpath(os.path.realpath(a).replace("\\", "/"))
        except OSError:
            return a

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

    phase = None
    if PROPOSAL_RE.match(rel):
        phase = 1
    elif RECORD_RE.match(rel):
        phase = 2
    else:
        sys.exit(0)  # not a surface this gate owns

    current = None
    if os.path.isfile(r):
        try:
            with open(r, encoding="utf-8-sig") as fh:
                current = fh.read(1 << 20)
        except OSError:
            deny("%s exists but cannot be read; failing closed on the cardinality-budget check." % rel)

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
            "from the tool input (tool=%r). Write the full file with Write, or use an "
            "Edit/MultiEdit whose old_string matches, so the cardinality-budget shape can "
            "be checked." % (rel, tool)
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

    POLICY_NEEDLES = ("drop", "hash", "bucket", "aggregate", "버킷", "해시", "제거")
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
