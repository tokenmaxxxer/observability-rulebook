# Proposal — observability 방법론을 훅 머신으로 강제 (issue-1 규범의 심화)

Subject: issue-7
Survey: docs/issue-7/reports/observability/2026-07-31-current-state-survey.md
Scout brief: docs/issue-7/reports/observability/scout-brief.md

## What was asked

Issue #7: issue-1에서 채택된 방법론(RED/USE/Golden Signals 선택,
cardinality budget, ad-hoc 탐색가능성)이 현재 `directive.sh`의 요약
문자열과 `docs/issue-1/proposals/...norms.md` 문서로만 존재하는데,
이를 implementation-rulebook 수준의 훅 머신으로 기계적으로 강제한다:
(1) directive 심화, (2) 방법론 게이트를 phase-1 산출물 필수 요소까지
기계 검증, 필요 시 순서 제약 상태 추적, (3) 게이트 테스트, (4) 필요
시 agents/체크리스트. 캐논 참조만·복사 금지. Phase 1만 — 이 proposal
PR까지, APPROVE 금지.

## (1) Directive depth — per-facet stages/criteria/prohibitions

`observability/hooks/directive.sh`의 `USE_WHEN`과 `PRODUCES`를, 각각
phase-1/phase-2로 나눈 라벨 하위섹션 + 불릿 규칙 형태로 재작성한다
(`core_role_directive` 4-인자 호출 형태·소스 라인은 그대로 — core
stub 형태를 벗어나지 않는다. `implementation-rulebook/coding/hooks/
directive.sh`의 구조를 참조했으나 문구는 이 역할 고유로 새로 쓴다).

**`YOU_DECIDE`** — 현행 한 줄 유지(`decides` 문장은 plugin.json과
일치해야 하며 변경 대상 아님).

**`USE_WHEN`** — 두 라벨 하위섹션:
- `PHASE 1 (research/survey/proposal)`: 대상 표면을 request-driven /
  resource-bound / service-rollup 중 분류 → 그에 맞는 방법론(RED/USE/
  Golden Signals) 선택을 한 줄로 진술 → 고카디널리티 후보 차원 예비
  목록 → 탐색가능성 체크 1줄. 방법론 선택 없이 지표만 나열하는 제안은
  불충분하다고 명시.
- `PHASE 2 (deliverable)`: phase-1이 선택한 방법론을 그대로 이어받아
  신호별 구체 계측 지점을 확정하고, 예비 카디널리티 목록을 처리 방침
  (태그 유지/샘플링·집계/구조화 로그)까지 확정하며, 최소 하나의 애드혹
  쿼리 예시를 작성한다. phase-1에서 선택하지 않은 방법론으로 phase-2가
  이탈하면 그 이유를 진술해야 한다(아래 상태 추적이 강제).

**`PRODUCES`** — 불릿 규칙, 각각 근거 딸림:
- `SIGNAL-SELECTION RULE`: 표면당 RED/USE/Golden Signals 중 하나를
  명명하고 그 표면 분류(요청/자원/롤업)와 연결해 왜인지 진술. 방법론
  미명명은 phase-1/phase-2 모두 불충분.
- `NAMING RULE`: OpenTelemetry semantic conventions을 표준으로 — 기존
  네임스페이스 재사용, 신규 시 semconv 패턴(`service.*`, `http.*` 등)
  준수를 진술.
- `CARDINALITY RULE`: 고카디널리티 차원의 명시적 목록과 각각의 처리
  방침. "budget: N/A" 류 무의미한 placeholder는 이 게이트를 형식상
  통과해도 실질 위반으로 취급(issue-1 proposal의 failure signal과
  동일 기준, 여기서 처음으로 게이트 로직에 반영 — 문구 매칭에 더해
  플레이스홀더 패턴 자체를 거부).
- `EXPLORABILITY RULE`: 최소 하나의 애드혹 쿼리 예시가 사전에 정의되지
  않은 질문에 답한다는 것을 보여야 함(대시보드 패널 나열만으로는 불충분).
- `PHASE TRACE RULE`: phase-2 record의 채택 방법론은 phase-1 proposal이
  명명한 방법론과 일치하거나, 불일치 시 이탈 이유를 진술해야 한다 —
  아래 (2)의 상태 추적이 기계적으로 이 정합성을 확인한다.

**`HAND_OFF`** — 현행 유지, 문구만 명확화(phase-2 record 갱신 시점
= 발견 즉시, contract v3 s19 관례와 동일).

## (2) Methodology gate — 표면 확장 + placeholder 거부 + phase-trace 상태 추적

세 가지 변경, 하나의 role-owned 스크립트로 (신규 core 파일 없음, 기존
`observability-produces-gate.sh`를 확장):

### (2a) 표면 확장: phase-1 proposal도 검사

`RECORD_RE`(현재 record만 매칭) 옆에 `PROPOSAL_RE =
r'^docs/issue-[0-9]+/proposals/.*observability.*\.md$'`를 추가한다
(pricing-rulebook의 `methodology-gate.sh` 구조를 참조 — 코드 복사가
아니라 정규식 두 개 병렬 매칭이라는 구조만 채택, 문구·변수명은 이
역할 고유로 새로 작성). 검사 항목은 phase별로 다르게:
- **Phase-1 (proposal)**: (i) 방법론명 언급, (ii) 카디널리티 관련
  문구("cardinality"/"카디널리티") 존재, (iii) 탐색가능성 문구
  ("탐색가능"/"explorability"/"ad-hoc"류) 존재. issue-1 (a) 규범의
  경량 3항목 — phase-1은 초안이므로 phase-2보다 느슨하다.
- **Phase-2 (record)**: 기존 3항목 그대로 유지 + 신규
  **placeholder-rejection**: cardinality 문구가 있어도 그 주변 텍스트가
  `N/A`, `해당 없음`, `없음`, `TBD` 류 패턴과 바로 인접(같은 줄 또는
  다음 줄)하면 "형식만 채운 placeholder"로 판정해 거부(issue-1
  proposal의 failure signal을 최초로 게이트 로직화).

### (2b) Phase-trace 상태 추적

방법론 순서 제약("조사→근거→채택")을 이 역할에 맞게 해석하면: **phase-1
proposal이 명명한 방법론이 phase-2 record의 채택 방법론과 다르면, 그
이탈 이유가 phase-2 record에 있어야 한다.** 상태는 게이트 자신이
쓴다(에이전트가 직접 쓰지 않음 — hunt-state.sh 패턴의 "게이트가 상태를
관리, 에이전트는 관여 안 함" 원칙만 채택, lock/count 메커니즘 자체는
채택하지 않는다 — 스카우트 브리프 axis 2: 이 역할의 순서 제약은
동시성 바운딩이 아니라 문서 간 정합성 트레이스이므로 다른 메커니즘이
필요).

- phase-1 proposal 쓰기가 게이트를 통과하면, 게이트가
  `.observability-phase1-methods/<issue-n>.json`에 그 proposal이
  명명한 방법론 집합(예: `["RED"]`, 표면이 여럿이면 여러 개)을 기록.
  role-owned 상태 파일이며 `.gitignore` 대상(세션 로컬, 커밋 대상
  아님 — hunt-hunt-*.lock/.count가 그런 것처럼).
- phase-2 record 쓰기가 게이트를 통과할 때, 같은 issue-n의 상태 파일이
  있으면 phase-2 텍스트에서 언급된 방법론 집합과 비교. 상태 파일에
  없는 새 방법론이 phase-2에 나타나고 "이탈"/"deviat"/"switch" 류
  이유 진술 문구가 없으면 거부. 상태 파일이 아예 없으면(예: phase-1이
  이 게이트 도입 이전에 쓰였거나 세션이 초기화됨) **정보용 stderr
  경고만 출력, 거부하지 않음** — fail-closed는 "판단 불가능한 입력"에
  적용하는 것이지 "phase-1 상태가 없다"는 이 역할 밖 사건에까지
  적용하면 과잉 차단이 된다(이 점은 core의 fail-closed 원칙과 다른
  판단이므로 근거를 명시: 상태 파일 부재는 파싱 실패가 아니라 정당한
  선행 사건 부재).

## (3) Gate tests

레포 루트에 `tests/observability-produces-gate.test.sh` 신규(레포 첫
`tests/` 디렉터리). implementation-rulebook의 3-스크립트 구성은 이
레포의 게이트 1개(표면 2개) 규모에 과합(스카우트 브리프 axis 3) —
대신 이름 붙은 pass/fail 케이스를 도는 단일 스크립트:

- PASS: phase-1 proposal에 방법론명+카디널리티+탐색가능성 문구 모두
  존재 → exit 0.
- FAIL: phase-1 proposal에서 방법론명 누락 → exit 2, stderr에 이유.
- PASS: phase-2 record에 6항목(기존 3 + placeholder-rejection 통과)
  모두 충족 → exit 0.
- FAIL: phase-2 record의 cardinality 문구가 "N/A"에 바로 인접 →
  exit 2 (placeholder-rejection).
- FAIL: phase-2 record가 phase-1 상태 파일에 없는 방법론을 이탈
  이유 없이 채택 → exit 2 (phase-trace).
- PASS: phase-1 상태 파일이 없을 때 phase-2가 통과(경고만) → exit 0.
- PASS: 게이트가 무관한 파일(예: `src/foo.py`) 쓰기에는 관여하지
  않음 → exit 0.
- FAIL: 손상된 JSON payload(빈 stdin, 파싱 불가) → exit 2
  (fail-closed).

각 케이스는 gate 스크립트에 합성 PreToolUse JSON payload를 stdin으로
주입해 실행하고 exit code + stderr 문구를 assert하는 방식
(implementation-rulebook의 `parse-check.sh` 구조를 참조하되 이 레포용
으로 새로 작성 — 코드 복사 없음).

## (4) Agents/checklist — 채택하지 않음, 이유 명시

스카우트·서베이 결과: 이 역할의 방법론 채택은 이슈당 1회의 판단
(phase-1에서 선택, phase-2에서 확정)이며, `warrant-hunter`의 hunt
cadence처럼 세션 중 반복 디스패치되는 절차가 아니다. 존재하지 않는
반복을 위해 체크리스트 에이전트를 만드는 것은 이슈의 "필요 시" 조건을
충족하지 않는다 — 이 결정 자체를 이 proposal의 명시적 출력으로 남긴다
(추후 이 역할의 워크플로가 실제로 반복 절차를 갖게 되면 재검토 대상).

## Write set (frozen for phase 2)

- `observability/hooks/directive.sh` — edit (USE_WHEN/PRODUCES 심화,
  core stub 형태 유지)
- `observability/hooks/observability-produces-gate.sh` — edit (proposal
  표면 매칭 추가, placeholder-rejection, phase-trace 상태 읽기/쓰기)
- `.gitignore` — edit (신규: `.observability-phase1-methods/` 항목 추가,
  없으면 파일 신규 생성)
- `tests/observability-produces-gate.test.sh` — new
- `observability/README.md` — edit (게이트 표면 확장·테스트 위치 반영)
- `docs/issue-7/reports/observability.md` — phase-2 record (Approve
  이후에만 작성; 이번 phase-1 커밋 범위 아님)

Out of scope for phase 2 execution: `core/` 어떤 파일도 수정하지 않는다
(참조만); `agents/`·체크리스트 신규 작성 안 함(위 (4) 참조); SLO/알림
정책·백엔드 선택(issue-1 proposal의 기존 out-of-scope 유지).

## Alternatives considered

1. **phase-trace를 상태 파일 대신 텍스트 매칭만으로 근사** (phase-2
   record에 phase-1 proposal 파일을 그대로 인용하라고 요구). 기각
   이유: 텍스트 인용 요구는 우회하기 쉽고(그냥 문자열 붙여넣기로 통과
   가능), 실제 방법론 *일치 여부*를 검증하지 못한다 — 상태 파일은
   게이트 자신이 phase-1 통과 시점에 기록하므로 위조 불가능한 근거가
   된다.
2. **implementation-rulebook의 lock/count 동시성 바운딩 메커니즘을
   그대로 이식**. 기각 이유: 스카우트 axis 2에서 확인했듯 이 역할의
   순서 제약은 동시 디스패치 바운딩 문제가 아니라 문서 간 정합성
   문제 — 다른 문제에 맞춘 메커니즘을 이식하면 불필요한 복잡도만
   추가된다.
3. **3-스크립트 테스트 하니스를 그대로 이식**. 기각 이유: 스카우트
   axis 3 — 이 레포는 게이트 1개(표면 2개)뿐이라 단일 스크립트로
   충분, 3-스크립트는 이 규모에 과설계.

## Failure signal

이 제안이 잘못됐다는 신호: (a) phase-trace 상태 파일이 세션 재시작·
worktree 전환 등으로 자주 유실되어 "정보용 경고"가 사실상 상시
무음화되고 phase-1/phase-2 방법론 불일치가 실제로 반복 발생하거나,
(b) placeholder-rejection 패턴 매칭이 실제 유효한 카디널리티 서술을
오탐 거부하는 사례가 반복되면 — 상태 추적 메커니즘 자체를 재검토
(예: 상태를 세션 로컬 파일 대신 git-committed 파일로 옮기는 것 검토)
하거나 placeholder 패턴 목록을 좁혀야 한다는 신호.

## How this will be verified (phase 2)

- `tests/observability-produces-gate.test.sh`의 8개 케이스 전부 통과.
- `directive.sh`가 core stub 형태(소스 라인 + `core_role_directive`
  단일 호출)를 벗어나지 않는지 확인.
- `git grep -l record-fields-gate observability/`가 아무것도 반환하지
  않는지(core 게이트 복사 안 함) 확인.
- 수동: phase-1 proposal → phase-2 record 순으로 실제 파일을 써서
  phase-trace 상태 파일이 생성·소비되는지 확인.

## Explicitly out of scope for this batch

- SLO/error-budget burn-rate 알림 정책, 특정 관측가능성 백엔드/벤더
  선택 — issue-1 proposal과 동일 이유로 범위 밖.
- `core/` 파일 수정 — 참조만, 복사·수정 금지.
- `agents/`·체크리스트 신규 작성 — 위 (4) 이유로 비채택.
- phase-1 상태 파일을 git에 커밋하는 방식으로 바꾸는 것 — 세션 로컬
  파일로 충분하다는 판단(위 실패 신호가 뒤집히면 재검토).
