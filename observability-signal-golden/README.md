# observability-signal-golden

Single-methodology plugin: Golden Signals (Latency/Traffic/Errors/
Saturation), for **service-rollup surfaces only**. One plugin, one
methodology — split out per the issue-7 approver feedback so no plugin
covers more than one signal-selection methodology (see `observability-
signal-red` and `observability-signal-use` for the other two).

## Scope

Phase-2 only. This plugin does not gate phase-1 proposals — it fires
when `docs/issue-<n>/reports/observability.md` is written/edited and
the resulting text adopts Golden Signals for some surface. It is a
no-op if Golden Signals isn't mentioned as adopted (RED/USE records
pass through untouched). When adopted, it requires all four signals —
latency, traffic, errors, saturation — each named with a concrete
instrumentation point.

## Install

Add this plugin alongside the other observability-* methodology and
cross-cutting plugins via this repo's `.claude-plugin/marketplace.json`.

## Kill switch

`export OBSERVABILITY_SIGNAL_GOLDEN_GATE_OFF=1` disables the gate.

## No agents/

Methodology adoption is a single per-surface judgment made once in
phase-1 and confirmed once in phase-2 — there is no repeated dispatch
cadence for this plugin to own, so it carries no `agents/` directory.
