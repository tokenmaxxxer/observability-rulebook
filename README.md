# observability-rulebook

Rulebook for the `observability` role (contract v3 role-handoff protocol), split off
per `docs/issue-160/proposals/role-taxonomy.md`'s round-4 promotion and
generated as skeleton scaffolding by issue-167.

- **decides**: 프로덕션 내부 상태에 대해 사전에 정의하지 않은 질문도 던질 수 있는가
- **use_when**: 신규 서비스/경로에 계측이 필요할 때
- **produces**: telemetry/instrumentation design, cardinality budget, dashboard/query examples
- **write_scope**: []
- **hand-off**: 장애가 실제로 발생하면 → incident-response

## Install

```
claude plugin marketplace add tokenmaxxxer/observability-rulebook
claude plugin install observability
```

## Layout

- `observability/.claude-plugin/plugin.json` — plugin manifest
- `observability/hooks/hooks.json` — SessionStart wiring (`directive.sh` only)
- `observability/hooks/directive.sh` — role-directive stub: sources core
  canon's `core/hooks/lib/role-directive.sh` and passes this role's four
  doctrine values
- `docs/specs/approvers.md` — Approve-authority allowlist (see below)

The role-agnostic gates (`trailer-gate.sh`, `record-fields-gate.sh`,
`handbook-trigger-gate.sh`) and the `warrant-hunter` hunt agent are no
longer vendored here. They are core canon now (core issue #63/#66):
`core/hooks/hooks.json` fires the three gates for every plugin install,
and `warrant`'s hunter installs independently. This repo stopped shipping
per-role copies of both (issue-66 survey found ~43 near-identical copies
repo-wide) — see `docs/issue-2/proposals/2026-07-31-core-canon-reference-switch.md`.

This is scaffolding, not a finished rulebook: fill in doctrine detail,
handoff enforcement, and any role-specific progress gate before treating
it as load-bearing.
