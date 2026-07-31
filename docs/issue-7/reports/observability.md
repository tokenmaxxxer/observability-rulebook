# Observability record — issue-7: plugin-set implementation

loop_state: landed

upstream: docs/issue-7/proposals/2026-07-31-produces-methodology-hook-machine.md
(phase-1 proposal, approved via issue comment `APPROVE issue-7/observability`,
single-account mode)

## Why

Issue #7 asks for the produces methodology adopted in issue-1 (RED/USE/
Golden Signals selection, cardinality budget, ad-hoc explorability) to be
mechanically enforced, not left as a directive summary + prose document.
The approver's revision (issue #7 comment "요구 정정") rejected a single-
plugin deepening and required a **plugin set**: one independent,
freelunch-completeness plugin per methodology, with phase-1/phase-2
norms expressed as combinations of those plugins rather than one gate's
if-else branches.

## What was done (phase 2)

Built the seven plugins named in the approved proposal's "Plugin list"
table, each self-contained (own `.claude-plugin/plugin.json`,
`hooks/hooks.json`, `hooks/directive.sh` in core-stub form, a gate where
the proposal calls for one, a `README.md`), registered individually in
`.claude-plugin/marketplace.json`:

- `observability-methodology-selector` — phase-1 surface classification
  + single methodology naming; on a passing write records state to
  `.observability-phase1-methods/<issue-n>.json` (gitignored, session-
  local), consumed by `observability-phase-trace`.
- `observability-signal-red` / `observability-signal-use` /
  `observability-signal-golden` — RED / USE / Golden Signals, each
  phase-2-only, each gate a no-op unless its own methodology is
  mentioned as adopted (so all three can share the phase-2 record path
  without collision, and no plugin implements more than one
  methodology).
- `observability-cardinality-budget` — one gate covering both the
  phase-1 proposal surface and the phase-2 record surface (OR'd regex,
  same shape as pricing-rulebook's `methodology-gate.sh`); phase-2
  additionally rejects placeholder values ("N/A"/"TBD"/"해당 없음")
  adjacent to the cardinality statement.
- `observability-explorability` — same dual-surface shape; phase-2
  requires an actual ad-hoc query example (a query-shape marker), not
  just the word "ad-hoc".
- `observability-phase-trace` — reads (never writes) the state file
  from `observability-methodology-selector`; informational only when
  the state file is absent; denies only when phase-2 text states a
  methodology deviation with no reason given.

`tests/<plugin>-gate.test.sh` added at repo root for every gated plugin
(7 test scripts).

Existing `observability` plugin's role was narrowed to entry point +
role-level directive: `observability/hooks/directive.sh` edited to
point at the seven plugins above instead of carrying all produces
detail in one string; `observability/README.md` added documenting the
combination table. `observability/hooks/observability-produces-gate.sh`
kept unchanged — an independent role-level backstop on the phase-2
record, not in this batch's frozen write set (proposal explicitly
deferred narrowing it to a future issue).

No file under any path containing `core` was read into, copied into, or
modified by this delivery — canon referenced by directory-relative
sourcing convention only (`hooks/directive.sh`'s existing source line),
per the issue's constraint.

## How this was verified

- `bash -n` clean on every new/edited `hooks/*.sh` and every
  `tests/*.test.sh`.
- All 7 gate test suites pass: methodology-selector 4/4, signal-red
  4/4, signal-use 4/4, signal-golden 4/4, cardinality-budget 6/6,
  explorability 6/6, phase-trace 5/5 — 34 named pass/fail cases total,
  0 failures.
- `.claude-plugin/marketplace.json` and every new `plugin.json`/
  `hooks.json` parse as valid JSON; marketplace has 8 entries
  (existing `observability` + the 7 new plugins).
- Each signal plugin verified (via `git grep`) to reference only its
  own single methodology name in its directive/gate — no plugin covers
  two or more of RED/USE/Golden Signals.

## Signal-selection methodology (this record itself)

Not applicable. This record documents infrastructure (the hook/gate
plugin set), not a telemetry design for a production service surface —
there is no RED/USE/Golden Signals selection to make for this
delivery. `observability-produces-gate.sh`'s own scope note explains it
scans this same file path as a role-level backstop independent of the
methodology plugins; that scan is not itself a claim that this record
is a telemetry-design output.

## Cardinality budget

Not applicable — no time-series or label design was created by this
delivery. The `observability-cardinality-budget` plugin's own gate is
what future telemetry-design records must satisfy.

## Ad-hoc query example

Not applicable for the same reason — no dashboards/queries exist yet
for this delivery. The `observability-explorability` plugin's gate is
what future records must satisfy with a concrete query example.

## Open findings

- `observability-produces-gate.sh` (existing, unchanged) still performs
  its own independent phase-2 produces-shape check on the same record
  path as the new plugins — intentionally redundant per the proposal's
  frozen write set. A future issue could fold it into the plugin set or
  retire it once the new plugins are proven in practice.
- `observability-phase-trace`'s deviation check is whole-document
  keyword presence, not strict proximity between the deviation marker
  and its reason — matches the proposal's stated design (simplicity
  over precision) but is a known coarseness if a record separates the
  two by unrelated content.
