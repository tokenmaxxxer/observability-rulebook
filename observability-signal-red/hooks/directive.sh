#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/role-directive.sh" || { echo "directive.sh: cannot source role-directive.sh" >&2; exit 2; }
core_role_directive "YOU DECIDE: request-driven 표면에 RED(Rate/Errors/Duration) 3신호 계측을 어디에 배치할 것인가" "USE WHEN: phase-1이 이 표면에 RED를 선택했을 때, phase-2 산출물 작성 시점" "PRODUCES: phase-2 record/proposal 본문에 RED 3신호 각각을 명시적으로 이름 붙이고 각 신호별 구체적 계측 지점을 진술 (rate: 어떤 카운터를 어디에 둘 것인지, errors: 어떤 에러 분류 기준을 쓸 것인지, duration: 어떤 히스토그램/퍼센타일을 쓸 것인지)" "HAND-OFF: 장애가 실제로 발생하면 → incident-response"
