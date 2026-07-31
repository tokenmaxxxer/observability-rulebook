# Current-state survey — issue-2

Scout skip record: pure internal architecture refactor against a fully
specified issue body (5 concrete tasks, no product-facing decision open) —
skipping the scout sweep per scout-directive's skip condition 2.

## This repo (observability-rulebook), as landed by issue-167

- `observability/agents/warrant-hunter.md` — full copy of the hunt agent
  prompt, explicitly labeled "adapted from implementation-rulebook's
  `agents/warrant-hunter.md`". Role-unique content: only the `decides`
  line and the hand-off arrow; everything else (stances, output format,
  bounds, record shape) is generic hunter doctrine.
- `observability/hooks/trailer-gate.sh`, `record-fields-gate.sh`,
  `handbook-trigger-gate.sh` — each file says in its own header comment
  that it is role-agnostic logic with only the role name substituted
  (`observability: refused —`, `OBSERVABILITY_CYCLE_OFF`, `REQUIRED_FIELDS`
  in record-fields-gate.sh, and a path suffix check). All three are wired
  in `observability/hooks/hooks.json` under `PreToolUse`.
- `observability/hooks/directive.sh` — hand-written SessionStart script:
  trap/kill-switch/CLAUDE_ROLE-guard boilerplate plus a `cat <<DIRECTIVE`
  heredoc with the role's four directive values baked directly into text.
- `observability/hooks/hooks.json` registers all four hook files
  (directive.sh under SessionStart; the three gates under PreToolUse).

## Core canon (tokenmaxxxer-core, local checkout), what it now owns

- `core/hooks/lib/role-directive.sh` — sourceable library exposing
  `core_role_directive <you_decide> <use_when> <produces> <hand_off>`.
  A rulebook's directive.sh is meant to shrink to: source this file, set
  four values, call the function. Nothing else — enforced structurally.
- `core/hooks/trailer-gate.sh`, `record-fields-gate.sh`,
  `handbook-trigger-gate.sh` — now core hooks, registered in core's own
  `hooks.json`, firing for every plugin install regardless of which
  rulebook is active. A per-rulebook copy is drift, not a stub.
- `core/hooks/tests/stub-check.sh` — the enforcement mechanism (issue-66
  item 4). Run as `stub-check.sh <hooks-dir>`:
  - FAILs if any of `trailer-gate.sh`, `record-fields-gate.sh`,
    `handbook-trigger-gate.sh`, `parse-check.sh` exist anywhere under the
    target hooks tree (depth <=3).
  - For `directive.sh`: structural check, not absence-based. Passes only
    if the file sources `role-directive.sh`, calls `core_role_directive`,
    and every other non-blank/non-comment/non-shebang line is a plain
    `VAR=value` assignment — any case/if/echo/cat is treated as regrown
    boilerplate and fails.
- `warrant/` — a separate, independently installable plugin (core issue
  #63) supplying its own `agents/warrant-hunter.md`, its own hooks
  (`directive.sh`, `hunt-guard.sh`, `hunt-state.sh`, `scope-gate.sh`), and
  its own `hooks.json`. It is not something a rulebook vendors or sources;
  it is installed alongside a rulebook's own plugin per contract v3, the
  same way `core` itself is. observability's fix here is to stop shipping
  its own hunter copy, not to add a reference to warrant's file.

## Gaps / unknowns this proposal must close

- No `RECORD_FIELDS_TERMINAL_STATES`-shaped mechanism exists yet anywhere
  in core's `record-fields-gate.sh` — the issue's task 4 asks this repo to
  set that variable *if* a real role-specific difference exists. Surveyed:
  observability's own `record-fields-gate.sh` copy hardcodes
  `REQUIRED_FIELDS = ["telemetry-design", "cardinality-budget",
  "dashboard-query-examples"]`, which is exactly this role's `produces`
  line — not a loop-terminal-state concept at all. No evidence in this
  repo of any loop/terminal-state field to preserve. This is a
  configuration knob for a *different* kind of role variance (the issue
  text names "종료 loop_state 집합" as the example) that observability
  does not have — the proposal must state this as "not applicable" rather
  than invent one.
- `handbook-trigger-gate.sh` in this repo is already an unhardened
  placeholder (`exit 0 # placeholder verdict`) with a comment saying a
  report-only role (`write_scope: []`) may not need this gate "at all" —
  relevant to whether removing it entirely (vs. relying on core's copy)
  changes any behavior here: it does not, since the local copy never
  denies anything today.
