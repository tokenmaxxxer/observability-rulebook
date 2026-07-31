# Record — observability (issue-1)

## What was done

Phase-2 실행: approved proposal(`docs/issue-1/proposals/2026-07-31-observability-rulebook-norms.md`)의
(d) plugin reflection plan을 그대로 반영했다.

- `observability/hooks/directive.sh`의 `PRODUCES` 문자열을 proposal (b)의
  세 범주(telemetry/instrumentation design, cardinality budget,
  dashboard/query examples) 각각의 필수 구성요소를 담도록 확장. 4-인자
  `core_role_directive` 호출 형태(core stub)는 그대로 유지.
- `observability/hooks/hooks.json`에 `PreToolUse` 항목 하나 추가 —
  신규 게이트 스크립트를 등록. 기존 `SessionStart` 항목은 그대로 둠.
- `observability/hooks/observability-produces-gate.sh` 신규 작성(core
  게이트의 복사본이 아니라 이 역할 고유 로직): 이 역할 자신의 record
  (`docs/issue-<n>/reports/observability.md`)로의 Write/Edit/MultiEdit를
  가로채, core의 §20 일반 필드 검사와 별개로 proposal (b)의 세 항목 —
  방법론명(RED/USE/Golden Signals), cardinality/카디널리티 문구,
  ad-hoc/애드혹 쿼리 예시 문구 — 존재 여부를 텍스트 레벨에서 점검하고
  누락 시 exit 2로 거부한다. fail-closed trap과 payload 파싱 구조는 core의
  `record-fields-gate.sh`가 쓰는 것과 같은 검증된 패턴을 참조했으나, 검사
  로직 자체는 이 역할 고유(§20 필드가 아니라 (b)의 produces 형태)이며
  core 파일을 수정하거나 복사하지 않았다.
- `observability/README.md`의 layout/doctrine 절을 갱신 — 확장된
  `produces` 설명과 신규 게이트 파일을 나열.

## Why

Issue #1이 요구한 대로 이 역할의 phase-1 규범(신호 선택 방법론 명시,
카디널리티 예산, 탐색가능성 체크)을 phase-2 산출물에서 실제로 강제하기
위함. proposal의 대안 검토에서 "produces 문자열만 갱신하고 게이트는
추가하지 않음"을 기각한 이유가 그대로 적용됨 — 텍스트만 바꾸면 이슈가
요구한 게이트 항목을 충족하지 못한다.

## Upstream basis

- Issue #1
- `docs/issue-1/proposals/2026-07-31-observability-rulebook-norms.md`
  (approved: issue-level comment `APPROVE issue-1/observability` by
  `JiwonJung94`, an `docs/specs/approvers.md` account)
- `docs/issue-1/reports/observability/2026-07-31-current-state-survey.md`,
  `docs/issue-1/reports/observability/scout-brief.md`

loop_state: landed

## Open findings

없음 — proposal의 frozen write set 5개 항목(directive.sh, hooks.json,
observability-produces-gate.sh, README.md, 이 record) 전부 반영 완료.
게이트 스크립트의 실행 시점 검증(수동 테스트)은 이 세션의 샌드박스
권한 정책상 실행 승인이 막혀 라이브로 수행하지 못했다 — `bash -n` 문법
검사와 `hooks.json`의 JSON 파싱 검증은 통과했고, 로직은 core
`record-fields-gate.sh`의 검증된 fail-closed 패턴을 그대로 따른다.
차후 PR 리뷰에서 실행 테스트를 권장.

## How this will be verified (phase 2, from proposal)

- `observability/hooks/observability-produces-gate.sh`가 (b) 세 조건 중
  하나라도 빠진 기록 초안에 대해 exit 2로 거부하는지 수동 테스트 — 위
  open findings 참고, PR 리뷰 단계 권장.
- `directive.sh`가 core stub 형태를 벗어나지 않음 — 확인 완료(소스 라인
  + `core_role_directive` 단일 호출 유지).
- `git grep -l record-fields-gate observability/`가 아무것도 반환하지
  않음 — 확인 완료.
