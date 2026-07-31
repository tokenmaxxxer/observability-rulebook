#!/usr/bin/env bash
__fc(){ rc=$?; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "fail-closed: gate aborted (rc=$rc)" >&2; exit 2; fi; }
trap __fc EXIT
# PreToolUse gate (Write|Edit|MultiEdit) — cross-cutting explorability
# norm, methodology-agnostic. Covers BOTH write surfaces in one gate:
#
#   phase-1 (proposal): docs/issue-<n>/proposals/*observability*.md
#     — require an explorability mention (explorability/탐색가능/
#     ad-hoc/adhoc/ad hoc/애드혹) — a one-line check that the design
#     keeps exploration open, not just fixed dashboards.
#   phase-2 (record):   docs/issue-<n>/reports/observability.md
#     — require BOTH the explorability mention AND a concrete
#     query-shape marker (SELECT/select /query:/쿼리:/backtick code
#     fence/WHERE/group by) — an actual ad-hoc query example, not
#     just the word.
#
# Per docs/issue-7/proposals/2026-07-31-produces-methodology-hook-machine.md
# plugin #6.
#
# Kill switch: export OBSERVABILITY_EXPLORABILITY_GATE_OFF=1
set -uo pipefail

role="${CLAUDE_ROLE:-observability}"
deny() { echo "${role}: refused — $1" >&2; exit 2; }

case "${OBSERVABILITY_EXPLORABILITY_GATE_OFF:-}" in
  ""|0|false|no|off) ;;
  *) exit 0 ;;
esac

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
[ -z "$root" ] && deny "no project root could be determined; failing closed (explorability check cannot run)."

EX_PAYLOAD="$payload" EX_ROOT="$root" EX_ROLE="$role" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["EX_ROLE"]

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    raw = os.environ.get("EX_PAYLOAD", "")
    try:
        ev = json.loads(raw) if raw else {}
    except ValueError:
        deny("the tool-call payload is not valid JSON; the gate cannot judge the explorability shape on an unparseable write.")
    if not isinstance(ev, dict):
        deny("the tool-call payload is not a JSON object; failing closed on explorability shape.")

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["EX_ROOT"].replace("\\", "/"))
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
            deny("%s exists but cannot be read; failing closed on the explorability check." % rel)

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
            "Edit/MultiEdit whose old_string matches, so the explorability shape can be "
            "checked." % (rel, tool)
        )

    low = new_text.lower()

    def has_any(*needles):
        return any(nd in low for nd in needles)

    EXPLORABILITY_NEEDLES = ("explorability", "탐색가능", "ad-hoc", "adhoc", "ad hoc", "애드혹")
    QUERY_SHAPE_NEEDLES = ("select", "query:", "쿼리:", "```", "where", "group by")

    has_explorability = has_any(*EXPLORABILITY_NEEDLES)
    has_query_shape = has_any(*QUERY_SHAPE_NEEDLES)

    if phase == 1:
        if not has_explorability:
            deny(
                "explorability-check-missing: %s does not mention explorability "
                "(explorability/탐색가능/ad-hoc/adhoc/ad hoc/애드혹) — phase-1 proposals "
                "must include a one-line check that the design keeps exploration open, "
                "not just fixed dashboards." % rel
            )
        sys.exit(0)

    # phase 2: needs both the explorability mention AND a concrete query-shape marker.
    if not has_explorability:
        deny(
            "explorability-check-missing: %s does not mention explorability "
            "(explorability/탐색가능/ad-hoc/adhoc/ad hoc/애드혹) — phase-2 records must "
            "show at least one concrete ad-hoc query example that answers a question not "
            "pre-defined by a dashboard." % rel
        )
    if not has_query_shape:
        deny(
            "ad-hoc-example-missing: %s mentions explorability but shows no concrete query "
            "example (expected a query-shape marker such as SELECT/query:/쿼리:/a code "
            "fence/WHERE/GROUP BY) — the word alone is not a phase-2 ad-hoc query example." % rel
        )

    sys.exit(0)
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
