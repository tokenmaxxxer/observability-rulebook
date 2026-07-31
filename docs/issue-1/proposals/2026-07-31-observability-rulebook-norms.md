# Proposal — observability 룰북 phase-1/phase-2 규범 확정

Subject: issue-1
Survey: docs/issue-1/reports/observability/2026-07-31-current-state-survey.md
Scout brief: docs/issue-1/reports/observability/scout-brief.md

## What was asked

Issue #1: 감이 아니라 도메인 조사에 근거해, (a) phase-1 제안서 규범, (b) phase-2
산출물 규범, (c) 각 채택의 논리적 근거, (d) 플러그인 반영 계획을 담은 proposal을
작성한다. Phase 1만 — proposal PR까지, APPROVE 없이 실행 작업(directive.sh 등
수정)은 하지 않는다.

## (a) Phase-1 proposal norms

이 역할의 phase-1 산출물(research/survey/proposal)이 지켜야 할 방법론·필수
섹션·근거 형식. contract v3 s19의 최소치(연구+서베이+제안, 절 체크리스트,
대안 1-2개, 실패 신호 1개)에 **더해**, observability 도메인 특유의 요구:

1. **신호 선택 방법론 명시** — 대상 표면이 요청 경로(request-driven)인지
   자원 바운드(resource-bound)인지 서비스 롤업 레벨인지를 먼저 분류하고,
   그에 맞는 방법론(RED / USE / Golden Signals)을 선택했다고 한 줄로
   진술한다. 방법론 선택 없이 임의 지표 나열은 phase-1 제안서로 불충분.
2. **카디널리티 예산 초안** — 제안 단계에서부터 어떤 차원(dimension)이
   고카디널리티가 될지 예비 목록을 든다(정확한 숫자는 phase-2 산출물에서
   확정). 예산을 phase-2로 통째로 미루는 제안은 불충분.
3. **탐색가능성 체크 1줄** — 이 설계가 사전에 정의하지 않은 질문에 답할 수
   있는 경로를 남기는지 1줄로 자체 진술(이 역할의 `decides` 문장과 직결).
4. s19의 절 체크리스트 형식(엔드투엔드로 phase-2가 각 절을 fulfill/dropped로
   마킹할 수 있게 한 줄씩)과 대안 1-2개 + 실패 신호 1개는 그대로 필수.

## (b) Phase-2 deliverable norms

`directive.sh`의 `produces` 세 범주(telemetry/instrumentation design,
cardinality budget, dashboard/query examples) 각각에 필수 구성요소를
부여한다.

1. **Telemetry/instrumentation design**
   - 대상 표면별 채택 방법론(RED/USE/Golden Signals 중 무엇을 왜)과, 그
     방법론이 요구하는 신호 각각(예: RED라면 rate/errors/duration 셋 다)의
     구체적 계측 지점.
   - 지표/스팬/속성 이름은 OpenTelemetry semantic conventions을 표준으로
     따른다 — 기존 컨벤션이 있는 이름공간은 그것을 쓰고, 새 이름을 만들
     때는 semconv 네이밍 패턴(예: `service.*`, `http.*` 식 네임스페이스,
     스네이크/도트 표기)을 따른다고 명시.
2. **Cardinality budget**
   - 고카디널리티가 될 차원의 명시적 목록(예: user_id, request_id 등)과
     각각을 태그로 유지할지/샘플링·집계할지/구조화 로그로 내릴지 결정.
   - 예산의 형태는 숫자든 정성적 등급(낮음/중간/높음 + 대응 조치)이든
     무방하나, "예산 없음"은 phase-2 산출물로 불충분 — 스카우트 근거:
     카디널리티 관리가 관측가능성 엔지니어링 팀 작업시간의 "대다수"를
     차지한다는 업계 관찰(Majors).
3. **Dashboard/query examples**
   - 최소 하나는 사전에 정의된 질문(대시보드 패널)이 아니라, 이 설계로
     처음 보는 질문에 답할 수 있음을 보이는 애드혹 쿼리 예시여야 한다
     (탐색가능성 체크의 산출물 증거).

## (c) Adoption rationale — why these and not others

- **RED/USE/Golden Signals as the required signal-selection method.**
  세 방법론 모두 "무엇을 계측할지"를 팀마다 임의로 정하던 문제에 대한
  업계 수렴 답이며(스카우트 4개 각도 전부 동일 삼각형에 수렴), 서로
  다른 표면(요청 경로 vs 자원 vs 서비스 레벨)을 커버해 하나만 강제하면
  나머지 표면에서 오적용된다 — RED는 "어느 자원이 병목인가"에 답하지
  못하고 USE는 "요청이 무엇을 겪는가"에 답하지 못한다는 것이 스카우트로
  확인된 명시적 실패 모드. 그래서 하나를 못박지 않고 "표면별로 맞는 것을
  선택하고 왜인지 진술"을 강제한다 — 이것이 이 역할의 `decides` 문장
  ("사전에 정의하지 않은 질문도 던질 수 있는가")과 직접 연결되는 지점:
  잘못된 방법론 선택은 그 표면에 대해 물을 수 있는 질문의 종류 자체를
  제한한다.
- **OpenTelemetry semantic conventions as the naming standard.** 벤더
  중립 표준이자, 스카우트 결과 "일관 안 된 네이밍이 교차 서비스 상관을
  깨기 때문에" 업계가 수렴한 답으로 확인됨 — 룰북이 자체 네이밍 규칙을
  발명하는 대신 기존 표준을 참조하는 것이 이 역할의 산출물이 다른
  서비스/팀과 상관 가능하게 만드는 유일한 방법.
- **Explicit cardinality budget as a required component.** 관측가능성
  비용·성능 문제의 최대 원인이 카디널리티 관리 실패라는 것이 스카우트로
  수렴 확인됨(Majors) — "산출물에 계측 설계는 있는데 카디널리티 예산이
  없다"는 상태가 이 도메인에서 실무적으로 반복되는 실패 형태이므로,
  누락 시 phase-2 산출물이 불완전하다고 못박는다.
- **Explorability check as the acceptance criterion.** 이 역할이 존재하는
  이유(`decides` 문장) 자체가 "사전에 정의하지 않은 질문"이다 — 대시보드
  패널만 있고 애드혹 쿼리 경로가 없는 산출물은 이 역할의 존재 이유를
  충족하지 못한다는 것이 논리적으로 직결된다(스카우트 축 3 "explorability
  vs dashboard-only"와 이 역할 doctrine의 정확한 일치).
- **왜 "observability 2.0" 전체 아키텍처(단일 wide-event 스토어)는
  채택하지 않는가.** 이것은 인프라/벤더/스토리지 선택이며, 이 역할이
  손대는 표면(`write_scope: []`, 설계·budget·예시 산출물)을 벗어난다 —
  룰북은 무엇을 설계·점검할지를 강제하지, 어떤 백엔드를 쓸지는 강제하지
  않는다.
- **왜 SLO burn-rate 알림 정책은 채택하지 않는가.** 실재하는 관행이지만
  이 역할의 hand-off("장애가 실제로 발생하면 → incident-response")가
  이미 런타임/알림 결정을 다른 역할로 라우팅하고 있어, 이 룰북이 그
  경계를 넘어서면 역할 간 책임이 겹친다.

## (d) Plugin reflection plan

Frozen write set for phase 2 (files this proposal's execution touches —
no other file):

- `observability/hooks/directive.sh` — `produces` 문자열을 (b)의 세
  범주와 방법론 선택 요구를 반영하도록 갱신(문구 확장, 4-인자
  `core_role_directive` 호출 형태는 유지 — core stub 형태를 벗어나지
  않는다).
- `observability/hooks/hooks.json` — `PreToolUse` 항목 하나 추가:
  새로 작성하는 role-owned 게이트 스크립트(아래) 등록. 기존 `SessionStart`
  항목은 그대로 둔다.
- `observability/hooks/observability-produces-gate.sh` — **신규 파일**
  (core canon 게이트의 복사본이 아니라, 이 역할 고유 로직만 담는 새
  스크립트). `docs/issue-<n>/reports/observability.md`로의
  Write/Edit/MultiEdit를 가로채, core의 §20 일반 필드 검사와 별개로
  (b)의 phase-2 필수 구성요소를 텍스트 레벨에서 점검한다:
  - 채택 방법론명(RED/USE/Golden Signals 중 최소 하나) 언급 여부
  - "cardinality" 또는 "카디널리티" 및 budget/예산 관련 문구 존재 여부
  - 애드혹/탐색 쿼리 예시임을 나타내는 문구(예: "ad-hoc", "탐색", 또는
    쿼리 예시 블록) 존재 여부
  누락 시 exit 2로 거부, 이유를 stderr에 명시(core의 fail-closed 패턴을
  따름 — core 파일을 수정하지 않고 이 역할 고유 훅으로 신규 작성).
  이 게이트는 issue-2가 삭제한 옛 `record-fields-gate.sh` 복사본의
  부활이 아니다 — 그것은 core가 이제 담당하는 role-agnostic §20 체크였고,
  이것은 이 역할만의 (b) 산출물-형태 체크다.
- `docs/issue-1/reports/observability.md` — phase-2 record (Approve
  이후에만 작성; 이번 phase-1 커밋 범위 아님).
- `observability/README.md` — layout/doctrine 절 갱신, 신규 게이트 파일
  나열.

Out of scope for phase 2 execution: `core/` 어떤 파일도 수정하지 않는다
(core canon은 참조만); `warrant-hunter` 관련 어떤 파일도 되살리지 않는다
(issue-2 삭제 유지).

## Write set (frozen for phase 2)

- `observability/hooks/directive.sh` — edit (produces string)
- `observability/hooks/hooks.json` — edit (add one PreToolUse entry)
- `observability/hooks/observability-produces-gate.sh` — new
- `observability/README.md` — edit
- `docs/issue-1/reports/observability.md` — new (phase-2 record only)

## Alternatives considered

1. **core canon에 role-specific `REQUIRED_FIELDS` 메커니즘 추가를
   요청하고 그것에 의존.** 기각 이유: issue-2 서베이가 이미 이 질문을
   core에 플래그했지만 미해결 상태이며, 이 역할의 phase-1이 업스트림
   core 결정을 기다리게 만드는 것은 불필요한 블로킹 — role-owned 게이트로
   자체 해결 가능한 문제를 core 의존으로 만들 이유가 없다.
2. **`produces` 문자열만 갱신하고 게이트는 추가하지 않음(텍스트로만
   강제).** 기각 이유: `directive.sh`의 `produces`는 현재도 순수
   안내문이며 아무것도 기계적으로 검사하지 않는다(서베이에서 확인) —
   텍스트만 바꾸면 이슈가 요구한 "게이트" 항목((d)의 필수 항목)을
   충족하지 못한다.

## Failure signal

이 제안이 잘못됐다는 신호: phase-2에서 이 역할이 실제로 작성하는
telemetry/instrumentation design 문서가 매번 방법론 선택·카디널리티
예산·애드혹 쿼리 예시 중 하나 이상을 게이트 통과를 위해 형식적으로만
채워 넣고(예: "cardinality: N/A" 같은 무의미한 placeholder), 다음 라운드
리뷰나 실제 사용에서 그 설계가 사전에 정의하지 않은 질문에 답하지
못한다는 불만이 반복되면 — 이는 이 규범이 형태만 강제하고 실질을
끌어내지 못한다는 신호이며, 게이트 조건을 문구 매칭에서 더 구체적인
검사로 강화하거나 규범 자체를 재검토해야 한다.

## How this will be verified (phase 2)

- `observability/hooks/observability-produces-gate.sh`가 (b) 세 조건 중
  하나라도 빠진 기록 초안에 대해 exit 2로 거부하는지 수동 테스트.
- `directive.sh`가 여전히 core stub 형태(소스 라인 + `core_role_directive`
  단일 호출)를 벗어나지 않는지 확인.
- `git grep -l record-fields-gate observability/`가 아무것도 반환하지
  않는지(core 게이트 복사 안 함) 확인.

## Explicitly out of scope for this batch

- SLO/error-budget burn-rate 알림 정책 수립 — incident-response 영역.
- 특정 관측가능성 백엔드/벤더 선택 — 인프라 결정, 이 룰북 범위 밖.
- core canon 파일 수정 — 참조만, 복사·수정 금지(이슈 제약 그대로).
