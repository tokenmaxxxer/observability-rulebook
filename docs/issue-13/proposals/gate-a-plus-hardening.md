# Proposal: gate A+ hardening for residual defects (issue-13)

This is a Phase-1 design proposal only. No code has been modified. Phase
2 implementation requires human approver sign-off per
`docs/specs/approvers.md` before proceeding.

Grounded in `docs/issue-13/reports/observability/current-state-survey.md`
and `docs/issue-13/reports/observability/scout-brief.md`. All file:line
references below are to the survey's citations unless noted otherwise.

## (a) PostToolUse migration for the status-recording hook

**What changes.** In
`observability-methodology-selector/hooks/hooks.json`, add a
`PostToolUse` entry (matcher `.*`, mirroring the existing `PreToolUse`
block's shape) pointing at a state-write step, and remove the
speculative write currently embedded in the `PreToolUse` deny/allow path
at `methodology-selector-gate.sh:208-219`. The `PreToolUse` gate keeps
its deny/allow judgment (the phase-1 produces-shape check itself is
unaffected); only the state-file *write* moves to `PostToolUse`.

Two implementation shapes are viable and phase 2 should pick one, not
both:
1. **Split file.** A second small script,
   `methodology-selector-status.sh`, registered under `PostToolUse`,
   re-derives `issue_n`/`rel` from the `tool_response`/`tool_input` it
   receives (Claude Code's PostToolUse payload includes both) and writes
   `.observability-phase1-methods/<issue_n>.json` only if the tool
   response indicates success (no error field / non-error status).
2. **Shared logic, dual entry point.** Keep one script, branch on
   `$CLAUDE_HOOK_EVENT` (or equivalent env Claude Code sets to
   distinguish PreToolUse/PostToolUse invocations of the same command) —
   only acceptable if Claude Code's hook contract reliably exposes which
   event fired; the survey did not confirm this in-repo, so phase 2 must
   verify it against the current Claude Code hook documentation before
   choosing shape 2 over shape 1.

**Why safe.** `PostToolUse` fires only after the tool call has actually
completed, so the state file will reflect writes that genuinely happened
— closing the exact gap the survey identifies (a PreToolUse-written state
file can describe a write that never completes, e.g. because a later
gate in the same PreToolUse chain still denies it).

**What to watch for.**
- **Ordering.** If the same `hooks.json` also has other `PostToolUse`
  entries in this repo eventually (none currently exist per the scout
  brief), the write step should not assume it runs before or after any
  sibling PostToolUse hook — it should be self-contained and not depend
  on execution order.
- **Idempotency.** `os.makedirs(..., exist_ok=True)` plus an
  unconditional overwrite (`json.dump(...)` truncating the file) is
  already idempotent — re-running PostToolUse for the same completed
  tool call (if Claude Code ever retries hook delivery) produces the
  same state, not a merge or append. Phase 2 should keep this property
  explicitly, not introduce accumulation.
- **Failure isolation.** The existing `except OSError: pass` (best-effort,
  does not fail the gate) is appropriate to keep for PostToolUse too —
  a PostToolUse hook cannot un-do a tool call that already happened, so
  failing closed here would only block subsequent unrelated tool calls
  for no corrective benefit. This is different from the state-file
  *read* side (section c below), which should fail closed.

## (b) Matcher/gate coverage parity (Bash-write bypass)

Two changes, and both should land together rather than either alone:

1. **Gate-side: stop silently exiting on Bash.** In every gate sharing
   the `if tool in ("Write","Edit","MultiEdit"): ... elif
   NotebookEdit: ... if path is None: sys.exit(0)` shape (confirmed at
   `observability-produces-gate.sh:93-106`,
   `phase-trace-gate.sh:100-109`, and the same pattern in the other five
   sub-plugin gates), add a `Bash` branch before the final
   `sys.exit(0)`:
   ```python
   elif tool == "Bash":
       cmd = ti.get("command")
       if isinstance(cmd, str) and cmd:
           for token in gate_lib.gate_bash_write_targets(cmd):
               cand_rel = gate_lib.gate_normalize_path(root, token)
               if cand_rel and RECORD_RE.match(cand_rel):
                   path = token
                   break
   ```
   reusing `gate_bash_write_targets` (Python port at `gate-lib.py:159-171`,
   sh original at `gate-lib.sh:86-95`) exactly as core issue #75 built
   it, rather than hand-rolling a second token scanner. If a Bash command
   is found to target the record path, the gate should treat it the same
   as a Write/Edit hit — but see the caveat immediately below.
2. **Caveat: Bash content is not reliably reconstructible.**
   `gate_reconstruct_write` (`gate-lib.py:87-152`, referenced in the
   survey) only knows how to reconstruct Write/Edit/MultiEdit/NotebookEdit
   tool_input shapes. A `Bash` command that writes the record path (via
   `cat >`, `tee`, `sed -i`, a script, etc.) has no equivalent structured
   `tool_input` to reconstruct content from. The correct behavior once a
   Bash write to the record path is detected is therefore **not** "run
   the same produces-shape content check" but **deny outright** with a
   message directing the author to use Write/Edit/MultiEdit for this
   path, e.g.: `"this Bash command appears to write %s; the produces-shape
   check cannot inspect a Bash-authored write's resulting content — use
   Write/Edit/MultiEdit for this path instead." % rel`. This keeps the
   gate's guarantee (no record ships without the required shape) intact
   without pretending to parse arbitrary shell.
3. **Matcher-side: narrow, don't leave at `.*`.** Once the Bash branch
   above exists, `.*` becomes accurate rather than accidentally-wide —
   but `.*` is still needlessly broad for tools that can never write a
   file (e.g. `Read`, `Grep`, `Glob`, `WebFetch`). Phase 2 should narrow
   every sub-plugin's `hooks.json` `PreToolUse` matcher from `.*` to an
   explicit alternation covering only tools that can write, e.g.
   `"Write|Edit|MultiEdit|NotebookEdit|Bash"`, so the matcher and the
   gate's actual coverage state the same set of tools in two independent
   places (defense in depth: a future gate-code regression that silently
   drops Bash handling would then also require someone to notice and
   widen the matcher back, rather than one silent code change alone
   reopening the bypass).

## (c) Fail-closed design for state-file corruption

In `phase-trace-gate.sh:129-138`, change the `except (OSError, ValueError):`
branch from `sys.exit(0)` (informational, allow) to `deny(...)` (block),
mirroring the fail-closed branch already present four lines later in the
same function for the record file (`phase-trace-gate.sh:149-150`):
```python
except (OSError, ValueError):
    deny(
        ".observability-phase1-methods/%s.json exists but could not be parsed "
        "(corrupt or invalid JSON); failing closed on the phase-trace check "
        "rather than silently skipping it." % issue_n
    )
```
This is a narrow, surgical change to one except-clause; it does **not**
touch the adjacent "file does not exist" branch
(`phase-trace-gate.sh:120-127`), which correctly stays informational —
absence of phase-1 state is a legitimate state (nothing to trace yet),
not corruption. Phase 2 must add a test case distinguishing the two
(missing file → allow with note; malformed/corrupt file → deny) so a
future regression cannot quietly re-merge the two branches.

## (d) Env/config resolution for hardcoded dev paths

Replace the eight `tests/*.test.sh` files' hardcoded
`export CLAUDE_PLUGIN_ROOT_CORE="/home/jwjung/tokenmaxxxer/tokenmaxxxer-core/core"`
with the fallback form already present in one of the eight
(`tests/cardinality-budget-gate.test.sh:5`):
```bash
export CLAUDE_PLUGIN_ROOT_CORE="${CLAUDE_PLUGIN_ROOT_CORE:-<repo-relative-default>}"
```
Design questions phase 2 must resolve, in order:
1. **Env var name.** Reuse `CLAUDE_PLUGIN_ROOT_CORE` itself (already the
   production variable per on-the-record issue #182's `spawn.py:1985`) —
   do not invent a second test-only variable name; a test harness that
   honors the same variable the runtime honors is the whole point of
   making it overridable.
2. **Default when unset.** Two options, and phase 2 should pick based on
   how CI actually checks out the core repo:
   - a sibling-checkout relative default (e.g.
     `"$(cd "$(dirname "$0")/../../core" 2>/dev/null && pwd -P)"`,
     matching each gate script's own existing relative fallback shape
     at e.g. `gate-lib.sh`'s consumer lines), if CI checks out
     `tokenmaxxxer-core` next to this repo; or
   - no default at all — see next point.
3. **Error behavior if unset and unresolvable.** If neither the env var
   nor a discoverable sibling checkout resolves to a directory containing
   `hooks/lib/gate-lib.sh`, the test harness should fail loudly at setup
   time (`echo "... set CLAUDE_PLUGIN_ROOT_CORE to a tokenmaxxxer-core
   checkout" >&2; exit 1`) rather than silently running gate tests against
   a nonexistent path (which — per defect 0/section (e) below, before the
   `||` guard lands — would currently make the gate under test silently
   no-op instead of failing the test suite).

## (e) Applying core issue #75's finalized guard pattern

Reference: `tokenmaxxxer-core/core/hooks/lib/gate-lib.sh:11-18`'s own
usage-contract comment, which gives the exact line shape:
```
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "<gate-name>.sh: cannot source gate-lib.sh" >&2; exit 2; }
```
adjusted for this repo's own relative path shape (`../../core`, one level
deeper than core's own gates, since this repo's gates live at
`<plugin>/hooks/*.sh` not `core/hooks/*.sh`). Phase 2 should append the
`|| { echo "<gate-name>.sh: cannot source gate-lib.sh" >&2; exit 2; }`
clause to the existing source line in all eight gate scripts listed in
the scout brief's Q1 answer (`observability-produces-gate.sh:2`,
`cardinality-budget-gate.sh:2`, `explorability-gate.sh:2`,
`methodology-selector-gate.sh:2`, `phase-trace-gate.sh:2`,
`signal-golden-gate.sh:2`, `signal-red-gate.sh:2`,
`signal-use-gate.sh:2`), and the two `directive.sh`/`role-directive.sh`
source lines that follow the same unguarded shape (e.g.
`observability/hooks/directive.sh:2` and its seven siblings). This is a
mechanical, one-line-per-file change reusing core's finalized pattern
verbatim — no redesign, per the task's instruction to cite and reuse
rather than re-derive.

## (f) Missing-core test case + full suite green + compliance-check

To be executed and recorded in phase 2, not now:
- Add a "missing-core" test case per role gate (mirroring core's own
  `run-gate-lib-tests.sh:230-246` group 7 shape), asserting that pointing
  `CLAUDE_PLUGIN_ROOT_CORE` at a nonexistent path makes the gate **deny**
  (exit 2) rather than silently allow — this only becomes a meaningful
  test once section (e)'s `||` guard has actually landed; writing the
  test first against the current unguarded source lines would either
  fail to compile the source line at all (bash treats a failed `.` as a
  script-level error already, but with no defined exit-code contract) or
  pass vacuously.
- Run the full existing suite (`bash tests/<name>.test.sh` per file) with
  section (d)'s corrected `CLAUDE_PLUGIN_ROOT_CORE` resolution, confirm
  all green, and record the run.
- Run `core/hooks/tests/compliance-check.sh <plugin>/hooks` (referenced,
  not vendored, same invocation shape as `README.md:36-41` already
  documents for this repo) against every one of this repo's eight gate
  scripts and confirm no `"sources gate-lib.sh with no || guard"` finding
  remains once section (e) lands.

## (g) README/manifest cleanup plan

The survey (`current-state-survey.md` section 5) found **no currently
existing ghost-file or stale-role-name references** in
`README.md`/`observability/.claude-plugin/plugin.json` — the one
historical mention of removed files (`trailer-gate.sh`,
`record-fields-gate.sh`, `handbook-trigger-gate.sh`, `warrant-hunter`,
`README.md:44-50`) is phrased correctly as past-tense history ("no
longer vendored here"), not as a present-tense claim, and none of those
filenames exist anywhere in this repo today.

Despite finding nothing to remove right now, issue-13 asks for a
standing hard-error check regardless, so a future edit cannot
reintroduce a stale reference silently. Proposed for phase 2: a small
lint step (either a new `tests/readme-ghost-check.test.sh` or an
addition to an existing compliance pass) that asserts these exact
strings never appear in `README.md`/`observability/.claude-plugin/plugin.json`
as if naming a currently-shipped file — concretely, assert that none of
`trailer-gate.sh`, `record-fields-gate.sh`, `handbook-trigger-gate.sh`,
`warrant-hunter` appears in a `## Layout`-style bullet without the
qualifying phrase "no longer vendored" / "core canon now" nearby, or
more simply: assert the files those names would refer to do not exist
under this repo's `observability*/` trees, which is already true and
would make the check a pure regression guard rather than a fix.
