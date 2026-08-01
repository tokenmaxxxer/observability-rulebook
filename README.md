# observability-rulebook

Rulebook for the `observability` role (contract v3 role-handoff protocol), split off
per `docs/issue-160/proposals/role-taxonomy.md`'s round-4 promotion and
generated as skeleton scaffolding by issue-167.

- **decides**: 프로덕션 내부 상태에 대해 사전에 정의하지 않은 질문도 던질 수 있는가
- **use_when**: 신규 서비스/경로에 계측이 필요할 때
- **produces**: telemetry/instrumentation design (surface별 RED/USE/Golden Signals 선택 근거 + semconv 네이밍), cardinality budget (고카디널리티 차원 목록 + 처리 방침), dashboard/query examples (최소 하나는 사전 미정의 질문에 답하는 애드혹 쿼리) — 상세 규범은 `docs/issue-1/proposals/2026-07-31-observability-rulebook-norms.md`
- **write_scope**: []
- **hand-off**: 장애가 실제로 발생하면 → incident-response

## Install

```
claude plugin marketplace add tokenmaxxxer/observability-rulebook
claude plugin install observability
```

## Layout

- `observability/.claude-plugin/plugin.json` — plugin manifest
- `observability/hooks/hooks.json` — SessionStart wiring (`directive.sh`)
  plus a `PreToolUse` entry for the role-owned produces gate below
- `observability/hooks/directive.sh` — role-directive stub: sources core
  canon's `core/hooks/lib/role-directive.sh` and passes this role's four
  doctrine values
- `observability/hooks/observability-produces-gate.sh` — role-owned
  `PreToolUse` gate. On a write to this role's own record
  (`docs/issue-<n>/reports/observability.md`) it checks, independent of
  core's role-agnostic §20 field check, that the phase-2 `produces`
  shape is present: a named signal-selection methodology (RED/USE/Golden
  Signals), an explicit cardinality budget, and an ad-hoc/explorable
  query example. See
  `docs/issue-1/proposals/2026-07-31-observability-rulebook-norms.md`.
  Every gate in this repo's plugin set, including this one, sources
  core's shared `core/hooks/lib/gate-lib.sh`/`gate-lib.py` per the
  gate-house standard's per-repo migration checklist, referenced (via
  `CLAUDE_PLUGIN_ROOT_CORE`) rather than vendored — the same
  reference-only pattern the next section describes for the
  role-agnostic gates.
- `docs/specs/approvers.md` — Approve-authority allowlist (see below)

The role-agnostic gates (`trailer-gate.sh`, `record-fields-gate.sh`,
`handbook-trigger-gate.sh`) and the `warrant-hunter` hunt agent are no
longer vendored here. They are core canon now (core issue #63/#66):
`core/hooks/hooks.json` fires the three gates for every plugin install,
and `warrant`'s hunter installs independently. This repo stopped shipping
per-role copies of both (issue-66 survey found ~43 near-identical copies
repo-wide) — see `docs/issue-2/proposals/2026-07-31-core-canon-reference-switch.md`.

## Plugins

This repo ships eight plugins:

- [`observability`](observability/README.md) — Rulebook for the
  `observability` role (contract v3 role-handoff protocol), split off
  per `docs/issue-160/proposals/role-taxonomy.md`'s round-4 promotion
  and generated as skeleton scaffolding by issue-167.
- [`observability-cardinality-budget`](observability-cardinality-budget/README.md) —
  Methodology-agnostic cross-cutting norm: any observability plan or
  record must budget its time-series cardinality up front — a list of
  candidate high-cardinality dimensions (e.g. `user_id`, `request_id`,
  raw URL path) plus an explicit handling policy per dimension
  (drop/hash/bucket/aggregate-away).
- [`observability-explorability`](observability-explorability/README.md) —
  Methodology-agnostic cross-cutting norm: an observability plan or
  record must stay queryable for questions nobody defined in advance —
  an ad-hoc/explorable query capability, not just fixed pre-built
  dashboards.
- [`observability-methodology-selector`](observability-methodology-selector/README.md) —
  Governs one narrow procedure: the phase-1 (proposal) step where every
  surface a proposal touches is classified as request-driven,
  resource-bound, or service-rollup, and exactly one signal methodology
  (RED, USE, or Golden Signals respectively) is named for it.
- [`observability-phase-trace`](observability-phase-trace/README.md) —
  Methodology-agnostic cross-cutting norm: phase-2's adopted signal
  methodology (RED/USE/Golden Signals) must trace back to what phase-1
  already named.
- [`observability-signal-golden`](observability-signal-golden/README.md) —
  Single-methodology plugin: Golden Signals (Latency/Traffic/Errors/
  Saturation), for service-rollup surfaces only.
- [`observability-signal-red`](observability-signal-red/README.md) —
  Single-methodology plugin for RED (Rate/Errors/Duration), scoped to
  request-driven surfaces only.
- [`observability-signal-use`](observability-signal-use/README.md) —
  Single-methodology plugin: USE (Utilization/Saturation/Errors), scoped
  to resource-bound surfaces only.

## Kill switches

| Env var | Gates |
|---|---|
| `OBSERVABILITY_PRODUCES_GATE_OFF` | `observability/hooks/observability-produces-gate.sh` on `docs/issue-<n>/reports/observability.md` |
| `OBSERVABILITY_METHODOLOGY_SELECTOR_GATE_OFF` | `observability-methodology-selector/hooks/methodology-selector-gate.sh` on `docs/issue-<n>/proposals/*observability*.md` |
| `OBSERVABILITY_PHASE_TRACE_GATE_OFF` | `observability-phase-trace`'s gate on `docs/issue-<n>/reports/observability.md` (consumes `.observability-phase1-methods/<issue-n>.json`) |
| `OBSERVABILITY_SIGNAL_GOLDEN_GATE_OFF` | `observability-signal-golden`'s gate on `docs/issue-<n>/reports/observability.md` |
| `OBSERVABILITY_SIGNAL_RED_GATE_OFF` | `observability-signal-red`'s gate on `docs/issue-<n>/reports/observability.md` |
| `OBSERVABILITY_SIGNAL_USE_GATE_OFF` | `observability-signal-use`'s gate on `docs/issue-<n>/reports/observability.md` |
| `OBSERVABILITY_EXPLORABILITY_GATE_OFF` | `observability-explorability`'s gate on `docs/issue-<n>/proposals/*observability*.md` (phase-1) and `docs/issue-<n>/reports/observability.md` (phase-2) |
| `OBSERVABILITY_CARDINALITY_BUDGET_GATE_OFF` | `observability-cardinality-budget`'s gate on `docs/issue-<n>/proposals/*observability*.md` (phase-1) and `docs/issue-<n>/reports/observability.md` (phase-2) |

This is scaffolding, not a finished rulebook: fill in doctrine detail,
handoff enforcement, and any role-specific progress gate before treating
it as load-bearing.
