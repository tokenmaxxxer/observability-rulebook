# Scout brief — issue-7

Mode: parallel-dispatch unavailable in this session for filesystem reads
(Read tool calls are sequential per the harness), so this pass used
**batched-sequential** reads of the two exemplar repos in one turn each —
stated explicitly per the fallback clause. Stages used: 1 (sweep read of
both exemplars' full file lists) + 1 (deepening read of the actual hook
bodies) = 2 of the 5-stage budget. Elapsed: well under the 3-minute
budget (local file reads only, no network).

Angles swept: (1) by-repo — the two rulebooks in this environment already
one step ahead of this one on the exact axis issue-7 asks about
(`implementation-rulebook`, explicitly named by the issue as the quality
bar; `pricing-rulebook`, a sibling role at the same contract version);
(2) by-file-role within each — directive vs gate vs state/ordering vs
tests, to find each of issue-7's four asks in a concrete existing
implementation rather than inventing one from scratch.

## Must-bes (what every exemplar gate has, that this repo's current gate lacks)

- **Directive split by phase, each facet as steps/criteria/prohibitions,
  not one summary line.** `coding/hooks/directive.sh` gives `USE_WHEN`
  four labeled sub-sections (RESEARCH / CURRENT-STATE SURVEY / PROPOSAL
  / ISSUE REFERENCE) and `PRODUCES` a bulleted list of named rules
  (SCOPE-EXCEEDED RULE, HONEST CLAIMS, hunt cadence, etc.), each with a
  concrete criterion or prohibition, not prose. Source:
  `implementation-rulebook/coding/hooks/directive.sh`.
- **The methodology/produces gate covers every write surface the norms
  govern, not just one.** `pricing/hooks/methodology-gate.sh` matches
  both `docs/issue-<n>/proposals/*pricing*.md` (phase-1) and
  `docs/issue-<n>/reports/pricing\.md` (phase-2) with one `PROPOSAL_RE
  | RECORD_RE` pair, and applies the same six-element check to both
  (some elements — "exited early" — only make sense at one phase, but
  the same script owns both surfaces). Source:
  `pricing-rulebook/pricing/hooks/methodology-gate.sh`.
- **Ordering constraints are state, not prose.** When a rulebook has a
  real "X must happen before Y" rule it cannot express as a single
  document's required fields, it tracks it as small on-disk state
  (`hunt-state.sh` writes/clears a lock + count file; `coding-progress-
  gate.sh` reads a *different* role's record to gate a commit). Source:
  `implementation-rulebook/coding/hooks/{hunt-state.sh,hunt-guard.sh,
  coding-progress-gate.sh}`.
- **Gate tests live in the plugin repo, with explicit pass/fail
  fixtures.** `implementation-rulebook/tests/{run-gate-tests.sh,parse-
  check.sh,deny-only-check.sh}` — a repo-root `tests/` directory, not
  bundled inside `hooks/`. Source:
  `implementation-rulebook/tests/*`.
- **Fail-closed trap-at-top + explicit kill switch on every gate.** Both
  exemplars' gates open with the same `__fc` trap-at-top pattern and a
  documented `<ROLE>_..._OFF` kill switch, and both document *why* each
  design choice was made inline (not left implicit). This repo's
  existing `observability-produces-gate.sh` already follows this
  pattern — it is the shape to keep, not to redo.

## Performance axes (where exemplars visibly differ, and this repo must pick a position)

1. **Gate surface breadth**: pricing's gate covers 2 write surfaces in
   one script vs this repo's 1. → adopt: extend, don't duplicate.
2. **Ordering enforcement mechanism**: coding uses a *cross-role*,
   cross-record state check (its own commit gated by another role's
   record); this role has no second role gating it — its ordering need
   is *intra-role, intra-phase* (does the phase-2 record's adopted
   methodology trace to something the phase-1 proposal actually named,
   not invented at phase-2). A full lock/count state file (hunt-state.sh
   pattern) is built for a different problem (bounding concurrent
   dispatches) — skip that mechanism, adopt only the underlying
   principle (state file records what phase-1 committed to, gate reads
   it at phase-2).
3. **Test harness weight**: implementation-rulebook's is three files
   (parse-check, deny-only-check, a runner) tuned to that repo's larger
   gate count. This repo has one role-owned gate (soon two write
   surfaces on it) — a single test script with named pass/fail cases is
   proportionate; a three-script harness would be over-built for one
   gate.

## Adopt / skip

- **Adopt**: split `PRODUCES`/`USE_WHEN` into phase-labeled,
  criterion-bulleted sub-sections (directive depth ask #1).
- **Adopt**: widen `observability-produces-gate.sh`'s regex to also
  match `docs/issue-<n>/proposals/*observability*.md`, applying phase-1's
  three lighter-weight checks (methodology *named*, cardinality *draft*
  mentioned, one-line explorability check) distinct from phase-2's three
  heavier checks (methodology *and* per-signal instrumentation points,
  full budget, ad-hoc query *example* block) (gate coverage ask #2).
- **Adopt, scoped down**: a small state file
  (`.observability-phase1.json` or similar, written by the gate itself
  on a passing phase-1 proposal write, never by the agent directly) that
  the phase-2 check reads to confirm the record's named methodology
  matches what phase-1 committed to — state as a mechanical trace, not a
  concurrency lock (ordering ask #3, scoped per axis 2 above).
- **Adopt**: `tests/` at repo root with named pass/fail fixtures for
  both gate surfaces (tests ask #4).
- **Skip, with reason recorded**: no `agents/` or checklist file. This
  role's phase-1→phase-2 methodology decision is a single per-subject
  judgment call, not a repeated multi-dispatch procedure like
  `warrant-hunter`'s hunt cadence — inventing a checklist agent for a
  process that runs once per issue would be manufacturing repetition
  that does not exist in this role's actual workflow (agents/checklist
  ask #5, addressed by explicit non-adoption + reason, per the issue's
  own "필요 시" qualifier).

## Segment fit

Both exemplars are the same role-handoff contract v3 ecosystem this repo
already conforms to (confirmed: same `core_role_directive` stub form,
same fail-closed trap pattern, same phase-1/phase-2 split) — direct
peers, not aspirational cross-domain references. Copying their
*structure* (not their literal text — no canon-script copying, per
issue-7's constraint) is a same-segment adoption, not a stretch.

## Gap line

This repo already meets: the fail-closed trap-at-top pattern, the
core-stub form for `directive.sh`, kill-switch conventions, and (from
issue-1) phase-2-only produces-shape checking. Missing relative to the
must-bes above: phase-1 proposal-surface gating, per-facet directive
depth, an ordering trace between phase-1 and phase-2, and any gate test
fixtures.

Sources:
- `implementation-rulebook/coding/hooks/directive.sh`
- `implementation-rulebook/coding/hooks/hooks.json`
- `implementation-rulebook/coding/hooks/state.sh`
- `implementation-rulebook/coding/hooks/coding-progress-gate.sh`
- `implementation-rulebook/coding/hooks/hunt-guard.sh`
- `implementation-rulebook/coding/hooks/hunt-state.sh`
- `implementation-rulebook/tests/run-gate-tests.sh`
- `implementation-rulebook/tests/parse-check.sh`
- `implementation-rulebook/tests/deny-only-check.sh`
- `pricing-rulebook/pricing/hooks/directive.sh`
- `pricing-rulebook/pricing/hooks/methodology-gate.sh`
- (all read from local checkouts under `/home/jwjung/tokenmaxxxer/
  rulebooks/`, this session's read-only reference location — not this
  repo, not copied)
