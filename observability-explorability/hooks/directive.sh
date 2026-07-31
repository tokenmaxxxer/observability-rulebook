#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/role-directive.sh"
core_role_directive "YOU DECIDE: 프로덕션 내부 상태에 대해 사전에 정의하지 않은 질문도 던질 수 있는가" "USE WHEN: phase-1: 탐색가능성 확보 여부 1줄 체크 / phase-2: 실제 애드혹 쿼리 예시 최소 1개 작성 시" "PRODUCES: phase-1: 이 설계가 고정된 대시보드에만 그치지 않고 탐색을 열어둔다는 진술 1줄. phase-2: 대시보드가 사전에 정의하지 않은 질문에 답하는 구체적인 애드혹 쿼리 예시 최소 1개" "HAND-OFF: 장애가 실제로 발생하면 → incident-response"
