#!/usr/bin/env bash
__fc(){ rc=$?; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "fail-closed: gate aborted (rc=$rc)" >&2; exit 2; fi; }
trap __fc EXIT
# PreToolUse hook (Bash matching `git commit`): enforces contract v3's
# commit-trailer requirement — a commit staging docs/issue-<n>/** must carry
# `Subject: issue-<n>`, one subject per commit. Adapted from
# implementation-rulebook's trailer-gate.sh, role name substituted only
# (this file's logic is role-agnostic).
set -uo pipefail

case "${OBSERVABILITY_CYCLE_OFF:-}" in ""|0|false|no|off) ;; *) exit 0 ;; esac

deny() { echo "observability: refused — $1" >&2; exit 2; }

command -v python3 >/dev/null 2>&1 || deny "trailer-gate: python3 is required to evaluate the gate and is not on PATH."

payload="$(cat 2>/dev/null)"
[ -n "$payload" ] || exit 0

OBSERVABILITY_PAYLOAD="$payload" python3 <<'PY'
import json, os, re, sys

def deny(msg):
    sys.stderr.write("observability: refused — %s\n" % msg)
    sys.exit(2)

payload = os.environ.get("OBSERVABILITY_PAYLOAD", "")
try:
    event = json.loads(payload)
except Exception:
    sys.exit(0)

cmd = ((event.get("tool_input") or {}).get("command") or "") if isinstance(event, dict) else ""
if "git commit" not in cmd:
    sys.exit(0)

m = re.search(r"-m\s+'((?:[^'\\]|\\.)*)'", cmd) or re.search(r'-m\s+"((?:[^"\\]|\\.)*)"', cmd)
msg = m.group(1) if m else ""
subjects = set(re.findall(r"docs/issue-(\d+)/", cmd))
if not subjects:
    sys.exit(0)
if len(subjects) > 1:
    deny("commit stages more than one issue tree: " + ", ".join(sorted(subjects)))
n = next(iter(subjects))
if not re.search(r"(?m)^Subject:\s*issue-%s\s*$" % re.escape(n), msg):
    deny("commit touches docs/issue-%s/** but message lacks 'Subject: issue-%s' trailer" % (n, n))
sys.exit(0)
PY
