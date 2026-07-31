# Scout brief — observability domain norms (issue-1)

Mode: parallel WebSearch, 4 angles, 1 sweep stage, no deepening round
needed (JUDGE POINT 1: the four angles converged cleanly on the same
canon with no contested exemplar; JUDGE POINT 2: another round would not
change the adopted set — stop). Total: 1 stage, well under the 5-stage /
3min budget.

## Angles run

1. Google SRE golden signals / SLI-SLO methodology
2. RED (Wilkie) / USE (Gregg) methods
3. OpenTelemetry semantic conventions (instrumentation naming standard)
4. Charity Majors — observability engineering, high-cardinality/wide
   structured events ("observability 2.0")

## Must-bes (what every strong source assumes)

- **A fixed, small "what to measure" vocabulary before instrumenting.**
  Golden Signals (latency/traffic/errors/saturation) and RED
  (rate/errors/duration, request-driven) / USE (utilization/saturation/
  errors, resource-driven) all exist because ad-hoc metric selection
  doesn't compose across services.
- **A naming/attribute standard, not per-team convention.** OpenTelemetry
  semantic conventions exist specifically because inconsistent naming
  breaks cross-service correlation — this is the industry's converged
  answer to "how do you instrument," not one vendor's opinion.
- **Cardinality is a first-class, budgeted design constraint, not an
  afterthought.** Majors: cardinality/dimensionality management consumes
  "an outright majority" of observability engineering teams' time; a
  design that doesn't budget it up front pays for it later in cost or in
  an unusable dataset.
- **The point is answering unplanned questions, not just dashboards.**
  Majors' "explorability" criterion is the direct match for this role's
  own doctrine line ("사전에 정의하지 않은 질문도 던질 수 있는가") — a
  telemetry design that only supports its author's anticipated queries
  fails the role's own decision test.

## Performance axes (where strong practice visibly competes)

1. **Signal selection discipline** — RED for request-path services vs.
   USE for resource-bound components vs. golden-signals as the
   service-level rollup; picking the wrong one for the wrong surface is
   a recognized failure mode (RED does not answer "which resource is the
   bottleneck," USE does not answer "what are requests experiencing").
2. **Cardinality budgeting rigor** — stated numeric/qualitative budget
   with an explicit high-cardinality-dimension list, vs. no budget at
   all (the common failure Majors describes).
3. **Explorability vs. dashboard-only** — does the design leave a path to
   ask a question nobody anticipated (wide events / high-dimensionality
   queries), or only pre-built panels for pre-known failure modes.

## Adopt / skip

- **Adopt:** RED/USE/Golden-Signals as the required signal-selection
  method (pick the fitting one(s) per surface, state which and why) +
  OpenTelemetry semantic conventions as the naming/attribute standard
  for whatever is instrumented + an explicit cardinality budget as a
  required artifact component + an explorability check (does this design
  survive an unplanned question) as the acceptance criterion tying back
  to the role's own `decides` line.
- **Skip:** mandating full "observability 2.0" wide-event/single-store
  architecture migrations — that is an infrastructure/platform decision
  (tool choice, storage backend) out of a rulebook's scope; this role
  prescribes what to design and check, not which vendor/backend to run.
  Also skip prescribing a specific SLO error-budget policy (burn-rate
  alerting math) — real but a level below "phase-1 proposal norms /
  phase-2 deliverable norms," reserved as an optional deepening a future
  design may add, not a mandatory minimum here.

## Segment fit

This repo's `observability` role is a design/spec-producing role
(`produces: telemetry/instrumentation design, cardinality budget,
dashboard/query examples` — `observability/hooks/directive.sh`), not an
implementation or ops role — it matches the "design phase" segment of the
field (SRE/observability-engineering methodology and instrumentation
standards), not the "runtime/incident" segment (paging, on-call, alerting
policy), which the role's own hand-off line explicitly routes elsewhere
("장애가 실제로 발생하면 → incident-response").

## Gap line (current state vs. field must-bes)

Current state (see current-state-survey.md): the role's `produces` line
already names the right *deliverable categories* (design, cardinality
budget, examples) but the rulebook enforces **none** of the field
must-bes mechanically or textually — no required signal-selection method,
no required naming standard, no required cardinality-budget shape, no
explorability check. Every must-be above is missing from the current
plugin; this proposal exists to close exactly that gap, not to invent
new deliverable categories the role doesn't already claim.

## Sources

- [Setting better SLOs using Google's Golden Signals — Gremlin](https://www.gremlin.com/blog/setting-better-slos-using-googles-golden-signals)
- [SRE Metrics: Four Golden Signals — Splunk](https://www.splunk.com/en_us/blog/learn/sre-metrics-four-golden-signals-of-monitoring.html)
- [The RED Method: How to Instrument Your Services — Grafana Labs](https://grafana.com/blog/the-red-method-how-to-instrument-your-services/)
- [RED method vs USE method — ClickHouse](https://clickhouse.com/resources/engineering/red-use-methods)
- [RED and USE Metrics for Monitoring and Observability — Better Stack](https://betterstack.com/community/guides/monitoring/red-use-metrics/)
- [Metrics semantic conventions — OpenTelemetry](https://opentelemetry.io/docs/specs/semconv/general/metrics/)
- [OpenTelemetry semantic conventions 1.43.0 — OpenTelemetry](https://opentelemetry.io/docs/specs/semconv/)
- [GitHub — open-telemetry/semantic-conventions](https://github.com/open-telemetry/semantic-conventions)
- [Breaking the Pillars: Rethinking Observability with Charity Majors — Cockroach Labs](https://www.cockroachlabs.com/big-ideas-podcast/breaking-the-pillars-rethinking-observability-with-charity-majors/)
- [Shifting from Observability 1.0 to 2.0 — Last Week in AWS](https://www.lastweekinaws.com/podcast/screaming-in-the-cloud/shifting-from-observability-1-0-to-2-0-with-charity-majors/)
