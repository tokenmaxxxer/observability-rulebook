#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/role-directive.sh" || { echo "directive.sh: cannot source role-directive.sh" >&2; exit 2; }
core_role_directive "YOU DECIDE: service-rollup 표면에 Golden Signals(Latency/Traffic/Errors/Saturation) 4신호 계측을 어디에 배치할 것인가" "USE WHEN: phase-1이 이 표면에 Golden Signals를 선택했을 때, phase-2 산출물 작성 시점" "PRODUCES: phase-2 record/proposal이 Golden Signals 4신호(latency/traffic/errors/saturation) 모두를 명시적으로 이름 붙이고, 각 신호별 구체적 계측 지점을 진술해야 함" "HAND-OFF: 장애가 실제로 발생하면 → incident-response"
