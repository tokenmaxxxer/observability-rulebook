#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/role-directive.sh"
core_role_directive "YOU DECIDE: phase-2가 채택한 방법론이 phase-1이 명명한 방법론과 정합한가" "USE WHEN: phase-2 산출물(record) 작성 시, phase-1에서 방법론이 이미 명명되어 있는 경우" "PRODUCES: HAND-OFF timing만 다룸: phase-1 상태가 존재하면 phase-2는 그 방법론을 그대로 쓰거나, 이탈 시 이탈 이유를 명시적으로 진술해야 한다 — 이 플러그인 자체는 신호/카디널리티 규범을 갖지 않는다" "HAND-OFF: 장애가 실제로 발생하면 → incident-response"
