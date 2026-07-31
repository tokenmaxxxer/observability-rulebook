Subject: issue-2

# Implementation record — core canon reference switch

Proposal: docs/issue-2/proposals/2026-07-31-core-canon-reference-switch.md
Approval: single-account mode, issue comment `APPROVE issue-2/implementation`
by JiwonJung94 (listed in docs/specs/approvers.md).

loop_state: landed

## What was done

1. Deleted `observability/agents/warrant-hunter.md`. No role-unique content
   lost — the `decides`/hand-off text already lives in `directive.sh`'s
   stub call. `warrant`'s hunter now installs independently (core #63);
   this repo never referenced or vendored it beyond that one file.
2. Deleted `observability/hooks/trailer-gate.sh`,
   `record-fields-gate.sh`, `handbook-trigger-gate.sh`, and removed their
   `PreToolUse` entries from `observability/hooks/hooks.json`. Core's
   `core/hooks/hooks.json` fires all three for every plugin install
   (core #66); `hooks.json` here now carries only the `SessionStart` →
   `directive.sh` entry.
3. Rewrote `observability/hooks/directive.sh` to the stub form: sources
   `core/hooks/lib/role-directive.sh` and calls `core_role_directive`
   with this role's four values (`you_decide`, `use_when`, `produces`,
   `hand_off`) on a single line — `stub-check.sh`'s structural check
   treats a multi-line backslash-continued call as regrown boilerplate,
   so the call had to stay one line to pass. `OBSERVABILITY_CYCLE_OFF`
   kill-switch behavior is preserved: `core_role_directive` derives the
   same `<ROLE>_CYCLE_OFF` name from `CLAUDE_ROLE` internally.
4. `RECORD_FIELDS_TERMINAL_STATES` — confirmed not applicable, per the
   proposal's survey: this repo has no terminal `loop_state` set or
   analogous record-shape variance. This role's only record-shape
   variance is its `produces` field list, which is a normal input to
   core's promoted `record-fields-gate.sh`, not a terminal-states
   question. Closing this task with that negative finding, not a
   placeholder.
5. Updated `README.md`'s layout list to match (drop the four removed
   files, note why, point at the proposal).

## Why (rationale)

Core landed a single canon for role-agnostic hunt/gate logic (core
issue #63/#66): 43 near-identical `warrant-hunter.md` copies and
role-agnostic gate scripts had drifted to 38/40 unique hashes across
rulebooks. This repo's own copies were exactly that drift. Removing them
and switching `directive.sh` to the shared-library stub form closes this
repo's part of that consolidation, per the issue-2 task list and the
already-approved phase-1 proposal — this record's upstream basis.

## Upstream basis

docs/issue-2/proposals/2026-07-31-core-canon-reference-switch.md (this
subject's own approved phase-1 proposal), which is itself based on:
core issue #63 (warrant plugin canon), core issue #66 (role-agnostic
gate canon + stub-check.sh), and this repo's own
docs/issue-2/reports/implementation/2026-07-31-current-state-survey.md.

## Verification

`stub-check.sh` run from repo root against `observability/hooks`:

```
$ bash <core>/hooks/tests/stub-check.sh observability/hooks
stub-check: ok — no vendored 'trailer-gate.sh' under observability/hooks
stub-check: ok — no vendored 'record-fields-gate.sh' under observability/hooks
stub-check: ok — no vendored 'handbook-trigger-gate.sh' under observability/hooks
stub-check: ok — no vendored 'parse-check.sh' under observability/hooks
stub-check: ok — observability/hooks/directive.sh is a role-directive stub
$ echo $?
0
```

Also checked, per the proposal's "how this will be verified" list:

- `observability/hooks.json` (`hooks.json`) has exactly one hook entry
  (`directive.sh` under `SessionStart`); confirmed by reading the file.
- `git grep -l warrant-hunter observability/` returns nothing (exit 1,
  no match).
- `bash -n observability/hooks/directive.sh` — syntax ok.
- Manual read of `directive.sh`: one source line, one `core_role_directive`
  call carrying the four literal strings, no other executable line.

## Open findings

- Phase-2 of core issue #66 (not this repo's concern) should confirm
  core's promoted `record-fields-gate.sh` reads this role's own
  `REQUIRED_FIELDS` (telemetry-design / cardinality-budget /
  dashboard-query-examples) from a role-owned source (e.g.
  `roles/observability.json`'s `produces`) rather than dropping the
  per-role required-field set the deleted local copy used to encode.
  This repo does not change core; it only flags the check, per the
  proposal's task 2 note.
- No other open findings. All five issue tasks closed; `stub-check.sh`
  passes; write set matches the frozen phase-1 list exactly.

Record status: landed. All five tasks in the issue closed, verification
passed, this record committed on `issue-2/implementation` for PR review.
No further work expected on this subject unless the open finding above
(core #66's own concern) triggers a follow-up issue.
