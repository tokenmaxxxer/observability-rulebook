# observability (role entry point)

Role on contract v3. Decides: 프로덕션 내부 상태에 대해 사전에 정의하지
않은 질문도 던질 수 있는가. USE WHEN: 신규 서비스/경로에 계측이 필요할
때. HAND-OFF: 장애가 실제로 발생하면 → incident-response.

## Scope (narrowed, issue-7)

As of issue-7's phase-2 delivery, this plugin is the role's top-level
directive + entry point only. Actual produces norms are implemented by
seven sibling plugins, each owning exactly one methodology:

| Plugin | Owns |
|---|---|
| `observability-methodology-selector` | phase-1: surface classification + naming exactly one signal methodology |
| `observability-signal-red` | phase-2: RED (Rate/Errors/Duration), request-driven surfaces |
| `observability-signal-use` | phase-2: USE (Utilization/Saturation/Errors), resource-bound surfaces |
| `observability-signal-golden` | phase-2: Golden Signals (Latency/Traffic/Errors/Saturation), service-rollup surfaces |
| `observability-cardinality-budget` | phase-1 preliminary + phase-2 confirmed high-cardinality dimension list + handling policy |
| `observability-explorability` | phase-1 check + phase-2 ad-hoc query example |
| `observability-phase-trace` | phase-2 consistency check against phase-1's named methodology |

Phase norms are the AND of the relevant plugins' phase checks, not a
property of any single plugin — see
`docs/issue-7/proposals/2026-07-31-produces-methodology-hook-machine.md`
("Phase norms as plugin combinations") for the full combination table.

This plugin's own gate (`observability-produces-gate.sh`) still checks
the phase-2 record for the same three (b) categories as a role-level
backstop; it is independent of, and does not replace, the per-methodology
gates above.

## Files

- `hooks/directive.sh` — `SessionStart` hook, core-stub form, role-level
  directive + pointer to the plugin combination above.
- `hooks/observability-produces-gate.sh` — `PreToolUse` gate on
  `docs/issue-<n>/reports/observability.md`, role-level produces-shape
  backstop (fail-closed; kill switch
  `OBSERVABILITY_PRODUCES_GATE_OFF=1`).

## Install

    claude plugin marketplace add tokenmaxxxer/tokenmaxxxer-observability
    claude plugin install observability@tokenmaxxxer-observability

Install the methodology/cross-cutting plugins above separately as needed
(one methodology plugin per adopted signal type, both cross-cutting
plugins always).
