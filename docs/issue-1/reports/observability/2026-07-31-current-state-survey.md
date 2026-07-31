# Current-state survey — observability rulebook (issue-1)

Subject: issue-1. Covers every surface this proposal intends to write to
(the two phase-1 homes: `docs/issue-1/reports/observability/**` and
`docs/issue-1/proposals/**`; and the phase-2 surfaces the proposal will
plan against: `observability/hooks/directive.sh`,
`observability/hooks/hooks.json`, `observability/README.md`,
`docs/issue-1/reports/observability.md`).

## What exists today

- **`observability/.claude-plugin/plugin.json`** (repo root) — plugin
  manifest: name, one-line `decides`/`use_when`/`hand-off` description,
  author. No methodology or required-component content.
- **`observability/hooks/hooks.json`** — one hook only:
  `SessionStart` → `directive.sh`. No `PreToolUse` gate registrations —
  confirmed by reading the file (`observability/hooks/hooks.json`,
  4 lines of content). This matches `docs/issue-2/proposals/2026-07-31-core-canon-reference-switch.md`'s
  task 2 (delete the three local gate copies, rely on core's promoted
  registration) — issue-2's PR (#4, merged per `git log` commit
  `626cc5f`) already landed this switch.
- **`observability/hooks/directive.sh`** — the stub form from issue-2's
  proposal: sources `core/hooks/lib/role-directive.sh` and calls
  `core_role_directive` with exactly four literal strings:
  `you_decide`, `use_when`, `produces`, `hand_off`. `produces` currently
  reads: `"telemetry/instrumentation design, cardinality budget,
  dashboard/query examples"`. This is the only place in the repo that
  names phase-2 deliverable *categories* — and it names them as free
  text with no required internal shape (e.g. "cardinality budget" is
  named but nothing defines what a compliant cardinality budget must
  contain).
- **`observability/README.md`** — layout doc, doctrine restated
  (`decides`/`use_when`/`produces`/`write_scope: []`/`hand-off`),
  install instructions, and a note (added by issue-2) that the
  role-agnostic gates and warrant-hunter are core canon now, not
  vendored here.
- **`docs/specs/approvers.md`** — one entry, `JiwonJung94`; this is the
  only account that can post the `APPROVE issue-1/observability`
  single-account-mode comment (repo has no `.git` remote confirming
  two-account mode is even reachable here — checked: `git log` shows
  author `Jiwon Jung`, and `approvers.md` lists exactly one login, so
  this issue's phase 2 opens via the single-account path per contract
  v3 s19).
- **No prior `docs/issue-1/` tree existed before this session** —
  confirmed via `find docs -type d` returning only `docs/specs` and
  `docs/issue-2/**`. This proposal and survey are issue-1's first
  commits, consistent with s19's "the role's FIRST commits on
  `issue-1/observability` are, before any execution work, research +
  survey + proposal."
- **No `record-fields-gate.sh` copy remains in this repo** (deleted by
  issue-2, task 2) — the generic §20 minimum-field check
  (what-was-done / why / upstream-basis / loop_state / open-findings)
  now runs from core canon
  (`core/hooks/record-fields-gate.sh`, read this session) against
  `docs/issue-<n>/reports/observability.md` on every Write/Edit/MultiEdit,
  and is role-agnostic — it does not know this role's own methodology
  or required deliverable shape. Confirmed by reading
  `core/hooks/record-fields-gate.sh` in full this session: it checks
  only the five generic §20 fields, has no `REQUIRED_FIELDS`-style
  per-role hook, and issue-2's proposal (task 2) explicitly flagged this
  as an open question for core, not something this repo's phase-1
  changes anything about.

## Unknown, stated plainly

- Whether core canon will ever add a per-role `produces`-driven
  required-field mechanism to `record-fields-gate.sh` is unknown — issue-2
  flagged it and did not resolve it. This proposal's plugin-reflection
  plan (section d) therefore does not depend on core adding one; it
  proposes a **role-owned** gate script instead (see proposal), so this
  repo is not blocked on an upstream core decision it does not control.
- Whether any consumer currently reads `directive.sh`'s `produces` string
  for anything beyond display (i.e., whether it is machine-checked
  anywhere today) is unknown — no grep hit in this repo or the sampled
  core checkout ties `produces` to gate logic. Treated as: currently
  advisory text only.

## What this issue's proposal must cover (recap from the issue body)

(a) phase-1 proposal norms (methodology, required sections, evidence
form), (b) phase-2 deliverable norms (methodology, required components),
(c) the adoption rationale for each, (d) the plugin-reflection plan
(directive text / record required fields / gates) — see
`docs/issue-1/proposals/2026-07-31-observability-rulebook-norms.md`.
