# Proposal — observability 방법론을 플러그인 세트로 체계화 (issue-1 규범의 심화, REVISED)

Subject: issue-7
Survey: docs/issue-7/reports/observability/2026-07-31-current-state-survey.md
Scout brief: docs/issue-7/reports/observability/scout-brief.md

## Revision note (rework of PR #8)

승인자 FEEDBACK (issue #7 코멘트, "요구 정정"):

> 단일 게이트/디렉티브 심화가 아니라 **플러그인 세트**로 체계화한다:
> - 채택 방법론 각각을 **독립 플러그인**으로 (core의 freelunch/scout처럼
>   — 룰북당 여러 개, freelunch 수준의 완성도).
> - **기획서(phase 1) 규범**과 **산출물(phase 2) 규범**도 각각을 플러그인
>   조합으로 풀어낸다 — 어떤 플러그인들이 조합되어 그 규범이 성립하는지가
>   설계의 본체.
> - 각 플러그인 = 자기 완결(디렉티브/게이트/에이전트/테스트 포함 가능),
>   marketplace.json 등록, 명확한 단일 방법론 담당.
> - proposal에는 플러그인 목록(이름·담당 방법론·구성요소·조합 관계)이 필수.

이전 버전(PR #8 최초본)은 기존 단일 `observability` 플러그인 내부에서
`directive.sh`를 심화하고 `observability-produces-gate.sh` 하나를
확장하는 안이었다 — 승인자는 이 구조 자체를 기각했다. 본 리비전은 그
안을 폐기하고, 방법론별 독립 플러그인 + 조합으로 표현되는 phase 규범
구조로 다시 설계한다. 아래는 전면 재작성이며, phase-1(proposal) 범위
그대로 유지 — 실행/구현 코드 없음, APPROVE 없음.

## What was asked (issue-7, 원문 그대로)

Issue #7: issue-1에서 채택된 방법론(RED/USE/Golden Signals 선택,
cardinality budget, ad-hoc 탐색가능성)이 현재 `directive.sh`의 요약
문자열과 `docs/issue-1/proposals/...norms.md` 문서로만 존재하는데,
이를 implementation-rulebook 수준의 훅 머신으로 기계적으로 강제한다.
승인자 정정 이후: 이 강제를 단일 플러그인 심화가 아니라 **플러그인
세트**로 구현한다. 캐논 참조만·복사 금지. Phase 1만 — 이 proposal PR
까지, APPROVE 금지.

## Design summary

기존 `observability` 플러그인 하나에 모든 규범을 욱여넣는 대신, **담당
영역이 좁고 자기 완결적인 플러그인 여러 개**로 쪼갠다. 각 플러그인은
`freelunch`/`scout`(core canon)와 동일한 완성도 기준을 만족해야 한다:
자기 소유의 `plugin.json`, `hooks/directive.sh`(core stub 형태 유지),
필요한 게이트, 필요한 경우의 테스트, marketplace.json 개별 등록. 어느
플러그인도 두 개 이상의 방법론을 동시에 담당하지 않는다.

phase-1(기획서) 규범과 phase-2(산출물) 규범은 그 자체로 플러그인이
아니라, **어떤 플러그인들이 함께 설치되어야 그 규범이 성립하는지**로
정의된다 — 즉 "phase-1 규범" = {methodology-selector, cardinality-
budget, explorability} 세 플러그인의 phase-1 체크 조합이고, "phase-2
규범" = 위 셋의 phase-2 체크 + 채택된 신호 방법론 플러그인(RED/USE/
Golden Signals 중 phase-1이 고른 것) + phase-trace 플러그인의 조합이다.
아래 "Plugin list"가 이 조합 관계를 표로 명시한다.

## Freelunch-completeness (freelunch 수준의 완성도)

승인자가 명시한 기준선은 core의 `freelunch` 플러그인이다. 이 proposal이
채택하는 완성도 정의(스카우트 브리프의 must-be 목록과 일치시킴):

- 플러그인마다 자기 소유 `<plugin>/.claude-plugin/plugin.json` +
  `<plugin>/hooks/hooks.json` + `<plugin>/hooks/directive.sh`(core stub
  형태: 소스 라인 + `core_role_directive` 단일 호출).
- 담당 게이트가 있는 플러그인은 fail-closed 트랩-at-top + 킬스위치
  (`<PLUGIN>_..._OFF`) 문서화, 스카우트 브리프가 확인한 이 레포 기존
  게이트 패턴과 동일 형태 유지.
- 반복 디스패치 절차가 실제로 존재하는 플러그인만 `agents/`를 갖는다
  (freelunch/scout에 에이전트가 있는 이유가 그것이므로) — 아래 plugin
  list에서 각 플러그인별로 "에이전트 있음/없음 + 이유"를 명시한다.
  이 역할은 방법론 채택이 이슈당 1회 판단이라는 스카우트 브리프의
  기존 결론을 유지하되, 그 결론을 *역할 전체*가 아니라 *플러그인
  단위*로 다시 적용한다 (아래 참조).
- 게이트가 있는 플러그인은 `tests/<plugin>-gate.test.sh`를 자기 레포
  루트 `tests/`에 갖는다(스카우트 브리프의 "단일 스크립트, named
  pass/fail" 결론은 유지 — 플러그인이 여러 개로 쪼개져도 게이트 하나당
  테스트 스크립트 하나면 충분한 규모).
- `.claude-plugin/marketplace.json`에 플러그인마다 별도 엔트리
  (`name`/`source`/`description`), 기존 단일 엔트리 방식에서 다중
  엔트리 방식으로 전환.

## Plugin list (required section)

담당 표면 분류 축(request-driven / resource-bound / service-rollup)은
issue-1 norms 문서에서 그대로 가져온 것이고 여기서 새로 발명하지 않는다.

| # | Plugin name | 담당 방법론 (단일) | 구성요소 | Phase 조합에서의 역할 |
|---|---|---|---|---|
| 1 | `observability-signal-red` | RED (Rate/Errors/Duration) — request-driven 표면 전용 | `plugin.json`, `hooks/directive.sh`(USE_WHEN: request-driven 판별 기준만, PRODUCES: RED 3신호별 계측 지점 규칙), `hooks/signal-red-gate.sh`(phase-2 전용, RED 3신호 모두 언급 확인), `tests/signal-red-gate.test.sh`. 에이전트 없음 — 표면당 1회 판단, 반복 디스패치 없음(스카우트 브리프 결론 상속). | phase-2 조합원. phase-1이 이 표면에 RED를 선택했을 때만 phase-2 조합에 들어옴(선택적 조합원). |
| 2 | `observability-signal-use` | USE (Utilization/Saturation/Errors) — resource-bound 표면 전용 | 위와 동일 구조, USE 3신호 기준으로 교체. 에이전트 없음(동일 이유). | phase-2 조합원(선택적, resource-bound 표면 선택 시). |
| 3 | `observability-signal-golden` | Golden Signals (Latency/Traffic/Errors/Saturation) — service-rollup 표면 전용 | 위와 동일 구조, Golden 4신호 기준. 에이전트 없음(동일 이유). | phase-2 조합원(선택적, service-rollup 표면 선택 시). |
| 4 | `observability-methodology-selector` | 방법론 *선택 절차* 자체(표면 분류 → RED/USE/Golden 중 지정) — 세 신호 방법론 어느 것도 이 플러그인 안에서 구현하지 않음, "선택했다는 사실"만 검증 | `plugin.json`, `hooks/directive.sh`(USE_WHEN phase-1: 표면 분류 + 방법론 명명 요구), `hooks/methodology-selector-gate.sh`(phase-1 proposal 쓰기 시 방법론명 언급 확인 + 통과 시 `.observability-phase1-methods/<issue-n>.json`에 상태 기록 — 상태를 쓰는 유일한 플러그인), `tests/methodology-selector-gate.test.sh`. 에이전트 없음(이슈당 1회 판단). | phase-1 조합의 핵심 멤버(필수). phase-2에서는 상태 소비자(`observability-phase-trace`)에게 근거를 제공하는 역할. |
| 5 | `observability-cardinality-budget` | 방법론 무관, 횡단 규범: 고카디널리티 차원 목록 + 처리 방침 | `plugin.json`, `hooks/directive.sh`(phase-1: 예비 목록 요구 / phase-2: 확정 목록 + 처리 방침 요구), `hooks/cardinality-budget-gate.sh`(phase별 다른 엄격도 + phase-2에서 placeholder-rejection: "N/A"/"해당 없음"/"TBD" 류가 카디널리티 문구에 바로 인접하면 거부 — issue-1 proposal의 failure signal을 최초로 게이트 로직화), `tests/cardinality-budget-gate.test.sh`. 에이전트 없음. | phase-1 조합 필수 멤버(예비 목록) + phase-2 조합 필수 멤버(확정 목록, 채택 방법론 무관하게 항상 적용). |
| 6 | `observability-explorability` | 방법론 무관, 횡단 규범: 사전 미정의 질문에 답하는 애드혹 쿼리 요구 | `plugin.json`, `hooks/directive.sh`(phase-1: 탐색가능성 체크 1줄 요구 / phase-2: 실제 애드혹 쿼리 예시 최소 1개 요구), `hooks/explorability-gate.sh`, `tests/explorability-gate.test.sh`. 에이전트 없음. | phase-1 조합 필수 멤버 + phase-2 조합 필수 멤버. |
| 7 | `observability-phase-trace` | 방법론 무관, 횡단 규범: phase-1이 명명한 방법론과 phase-2가 채택한 방법론의 정합성(순서 제약 상태 추적) | `plugin.json`, `hooks/directive.sh`(HAND_OFF 갱신 시점 규범만, 신호/카디널리티 규범 없음), `hooks/phase-trace-gate.sh`(phase-2 record 쓰기 시 `observability-methodology-selector`가 남긴 상태 파일을 읽어 비교; 상태 파일 없으면 정보용 경고만, 거부 안 함; 이탈 시 "이탈"/"deviat"/"switch" 류 이유 진술 없으면 거부), `tests/phase-trace-gate.test.sh`. 에이전트 없음. | phase-2 조합 필수 멤버. phase-1에는 관여하지 않음(쓸 상태가 아직 없으므로 phase-1 조합에는 포함되지 않음). |

7개 플러그인, 모두 marketplace.json에 개별 엔트리로 등록(아래 write
set). 기존 단일 `observability` 플러그인은 유지하되 역할을 좁힌다 —
아래 "기존 observability 플러그인의 축소된 역할" 참조.

## Phase norms as plugin combinations (설계의 본체)

**기획서(phase-1) 규범** = 아래 플러그인들의 phase-1 체크의 논리곱(AND):

- `observability-methodology-selector` (phase-1): 표면 분류 + 방법론
  명명 — 방법론 선택 없이 지표만 나열하는 제안은 이 멤버가 거부.
- `observability-cardinality-budget` (phase-1): 고카디널리티 후보 차원
  예비 목록 존재.
- `observability-explorability` (phase-1): 탐색가능성 체크 1줄 존재.

`observability-signal-red`/`-use`/`-golden`과 `observability-phase-
trace`는 phase-1 조합에 **들어가지 않는다** — 전자는 아직 확정 계측
지점이 없어 적용 대상이 아니고(phase-2 전용 체크만 가짐), 후자는 아직
비교할 phase-2 산출물이 없다.

**산출물(phase-2) 규범** = 아래 플러그인들의 phase-2 체크의 논리곱:

- `observability-methodology-selector`가 phase-1에서 기록한 상태에
  대응하는 신호 방법론 플러그인 **정확히 하나**
  (`observability-signal-red` 또는 `-use` 또는 `-golden` — 표면이
  여러 개면 표면마다 하나씩, 여러 개 동시 적용 가능. 단, 한 표면에
  대해 두 개 이상의 신호 플러그인이 동시에 요구되는 경우는 없음 —
  "방법론 1개 = 독립 플러그인 1개"가 "표면 1개 = 방법론 1개"라는
  기존 norms 문서의 제약과 결합해 표면당 정확히 하나의 신호 플러그인만
  활성화됨을 보장).
- `observability-cardinality-budget` (phase-2): 확정 목록 + 처리 방침
  + placeholder-rejection.
- `observability-explorability` (phase-2): 실제 애드혹 쿼리 예시.
- `observability-phase-trace` (phase-2): phase-1 상태와의 정합성.

이 조합 표가 "기획서/산출물 규범이 어떤 플러그인 조합으로 성립하는지"에
대한 답이며, 이 proposal의 본체다 — 이전 버전처럼 단일 게이트 스크립트
안에 phase별 분기(if-else)를 두는 대신, phase마다 어떤 플러그인 집합이
활성화되는지로 규범을 표현한다.

## 기존 `observability` 플러그인의 축소된 역할

기존 `observability/hooks/directive.sh`(현재 `core_role_directive` 4-
인자 스텁)와 `observability/hooks/observability-produces-gate.sh`는
제거하지 않는다 — 다만 그 역할을 **역할 자체의 최상위 디렉티브**(role이
무엇을 decide/hand-off하는지, 위 6개 방법론/횡단 플러그인 목록을
안내하는 진입점)로 좁힌다. 신호별·횡단 규범의 실제 게이트 로직은 모두
새 플러그인들로 이동한다. `observability-produces-gate.sh`는 phase-2
발견에서 신규 플러그인들이 커버하지 못하는 잔여 항목이 있는지 다음
survey에서 재확인하되, 이번 phase-1 리비전에서는 "역할 최상위 디렉티브
+ 안내" 역할로 축소된다는 방향만 proposal에 명시하고 실제 코드 변경은
phase 2로 미룬다.

## Write set (frozen for phase 2)

- `.claude-plugin/marketplace.json` — edit: 7개 신규 플러그인 엔트리
  추가(`observability-signal-red`, `observability-signal-use`,
  `observability-signal-golden`, `observability-methodology-selector`,
  `observability-cardinality-budget`, `observability-explorability`,
  `observability-phase-trace`), 기존 `observability` 엔트리는 설명만
  갱신(축소된 역할 반영).
- `observability-signal-red/` — new (plugin.json, hooks/directive.sh,
  hooks/hooks.json, hooks/signal-red-gate.sh)
- `observability-signal-use/` — new (동일 구조)
- `observability-signal-golden/` — new (동일 구조)
- `observability-methodology-selector/` — new (plugin.json,
  hooks/directive.sh, hooks/hooks.json,
  hooks/methodology-selector-gate.sh)
- `observability-cardinality-budget/` — new (plugin.json,
  hooks/directive.sh, hooks/hooks.json,
  hooks/cardinality-budget-gate.sh)
- `observability-explorability/` — new (plugin.json, hooks/directive.sh,
  hooks/hooks.json, hooks/explorability-gate.sh)
- `observability-phase-trace/` — new (plugin.json, hooks/directive.sh,
  hooks/hooks.json, hooks/phase-trace-gate.sh)
- `tests/signal-red-gate.test.sh` — new
- `tests/signal-use-gate.test.sh` — new
- `tests/signal-golden-gate.test.sh` — new
- `tests/methodology-selector-gate.test.sh` — new
- `tests/cardinality-budget-gate.test.sh` — new
- `tests/explorability-gate.test.sh` — new
- `tests/phase-trace-gate.test.sh` — new
- `.gitignore` — edit (신규: `.observability-phase1-methods/` 항목
  추가)
- `observability/README.md` — edit (축소된 역할 + 6개(신호 3 + 횡단 3)
  플러그인으로의 위임 안내, 조합 표 링크)
- `docs/issue-7/reports/observability.md` — phase-2 record (Approve
  이후에만 작성; 이번 phase-1 커밋 범위 아님)

Out of scope for phase 2 execution: `core/` 어떤 파일도 수정하지 않는다
(참조만); SLO/알림 정책·특정 관측가능성 백엔드 선택(issue-1 proposal과
동일 이유로 범위 밖); 반복 디스패치가 실존하지 않는 한 어떤 플러그인에도
`agents/` 신규 작성 안 함(각 플러그인 항목에 이유 명시); phase-1 상태
파일을 git 커밋 대상으로 바꾸는 것(세션 로컬로 충분).

## Alternatives considered

1. **(기각된 이전 버전) 단일 `observability` 플러그인 안에서 directive
   심화 + 게이트 하나를 phase별 if-else로 확장.** 승인자 FEEDBACK으로
   기각 — "방법론 1개 = 독립 플러그인 1개"라는 구조 요구를 만족하지
   못하고, 세 신호 방법론이 한 게이트 스크립트 안에 섞여 "룰북당 여러
   개"라는 freelunch/scout 기준에도 맞지 않는다.
2. **신호 방법론 3개를 하나의 `observability-signals` 플러그인으로
   묶고 내부에서 표면별 분기.** 기각 이유: "방법론 각각을 독립
   플러그인으로"라는 요구를 정확히 위반 — 세 방법론이 한 플러그인
   안에 있으면 그 플러그인이 다시 "여러 방법론을 동시에 담당"하는
   구 구조의 축소판이 된다.
3. **횡단 규범(cardinality/explorability/phase-trace)도 신호 방법론
   플러그인 안에 각각 중복 구현.** 기각 이유: 세 신호 플러그인 모두가
   동일한 카디널리티/탐색가능성 로직을 복사하게 되어 유지보수 시
   드리프트 위험 — 방법론 무관 규범은 별도 플러그인으로 분리해 신호
   플러그인 개수와 무관하게 한 곳에서만 정의한다.
4. **phase-trace 상태 파일 쓰기를 신호 플러그인 각각에 분산.** 기각
   이유: 상태를 누가 쓰는지가 여러 곳으로 흩어지면 "게이트가 상태를
   관리, 에이전트는 관여 안 함" 원칙이 "어느 게이트가?"로 모호해진다 —
   상태 쓰기는 `observability-methodology-selector` 하나로 집중.

## Failure signal

이 설계가 잘못됐다는 신호: (a) 7개 플러그인 분할이 실제 설치/운용에서
과도한 설치 단계로 이어져(플러그인 개수만큼 marketplace install 명령
반복) 실사용자가 일부만 설치하고 나머지를 빠뜨리는 사례가 반복되거나,
(b) 신호 방법론 플러그인 3개 중 실제로는 한 표면에 두 개 이상이
동시에 필요한 사례가 발견되어 "표면당 정확히 하나"라는 전제가 깨지거나,
(c) 횡단 규범 플러그인(cardinality/explorability/phase-trace)이 신호
플러그인 없이는 단독으로 의미가 없어 사실상 항상 함께 설치돼야
한다면 — 분할 경계 자체를 재검토(예: 횡단 규범 3개를 하나의
`observability-crosscutting-norms` 플러그인으로 재통합하는 것 검토,
단 신호 방법론 3개의 독립 분할은 승인자 요구의 핵심이므로 유지).

## How this will be verified (phase 2)

- `.claude-plugin/marketplace.json`에 7개 신규 엔트리 + 기존
  `observability` 엔트리, 총 8개 플러그인 등록 확인.
- 신호 방법론 플러그인 3개 각각이 서로 다른 단일 방법론만 언급하는지
  (`git grep`으로 다른 두 방법론명이 섞여 있지 않은지) 확인.
- 게이트가 있는 플러그인 7개 전부 대응하는
  `tests/<plugin>-gate.test.sh`가 존재하고 각각 최소 named pass/fail
  1쌍 이상을 포함하는지 확인.
- `directive.sh`가 core stub 형태(소스 라인 + `core_role_directive`
  단일 호출)를 벗어나지 않는지 각 플러그인마다 확인.
- 수동: phase-1 proposal 작성 → `observability-methodology-selector`
  상태 파일 생성 → phase-2 record 작성 → `observability-phase-trace`가
  그 상태를 소비하는 순서로 실제 동작 확인.

## Explicitly out of scope for this batch

- SLO/error-budget burn-rate 알림 정책, 특정 관측가능성 백엔드/벤더
  선택 — issue-1 proposal과 동일 이유로 범위 밖.
- `core/` 파일 수정 — 참조만, 복사·수정 금지.
- 반복 디스패치가 실존하지 않는 플러그인에 `agents/` 신규 작성 —
  각 plugin list 항목에 이유 명시.
- phase-1 상태 파일을 git에 커밋하는 방식으로 바꾸는 것 — 세션 로컬
  파일로 충분하다는 판단(위 실패 신호가 뒤집히면 재검토).
- 실제 플러그인 디렉터리/코드 생성 자체 — 이 리비전은 phase-1
  proposal 개정이며, write set에 나열된 신규 디렉터리/파일은 모두
  Approve 이후 phase-2에서 작성한다.
