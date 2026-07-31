# observability-explorability

Methodology-agnostic cross-cutting norm: an observability plan or record
must stay queryable for questions nobody defined in advance — an
ad-hoc/explorable query capability, not just fixed pre-built dashboards.
This applies regardless of which signal methodology (RED/USE/Golden
Signals) the surface adopts.

One gate covers both write surfaces:

- **phase-1** (`docs/issue-<n>/proposals/*observability*.md`) — requires
  a one-line explorability check (explorability/탐색가능/ad-hoc/adhoc/
  ad hoc/애드혹 mentioned) — the design must keep exploration open.
- **phase-2** (`docs/issue-<n>/reports/observability.md`) — requires
  both the explorability mention AND a concrete query-shape marker
  (SELECT/`query:`/쿼리:/a code fence/WHERE/GROUP BY) — at least one
  actual ad-hoc query example answering a question not pre-defined by a
  dashboard, not just the word "explorability".

## Install

Add `observability-explorability` to `.claude-plugin/marketplace.json`
and install it alongside the other observability plugins.

## Kill switch

`export OBSERVABILITY_EXPLORABILITY_GATE_OFF=1` disables the gate.

No `agents/` — this is a cross-cutting norm check with no repeated
dispatch cadence (judgment happens once per phase-1/phase-2 write, not
on a recurring cycle).
