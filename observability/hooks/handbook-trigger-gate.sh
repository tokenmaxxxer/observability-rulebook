#!/usr/bin/env bash
__fc(){ rc=$?; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "fail-closed: gate aborted (rc=$rc)" >&2; exit 2; fi; }
trap __fc EXIT
# PreToolUse gate (Bash matching `git commit`) — contract v3 s21, handbook
# half. When a commit's staged file set introduces/changes an operational
# surface for observability, the same commit must also touch docs/handbooks/*.md.
# Skeleton: path heuristics for "operational surface" are a placeholder —
# harden per this role's actual write_scope ([])
# before treating as load-bearing; a report-only role with empty write_scope may not need this gate at all — reassess before shipping.
set -uo pipefail

case "${OBSERVABILITY_CYCLE_OFF:-}" in ""|0|false|no|off) ;; *) exit 0 ;; esac

deny() { echo "observability: refused — $*" >&2; exit 2; }

command -v python3 >/dev/null 2>&1 || deny "handbook-trigger-gate.sh requires python3, which is not on PATH; denying rather than guessing."
command -v git >/dev/null 2>&1 || deny "handbook-trigger-gate.sh requires git, which is not on PATH; denying rather than guessing."

exit 0  # placeholder verdict — TODO before this repo is treated as load-bearing
