#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/role-directive.sh"
core_role_directive "YOU DECIDE: 프로덕션 내부 상태에 대해 사전에 정의하지 않은 질문도 던질 수 있는가" "USE WHEN: 신규 서비스/경로에 계측이 필요할 때" "PRODUCES: telemetry/instrumentation design, cardinality budget, dashboard/query examples" "HAND-OFF: 장애가 실제로 발생하면 → incident-response"
