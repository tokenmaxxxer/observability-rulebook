# Current-state survey — issue-7

Subject: issue-7. What this role's plugin already has, before proposing
what issue #7 asks to add.

## Write surfaces that exist today

- `observability/hooks/directive.sh` — core stub form (source line + one
  `core_role_directive` call). `PRODUCES` is already a single string
  naming the three (b) categories from issue-1's proposal
  (telemetry/instrumentation design, cardinality budget, dashboard/query
  examples) with their required components, but as continuous prose —
  no per-facet stage/criteria/prohibition breakdown, and phase-1 vs
  phase-2 are not separated inside `PRODUCES` at all (`USE_WHEN` carries
  no phase-1 method text either).
- `observability/hooks/hooks.json` — one `SessionStart` entry
  (`directive.sh`) and one `PreToolUse` entry
  (`observability-produces-gate.sh`, matcher `.*`).
- `observability/hooks/observability-produces-gate.sh` — checks exactly
  one write surface: `docs/issue-<n>/reports/observability.md` (the
  **phase-2 record**). It does not touch
  `docs/issue-<n>/proposals/*observability*.md` (the phase-1 proposal) at
  all — a phase-1 proposal that never names a methodology, never sketches
  a cardinality budget, and never states an explorability check passes
  through untouched. Confirmed by reading the file: the `RECORD_RE`
  regex is `^docs/issue-[0-9]+/reports/observability\.md$` only.
- No ordering/state file exists anywhere under `observability/hooks/` —
  nothing tracks whether a survey exists before a proposal is written, or
  whether the proposal's adopted methodology traces to stated evidence
  before phase-2 begins. `git ls-files observability/hooks` returns
  exactly the three files above; no `state.sh`, no lock file, no
  `.claude-plugin`-adjacent tracking artifact.
- No `tests/` directory exists anywhere in this repo (`find . -iname
  tests` returns nothing) — the gate has never had a pass/fail test
  case, per the issue-1 record's own "open finding" (manual execution
  was sandboxed out of that session; the JSON/`bash -n` checks were the
  only verification that landed).
- No `agents/` directory exists (issue-2 already deleted the
  `warrant-hunter.md` copy; this repo has never had a role-owned agent
  file since).
- `observability/README.md` lists the three hook files and the
  `produces` categories at prose level; it does not describe a gate on
  the proposal surface or any ordering state.

## What issue-7 is asking for, mapped onto this gap

1. **Directive depth** — issue-1's `PRODUCES` string names the three
   categories and their components but reads as one paragraph per
   category, not the stage/criteria/prohibition structure
   `implementation-rulebook`'s `coding/hooks/directive.sh` uses (see
   scout-brief for the concrete shape). Phase-1 vs phase-2 facets are
   not separated in `USE_WHEN`/`PRODUCES` the way a two-phase contract
   needs.
2. **Methodology gate coverage gap** — the existing gate only fires on
   the phase-2 record. A phase-1 proposal with none of the three (b)
   elements currently passes the gate silently; the mismatch is directly
   visible in the regex above.
3. **No ordering enforcement** — issue-1's (a) norms require "신호 선택
   방법론 명시" and a cardinality *draft* at phase-1, refined at phase-2.
   Nothing today checks that a phase-2 record's adopted methodology
   traces back to a phase-1 proposal that named one — the two documents
   are gated independently (and currently, only one of the two is gated
   at all).
4. **No gate tests** — issue-1's own record flags this as an open
   finding; issue-7 asks for it explicitly.
5. **Agents/checklist** — surveyed for a repeated procedure analogous to
   `warrant-hunter`'s hunt cadence: this role's produces norms (RED/
   USE/Golden-Signals selection, a cardinality budget, one ad-hoc query)
   are a **single per-subject judgment**, made once per issue at
   phase-1 and refined once at phase-2 — there is no "dispatch N times
   per session" cadence for this role to track. This gap is addressed in
   the proposal by naming it explicitly rather than fabricating a
   procedure that does not exist.

## Reference material read (read-only, canon/exemplar — not this repo)

- `implementation-rulebook/coding/hooks/{directive.sh,hooks.json,
  state.sh,coding-progress-gate.sh,hunt-guard.sh,hunt-state.sh}` —
  the "hook machine" implementation-rulebook example the issue names as
  the target quality bar.
- `pricing-rulebook/pricing/hooks/{directive.sh,methodology-gate.sh}` —
  a sibling rulebook already one step ahead of this repo: its
  methodology gate covers *both* the phase-1 proposal surface
  (`docs/issue-<n>/proposals/*pricing*.md`) and the phase-2 record
  surface in one script, with six required elements.

Full detail and adopt/skip decisions: see
`docs/issue-7/reports/observability/scout-brief.md`.
