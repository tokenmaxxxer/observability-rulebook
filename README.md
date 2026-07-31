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
- `observability/hooks/hooks.json` — SessionStart + PreToolUse wiring
- `observability/hooks/directive.sh` — SessionStart role directive
- `observability/hooks/record-fields-gate.sh` — this role's record required-field gate
- `observability/hooks/trailer-gate.sh` — commit `Subject: issue-<n>` trailer gate
- `observability/hooks/handbook-trigger-gate.sh` — s21 handbook-sync gate
- `observability/agents/warrant-hunter.md` — rotating-stance hunt agent
- `docs/specs/approvers.md` — Approve-authority allowlist (see below)

This is scaffolding, not a finished rulebook: fill in doctrine detail,
handoff enforcement, and any role-specific progress gate before treating
it as load-bearing.
