#!/usr/bin/env bash
__fc(){ rc=$?; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "fail-closed: gate aborted (rc=$rc)" >&2; exit 2; fi; }
trap __fc EXIT
# PreToolUse gate (Write|Edit|MultiEdit) — methodology-selector only.
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
# Kill switch: export OBSERVABILITY_METHODOLOGY_SELECTOR_GATE_OFF=1
set -uo pipefail

role="${CLAUDE_ROLE:-observability}"
deny() { echo "${role}: refused — $1" >&2; exit 2; }

case "${OBSERVABILITY_METHODOLOGY_SELECTOR_GATE_OFF:-}" in
  ""|0|false|no|off) ;;
  *) exit 0 ;;
esac

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
[ -z "$root" ] && deny "no project root could be determined; failing closed (produces-shape check cannot run)."

MSG_PAYLOAD="$payload" MSG_ROOT="$root" MSG_ROLE="$role" \
python3 <<'PY'
import sys as _fc_sys  # fail-closed-on-internal-error
try:
    import json, os, posixpath, re, sys

    role = os.environ["MSG_ROLE"]

    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)

    raw = os.environ.get("MSG_PAYLOAD", "")
    try:
        ev = json.loads(raw) if raw else {}
    except ValueError:
        deny("the tool-call payload is not valid JSON; the gate cannot judge the produces shape on an unparseable write.")
    if not isinstance(ev, dict):
        deny("the tool-call payload is not a JSON object; failing closed on produces shape.")

    tool = ev.get("tool_name")
    ti = ev.get("tool_input")
    if not isinstance(ti, dict):
        deny("tool_input is missing or not a JSON object; the gate cannot judge a write it cannot parse.")

    root = posixpath.normpath(os.environ["MSG_ROOT"].replace("\\", "/"))
    PROPOSAL_RE = re.compile(r'^docs/issue-[0-9]+/proposals/.*observability.*\.md$')
    ISSUE_RE = re.compile(r'issue-([0-9]+)')

    def resolve(p):
        n = p.replace("\\", "/")
        a = n if posixpath.isabs(n) else posixpath.join(root, n)
        a = posixpath.normpath(a)
        try:
            return posixpath.normpath(os.path.realpath(a).replace("\\", "/"))
        except OSError:
            return a

    # Only Write/Edit/MultiEdit reach the record in a form whose full
    # resulting content we can read. Everything else is out of this
    # gate's scope and passed through.
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
    if not PROPOSAL_RE.match(rel):
        sys.exit(0)  # not the phase-1 proposal surface — not this gate's business

    current = None
    if os.path.isfile(r):
        try:
            with open(r, encoding="utf-8-sig") as fh:
                current = fh.read(1 << 20)
        except OSError:
            deny("%s exists but cannot be read; failing closed on the produces-shape check." % rel)

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
            "from the tool input (tool=%r). Write the full proposal with Write, or use an "
            "Edit/MultiEdit whose old_string matches, so the methodology-selection shape can be checked." % (rel, tool)
        )

    low = new_text.lower()

    def has_any(*needles):
        return any(nd in low for nd in needles)

    missing = []
    if not has_any("red method", "use method", "golden signals", "golden signal",
                    "rate/errors/duration", "red (rate", "red(rate", " red/", "/red ",
                    "red 방법", "use 방법"):
        missing.append("signal-methodology-name (RED/USE/Golden Signals 중 하나를 명명해야 함)")
    if not has_any("request-driven", "request driven", "resource-bound", "resource bound",
                   "service-rollup", "service rollup", "요청 기반", "자원 기반", "서비스 롤업"):
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
