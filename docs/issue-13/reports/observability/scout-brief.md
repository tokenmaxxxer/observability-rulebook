# Scout brief: gate A+ hardening reference shapes (issue-13)

Bounded scouting pass in support of `current-state-survey.md`. Scope: how
core issue #75's guard/rule pattern is meant to be reused here, and how
already-migrated plugins in this repo structure PostToolUse status hooks
and fail-closed state handling. Kept to roughly one page.

## Q1: How should core #75's `||`-guarded source line be adopted?

**Answer, not a skip.** Every gate script in this repo (all eight:
`observability/hooks/observability-produces-gate.sh:2`,
`observability-cardinality-budget/hooks/cardinality-budget-gate.sh:2`,
`observability-explorability/hooks/explorability-gate.sh:2`,
`observability-methodology-selector/hooks/methodology-selector-gate.sh:2`,
`observability-phase-trace/hooks/phase-trace-gate.sh:2`,
`observability-signal-golden/hooks/signal-golden-gate.sh:2`,
`observability-signal-red/hooks/signal-red-gate.sh:2`,
`observability-signal-use/hooks/signal-use-gate.sh:2`) currently sources
`gate-lib.sh` with no trailing `||` guard — one unbroken line per file,
identical shape:
```
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../core" && pwd -P)}/hooks/lib/gate-lib.sh"
```
Reference target: `gate-lib.sh:18`'s own usage-contract comment gives the
exact replacement line (append
`|| { echo "<gate-name>.sh: cannot source gate-lib.sh" >&2; exit 2; }`).
This is a mechanical one-line change per file, reusing the pattern
verbatim rather than redesigning it — see proposal section (e).

## Q2: How do already-migrated plugins in this repo (commit `54a9688`)
structure a PostToolUse status hook?

**Skip — none exists, reason given.** Surveyed all seven
`observability-*` sub-plugins' `hooks/hooks.json`
(`observability-cardinality-budget/hooks/hooks.json`,
`-explorability`, `-methodology-selector`, `-phase-trace`,
`-signal-golden`, `-signal-red`, `-signal-use`): every one registers its
gate under `PreToolUse` only (`"PreToolUse": [...]`, matcher `.*`, at
line 10-12 of each file). None registers anything under `PostToolUse`.
The only status-writing hook in this repo is
`observability-methodology-selector/hooks/methodology-selector-gate.sh:208-219`,
itself on `PreToolUse` — i.e. it is the thing defect 1 asks to migrate,
not a working example to copy from. There is no in-repo PostToolUse
precedent to scout; the proposal (section a) has to design this from
Claude Code's documented PostToolUse hook contract directly rather than
by analogy to a sibling plugin.

## Q3: How do already-migrated plugins structure fail-closed state
handling?

**Partially answered by in-repo material already read for the survey,
no further scouting needed.** The one state-reader in this repo,
`observability-phase-trace/hooks/phase-trace-gate.sh`, already
demonstrates both patterns in the same file: fail-closed on the *record*
file's own read failure (`phase-trace-gate.sh:149-150`,
`deny("%s exists but cannot be read; failing closed on the phase-trace check.")`)
and fail-open on the *state* file's corruption (`phase-trace-gate.sh:132-138`,
the defect). The fail-closed idiom to extend to the state-file branch is
therefore already present verbatim two branches later in the same
function — no external plugin needs to be scouted for a fail-closed
`deny()` shape; `gate_deny` (`gate-lib.sh:77-80`) is the one canonical
primitive both branches should call.

## Q4: Env/config resolution pattern for hardcoded paths — is there a
scouting need?

**Skip — spec fully determined by on-the-record issue #182 already cited
in the survey.** `spawn.py:1983-1989` (in
`on-the-record-issue-182-implementation`, commit `e50fe08`) is the
canonical shape for resolving `CLAUDE_PLUGIN_ROOT_CORE` from the
environment with an explicit warn-on-missing branch, already fully
covered in `current-state-survey.md` section 0. The test-harness fix
(defect 4) is a narrower instance of the same idea (env var with
fallback, not unconditional overwrite) and does not need a second
external reference — `tests/cardinality-budget-gate.test.sh:5`'s own
`"${CLAUDE_PLUGIN_ROOT_CORE:-/home/jwjung/...}"` fallback form is already
the right shape for the other seven test files to converge on (the
proposal's job is only to make the *default* itself non-machine-specific
— see proposal section d).

## Sources (file:line actually read)

- `tokenmaxxxer-core/core/hooks/lib/gate-lib.sh:1-95` (full file)
- `tokenmaxxxer-core/core/hooks/lib/gate-lib.py:159-171`
- `tokenmaxxxer-core/core/hooks/tests/compliance-check.sh:1-15,51-58,60-70`
- `tokenmaxxxer-core/core/hooks/tests/run-gate-lib-tests.sh:165,230-246`
- `on-the-record-issue-182-implementation/spawn.py:1960-1990`
- `observability/hooks/hooks.json:1-20`
- `observability/hooks/observability-produces-gate.sh:1-208` (full file)
- `observability-phase-trace/hooks/phase-trace-gate.sh:100-159`
- `observability-methodology-selector/hooks/methodology-selector-gate.sh:195-232`
- `observability-cardinality-budget/hooks/hooks.json`,
  `-explorability/hooks/hooks.json`, `-signal-golden/hooks/hooks.json`,
  `-signal-red/hooks/hooks.json`, `-signal-use/hooks/hooks.json`
  (matcher/section lines only)
- `README.md:1-106` (full file)
- `tests/*.test.sh:5` (all eight files, the `CLAUDE_PLUGIN_ROOT_CORE`
  export line only)
