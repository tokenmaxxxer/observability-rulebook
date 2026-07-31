# observability-signal-red

Single-methodology plugin for **RED** (Rate/Errors/Duration), scoped to
request-driven surfaces only. Part of the observability plugin set (see
`docs/issue-7/proposals/2026-07-31-produces-methodology-hook-machine.md`) —
each signal methodology (RED/USE/Golden Signals) gets its own independent,
self-contained plugin instead of one gate branching on all three.

## Scope

Phase-2 only. This plugin has no phase-1 check — surface classification and
methodology naming belong to `observability-methodology-selector`. This
plugin only fires once RED has been named as the adopted methodology for a
surface and the phase-2 record (`docs/issue-<n>/reports/observability.md`)
is being written. If RED is not mentioned in the write, the gate is a no-op
so `observability-signal-use`/`-golden` (or neither) can own that write
instead — the record path is shared across signal plugins.

When RED is mentioned, the gate requires all three RED signals (rate,
errors, duration) to appear with a concrete instrumentation point each.

## Install

Add to the marketplace and install `observability-signal-red` alongside the
other observability plugins.

## Kill switch

`export OBSERVABILITY_SIGNAL_RED_GATE_OFF=1` disables the gate.

## No agents/

Methodology adoption is a single per-surface judgment made once, not a
repeated dispatch cadence — so this plugin has no `agents/` directory.
