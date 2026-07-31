# Proposal — core canon 참조 전환 (core #63/#66 롤아웃)

Subject: issue-2
Survey: docs/issue-2/reports/implementation/2026-07-31-current-state-survey.md

## What was asked

Issue #2 (5 tasks, one batch):
1. Remove this repo's `agents/warrant-hunter.md` copy and any hunt-cadence
   directive text → replace with a core-canon reference.
2. Remove `trailer-gate.sh` / `record-fields-gate.sh` /
   `handbook-trigger-gate.sh` copies and their hook registrations (core's
   registration replaces them).
3. Replace `directive.sh` with the stub form (source shared function,
   call it, role-unique part only) — role-unique content preserved.
4. If a real role-specific difference exists (e.g. terminal `loop_state`
   set), preserve it explicitly via `RECORD_FIELDS_TERMINAL_STATES`.
5. Confirm `core/hooks/tests/stub-check.sh` passes and record it.

Ordering constraint: this must land before this repo's "rulebook
maturation" phase-2 issue.

## Write set (frozen for phase 2)

- `observability/agents/warrant-hunter.md` — delete
- `observability/hooks/trailer-gate.sh` — delete
- `observability/hooks/record-fields-gate.sh` — delete
- `observability/hooks/handbook-trigger-gate.sh` — delete
- `observability/hooks/directive.sh` — rewrite to stub form
- `observability/hooks/hooks.json` — drop the three deleted gates'
  registrations; keep `directive.sh` under `SessionStart`
- `observability/README.md` — update file-listing section to match
- `docs/issue-2/reports/implementation.md` — phase-2 record (written only
  after Approve, per contract v3 s19; not part of this phase-1 write set)

Out of scope: `warrant/` plugin itself (owned by core issue #63, installed
independently — this repo never vendors it); any change to
`observability/.claude-plugin/plugin.json` or `marketplace.json` (no
dependency declaration needed — core and warrant install alongside this
plugin per contract v3, not as a declared dependency of it).

## Per-task plan

### 1. warrant-hunter copy → core-canon reference

Delete `observability/agents/warrant-hunter.md` outright. It carries no
role-unique content beyond the `decides` line and hand-off arrow, both of
which already live in `observability/hooks/directive.sh`'s payload — deleting
the copy loses no information. Do not add a new file that re-references
`warrant`'s hunter path; a rulebook does not source or point at another
plugin's agent file, it simply stops shipping its own copy. Record the
removal and the reason (issue-66 survey: 43 near-identical copies) in
`observability/README.md`'s layout list.

### 2. Three gate copies → core registration

Delete the three files and remove their three `PreToolUse` entries from
`observability/hooks/hooks.json`, leaving only the `SessionStart` entry
for `directive.sh`. Core's own `core/hooks/hooks.json` already fires
`trailer-gate.sh`, `record-fields-gate.sh`, and `handbook-trigger-gate.sh`
for every plugin install (issue-66), so no gate coverage is lost — only
the duplicate copy and its duplicate registration go away. Note:
`observability`'s local `record-fields-gate.sh` copy encoded this role's
own `REQUIRED_FIELDS` (telemetry-design / cardinality-budget /
dashboard-query-examples) — confirm during phase-2 that core's promoted
version reads this per-role required-field set from somewhere role-owned
(e.g. `roles/observability.json`'s `produces`) rather than dropping it;
this proposal does not change core, so it only flags the check.

### 3. directive.sh → stub form

Replace the current hand-rolled trap/kill-switch/heredoc script with:

```sh
#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/role-directive.sh"
core_role_directive \
  "YOU DECIDE: 프로덕션 내부 상태에 대해 사전에 정의하지 않은 질문도 던질 수 있는가" \
  "USE WHEN: 신규 서비스/경로에 계측이 필요할 때" \
  "PRODUCES: telemetry/instrumentation design, cardinality budget, dashboard/query examples" \
  "HAND-OFF: 장애가 실제로 발생하면 → incident-response"
```

This is the exact form `core/hooks/tests/stub-check.sh` requires: a
source line, a `core_role_directive` call, and no other executable line
(only the four values, which the library call passes as plain
arguments — no separate `VAR=value` assignments are even needed here).
Role-unique content (the four `you_decide`/`use_when`/`produces`/`hand_off`
strings, i.e. this role's actual doctrine) is fully preserved — only the
~15 lines of trap/kill-switch/guard/heredoc boilerplate that issue-66
found duplicated ~43 times are removed. `OBSERVABILITY_CYCLE_OFF` kill-switch
behavior is preserved too: `core_role_directive` derives the same
`<ROLE>_CYCLE_OFF` variable name from `CLAUDE_ROLE` internally.

### 4. RECORD_FIELDS_TERMINAL_STATES — not applicable

Surveyed and confirmed: this repo has no terminal `loop_state` set or any
analogous role-specific record-shape variance that
`RECORD_FIELDS_TERMINAL_STATES` (or an equivalent config knob) would need
to preserve. `observability`'s only role-specific record variance is its
`produces` field list, which is a normal input to core's promoted
`record-fields-gate.sh` (task 2), not a terminal-states question. Record
this explicitly as "checked, not applicable" rather than inventing a
placeholder value — closing task 4 with a negative finding is the
correct outcome here, not silently skipping it.

### 5. stub-check.sh confirmation

Phase 2 must run, from this repo's root:

```sh
/home/jwjung/tokenmaxxxer/tokenmaxxxer-core/core/hooks/tests/stub-check.sh observability/hooks
```

(or the copy distributed alongside `parse-check.sh` once this repo has
one — the core repo's own script is the canonical source per its header).
Expect: `ok` for the three canon-gate absence checks, and `ok — ... is a
role-directive stub` for `directive.sh`. The transcript and verdict go
into `docs/issue-2/reports/implementation.md` in phase 2 (not written now —
phase-1 output is this proposal and the survey only).

## How this will be verified

- `stub-check.sh` exit code 0 against `observability/hooks`.
- `observability/hooks.json` has exactly one hook entry (`directive.sh`
  under `SessionStart`); no `PreToolUse` entries remain.
- `git grep -l warrant-hunter observability/` returns nothing.
- Manual read of the new `directive.sh`: only source line, four literal
  strings, one function call.

## Explicitly out of scope for this batch

- Hardening `handbook-trigger-gate.sh`'s placeholder verdict logic — that
  script is being deleted here, not fixed; any hardening is core's
  concern now.
- Any change to `docs/specs/approvers.md` or this repo's phase-2
  "rulebook maturation" issue — the ordering constraint only says this
  must land first, not that this batch touches that issue's content.
