#!/usr/bin/env bash
# SessionStart: observability's role directive — how this role fills the core
# lifecycle. Kill switch: export OBSERVABILITY_CYCLE_OFF=1
trap 'rc=$?; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then exit 2; fi' EXIT
set -uo pipefail

case "${OBSERVABILITY_CYCLE_OFF:-}" in ""|0|false|no|off) ;; *) trap - EXIT; exit 0 ;; esac
[ "${CLAUDE_ROLE:-}" = "observability" ] || { trap - EXIT; exit 0; }

cat <<'DIRECTIVE'
[observability] Role directive (on top of core's protocol):

YOU DECIDE: 프로덕션 내부 상태에 대해 사전에 정의하지 않은 질문도 던질 수 있는가

USE_WHEN: 신규 서비스/경로에 계측이 필요할 때

PRODUCES (required record fields): telemetry/instrumentation design, cardinality budget, dashboard/query examples

WRITE_SCOPE: [] (report-only role — no code/doc write outside the record itself)

HAND-OFF: 장애가 실제로 발생하면 → incident-response

BOUNDARY CASE: if the work in front of you drifts outside `decides` above,
stop and hand off per the arrow — do not silently absorb another role's
scope. Record the hand-off point in this role's record before opening the
next role's session.

RECORD: docs/issue-<n>/reports/observability.md, phase-gated per contract v3 s19
(phase-1 homes only pre-Approve; this record is phase-2 output).
DIRECTIVE
