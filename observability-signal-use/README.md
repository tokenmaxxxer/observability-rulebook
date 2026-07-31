# observability-signal-use

Single-methodology plugin: USE (Utilization/Saturation/Errors), scoped to
resource-bound surfaces only. Part of the observability rulebook's
methodology split — RED/USE/Golden Signals are each independent plugins
rather than branches inside one gate, so a record can adopt at most one
methodology per surface and this plugin only ever checks for USE.

Scope: phase-2 only. This plugin has no phase-1 check — methodology
*selection* (which surface gets which methodology) is
`observability-methodology-selector`'s job. This plugin only fires once a
phase-2 record (`docs/issue-<n>/reports/observability.md`) adopts USE for
some surface, and then requires all three USE signals — utilization,
saturation, errors — each named with a concrete instrumentation point. If
USE isn't mentioned as adopted, this gate no-ops (another signal plugin may
own the record).

## Install

Add an entry for `observability-signal-use` to
`.claude-plugin/marketplace.json` and install it alongside
`observability-methodology-selector`, `observability-cardinality-budget`,
and `observability-explorability`.

## Kill switch

`export OBSERVABILITY_SIGNAL_USE_GATE_OFF=1`

No `agents/` directory — methodology adoption is a single per-surface
judgment made once at phase-2 write time, not a repeated dispatch cadence,
so there is no agent role for this plugin to own.
