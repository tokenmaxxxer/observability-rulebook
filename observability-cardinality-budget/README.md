# observability-cardinality-budget

Methodology-agnostic cross-cutting norm: any observability plan or record
must budget its time-series cardinality up front — a list of candidate
high-cardinality dimensions (e.g. `user_id`, `request_id`, raw URL path)
plus an explicit handling policy per dimension (drop/hash/bucket/
aggregate-away). This applies regardless of which signal methodology
(RED/USE/Golden Signals) the surface adopts.

One gate covers both write surfaces:

- **phase-1** (`docs/issue-<n>/proposals/*observability*.md`) — requires
  a preliminary candidate list ("cardinality"/"카디널리티" mentioned).
- **phase-2** (`docs/issue-<n>/reports/observability.md`) — requires the
  confirmed list, requires the cardinality statement is not immediately
  adjacent to a placeholder token (`N/A`/`해당 없음`/`TBD`), and requires
  an explicit handling-policy keyword (drop/hash/bucket/aggregate/버킷/
  해시/제거) somewhere in the record.

## Install

Add `observability-cardinality-budget` to `.claude-plugin/marketplace.json`
and install it alongside the other observability plugins.

## Kill switch

`export OBSERVABILITY_CARDINALITY_BUDGET_GATE_OFF=1` disables the gate.

No `agents/` — this is a cross-cutting norm check with no repeated
dispatch cadence (judgment happens once per phase-1/phase-2 write, not
on a recurring cycle).
