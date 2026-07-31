# observability-methodology-selector

Governs one narrow procedure: the phase-1 (proposal) step where every
surface a proposal touches is classified as request-driven,
resource-bound, or service-rollup, and exactly one signal methodology
(RED, USE, or Golden Signals respectively) is named for it.

This plugin is split out from the signal-methodology plugins on
purpose. It does not implement RED, USE, or Golden Signals itself — it
only requires that the *selection* happen and be legible in the
proposal text. The signal content (which specific metrics, how they're
instrumented) is owned by the sibling plugins `observability-signal-red`,
`observability-signal-use`, and `observability-signal-golden`.

## Install

```
claude plugin install observability-methodology-selector@tokenmaxxxer-observability
```

## Gate

`hooks/methodology-selector-gate.sh` fires on Write/Edit/MultiEdit
targeting `docs/issue-<n>/proposals/*observability*.md`. It denies the
write unless the resulting text names both a signal methodology and a
surface classification. On a passing write it best-effort records
`.observability-phase1-methods/<issue-n>.json` — the state file that
`observability-phase-trace` later reads to check phase-1/phase-2
consistency.

Kill switch: `export OBSERVABILITY_METHODOLOGY_SELECTOR_GATE_OFF=1`
