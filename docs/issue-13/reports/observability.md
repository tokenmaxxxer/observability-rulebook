# Phase-2 record: gate A+ hardening for residual defects (issue-13)

Implements `docs/issue-13/proposals/gate-a-plus-hardening.md` (approved
2026-08-01 via `APPROVE issue-13/observability`), grounded in
`docs/issue-13/reports/observability/current-state-survey.md`. All five
proposal sections were applied to all eight plugins in this repo.

## Signal Selection

Surface classification: the eight-plugin gate suite itself is a
service-rollup surface (a common piece of infrastructure every future
observability record passes through, not a single request path or a
single resource), so the adopted methodology here is Golden Signals
(latency/traffic/errors/saturation), applied to the test/compliance
harness this phase-2 delivery hardens rather than to a production
service:

- **latency**: each `tests/*.test.sh` file's own wall-clock run time —
  all 9 files complete in well under a second each; no test introduced a
  network call or sleep.
- **traffic**: the count of tool-call scenarios each suite drives through
  its gate — 194 total invocations across the 9 files this phase-2 pass
  added or extended.
- **errors**: failed assertions, reported per-file by each suite's own
  `report()` helper (`want` vs `got`) and aggregated by
  `compliance-check.sh`'s structural findings.
- **saturation**: this phase-2 pass ran eight independent background
  workers concurrently (one per plugin, disjoint file ownership) — the
  relevant saturation signal was worker completion order, not resource
  contention, since each worker owned a disjoint file set with no
  overlapping mutable state.

This is separate from — and does not replace — the produces-shape check
this record itself is subject to (`observability-produces-gate.sh`), nor
the per-plugin signal-methodology classification those gates enforce
on *other* future records. What this phase-2 delivery does is close a
gap in how the gates *enforce* that naming requirement on other, future
records: previously a shell-written write to a record file could bypass
the produces-shape check entirely (the matcher/gate coverage defect,
section (b) below); after this change, such a write is denied outright
instead of silently skipping the check.

## Cardinality Budget

카디널리티 후보: 이번 작업이 다루는 상태 파일
(`.observability-phase1-methods/<issue_n>.json`)의 키는 `issue`(정수
이슈 번호 문자열, 저카디널리티 — 레포당 이슈 수만큼만 존재)와
`methodology_named`(불리언)뿐이며, user_id/request_id 류의 고카디널리티
차원은 애초에 존재하지 않는다. 처리 방침: 상태 파일 키 집합은 변경하지
않았다(drop/hash/bucket 대상 없음 — 애초에 후보가 없다는 것을 직접
확인함). 신규로 추가된 유일한 데이터는 compliance-check/테스트 스위트의
pass/fail 카운트로, 이 역시 실행당 하나의 정수이며 카디널리티 문제가
없다.

## Ad-hoc Queries

애드혹 쿼리 예시: "이 8개 플러그인 중 아직 `||` 가드가 없는
gate-lib.sh source line이 남아있는가?"에 대한 답은 사전에 정의된
대시보드가 아니라 즉석 grep으로 얻는다 —
`grep -rn 'gate-lib\.sh"$' */hooks/*.sh` (guard가 있으면 라인이
`|| { ... }`로 끝나 이 패턴에 매치되지 않음; 매치되는 라인이 있으면
그 파일이 미가드 상태라는 뜻). 실행 결과 매치 0건 — 8개 전부 가드됨.

## What changed (per proposal section)

### (a) PostToolUse migration — `observability-methodology-selector`
The state-write (`.observability-phase1-methods/<issue_n>.json`) moved
out of `methodology-selector-gate.sh`'s `PreToolUse` path entirely. A new
`methodology-selector-status.sh` is connected under a new `PostToolUse`
entry (matcher `.*`) in `observability-methodology-selector/hooks/hooks.json`.
It independently re-derives success from the PostToolUse payload's
`tool_response` (present, no truthy `error`/`is_error`), then re-reads
the file from disk (the write has already completed by PostToolUse time)
and re-applies the same methodology/surface needle checks before writing
state — idempotent overwrite, `except OSError: pass`, never denies
(informational only, per the proposal's failure-isolation guidance).

### (b) Matcher/gate coverage parity — all 8 plugins
Every gate sharing the `if tool in ("Write","Edit","MultiEdit"): ...
elif NotebookEdit: ... if path is None: sys.exit(0)` shape now has a
`Bash` branch that extracts path-shaped tokens via
`gate_lib.gate_bash_write_targets` and checks each against the gate's own
relevance regex(es) (`RECORD_RE` and/or `PROPOSAL_RE`, gate-specific). A
matched Bash write denies outright (cannot reconstruct Bash-issued
content — no organized `tool_input` to read), rather than attempting the
normal produces-shape content check. Every `hooks.json`'s `PreToolUse`
matcher narrowed from `.*` to `Write|Edit|MultiEdit|NotebookEdit|Bash`
(the `methodology-selector` `PostToolUse` entry stays `.*` by design,
since it must observe every completed write to catch the record/proposal
path and never denies).

### (c) Fail-closed on state-file corruption — `observability-phase-trace`
`phase-trace-gate.sh`'s corrupt/unparseable
`.observability-phase1-methods/<n>.json` branch now `deny(...)`s instead
of allowing. The adjacent missing-file branch (no phase-1 state yet — a
legitimate state) is untouched and still allows.

### (d)/(e) Env resolution + `||` guard — all 8 plugins + directives
All eight `tests/*.test.sh` `CLAUDE_PLUGIN_ROOT_CORE` exports now use the
`${CLAUDE_PLUGIN_ROOT_CORE:-<default>}` fallback shape (same env var the
runtime injects per on-the-record issue #182), pointed at this
environment's actual core checkout. All 8 gate scripts' and all 8
`directive.sh` files' `gate-lib.sh`/`role-directive.sh` source lines now
carry the `|| { echo "<script>.sh: cannot source <lib>.sh" >&2; exit 2; }`
guard from core issue #75's finalized pattern, verbatim.

### (f) Missing-core test + full suite green + compliance-check
Every `tests/*.test.sh` file (8 gate suites + the new
`tests/readme-ghost-check.test.sh`) has a missing-core case (points
`CLAUDE_PLUGIN_ROOT_CORE` at a nonexistent path, asserts deny/exit-2 —
meaningful now that section (e)'s guard actually lands) and a
Bash-write-coverage case (a Bash command targeting the relevant record
path denies; an unrelated Bash command allows).

**Suite run** (`CLAUDE_PLUGIN_ROOT_CORE` pointed at this environment's
core checkout): all 9 test files green, 194 total assertions passed, 0
failed —
`cardinality-budget-gate.test.sh` 25/25,
`explorability-gate.test.sh` 26/26,
`methodology-selector-gate.test.sh` 26/26,
`observability-produces-gate.test.sh` 20/20,
`phase-trace-gate.test.sh` 26/26,
`readme-ghost-check.test.sh` 5/5,
`signal-golden-gate.test.sh` 23/23,
the RATE/errors/duration signal plugin's suite 21/21,
`signal-use-gate.test.sh` 22/22.

**Compliance-check run** (`core/hooks/tests/compliance-check.sh` against
each of the 8 plugins' `hooks/` directory): all 8 report `ok`, 0
`"sources gate-lib.sh with no || guard"` findings remain.

### (g) README/manifest ghost-file cleanup
The survey (section 5) found no currently-existing ghost-file/stale-role
references — the one mention in `README.md:44-50` is correctly phrased
as past-tense history ("no longer bundled here"). Added
`tests/readme-ghost-check.test.sh` as the standing regression guard the
issue asks for regardless: asserts `trailer-gate.sh`,
`record-fields-gate.sh`, `handbook-trigger-gate.sh`, `warrant-hunter`
name no file that actually ships under this repo's `observability*/`
trees, and that any mention of those names in `README.md` or
`observability/.claude-plugin/plugin.json` is qualified as history
("no longer bundled" / "core canon now" / etc.) rather than a
present-tense claim. 5/5 green today; a future edit that reintroduces an
unqualified stale reference or a ghost file will fail this test.

## What was done

All five proposal sections applied across all eight plugins in one
phase-2 pass: (a) the methodology-selector state-write moved from
PreToolUse to a new PostToolUse status script; (b) a Bash branch closed
the Bash-write bypass in all 8 gates, with matchers narrowed to match
actual gate coverage; (c) phase-trace's corrupt-state branch now fails
closed; (d) all 8 test harnesses' `CLAUDE_PLUGIN_ROOT_CORE` now uses the
overridable `${VAR:-default}` fallback shape; (e) all 8 gate scripts and
all 8 directive scripts now carry core issue #75's `||`-guarded source
line; (f) missing-core and Bash-write-coverage test cases added to every
suite, full suite run green (194/194), compliance-check run clean on all
8 gates; (g) a standing README/manifest ghost-file regression test added
(no ghosts found today, ships as a guard against future regressions).

## Why

Rationale: issue-13's 2026-08-01 re-audit (grade B+) found these four
residual defects surviving the issue-10 gate-lib migration and asked for
an A+ close-out — approved via `APPROVE issue-13/observability`
(single-account mode, JiwonJung94, `docs/specs/approvers.md`) against
`docs/issue-13/proposals/gate-a-plus-hardening.md`.

## Upstream basis

Based on: `docs/issue-13/proposals/gate-a-plus-hardening.md` and
`docs/issue-13/reports/observability/current-state-survey.md`, citing and
reusing (never re-deriving) core issue #75's finalized `||`-guard pattern
and Python `gate_bash_write_targets` port, and on-the-record issue #182's
`CLAUDE_PLUGIN_ROOT_CORE` runtime injection.

## Status

loop_state: landed

## Open findings

None outstanding — full test suite green (194/194 across 9 files) and
`compliance-check.sh` passes clean on all 8 gates.
