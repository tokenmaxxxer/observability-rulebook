# Phase-1 current-state survey: gate A+ residual defects (issue-13)

This is a survey only. No code, hooks.json, README, or manifest file in
this repo has been modified as part of this document.

Scope: the four residual defects named in issue-13's 2026-08-01 re-audit
(grade B+), against this repo's actual files as of the `issue-13/observability`
branch tip.

## 0. Reference shapes landed elsewhere (cited, not redesigned here)

### core issue #75 — `tokenmaxxxer-core` repo, commit `52bdc15`
("deliver(implementation): gate-lib source guard + gate_bash_write_targets
py parity (issue-75) (#77)")

- **Mandatory `||`-guarded source.** `core/hooks/lib/gate-lib.sh:11-18`
  (usage-contract comment) now mandates:
  ```
  . "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}/hooks/lib/gate-lib.sh" || { echo "<gate-name>.sh: cannot source gate-lib.sh" >&2; exit 2; }
  ```
  The comment (`gate-lib.sh:11-14`) names the exact bug this closes: an
  unguarded source that fails when core is unreachable runs no code —
  including no `gate_* ` function definitions — after which every
  `gate_kill_switch_active ... || { exit 0; }` call site reads the
  resulting "command not found" (rc 127) as "kill switch off," silently
  allowing everything. All 7 core gates (`approval-gate.sh`,
  `board-gate.sh`, `directive.sh`, `gh-guard.sh`,
  `handbook-trigger-gate.sh`, `record-fields-gate.sh`, `trailer-gate.sh`)
  were updated to this pattern in the same commit.
- **compliance-check.sh detection.** `core/hooks/tests/compliance-check.sh:51-58`
  adds a structural check: "a gate that sources gate-lib.sh with no `||`
  fallback on the same line" is flagged with the exact reason string
  `"sources gate-lib.sh with no || guard on the same line — fail-open
  when core is unreachable (missing CLAUDE_PLUGIN_ROOT_CORE)"`
  (`compliance-check.sh:58`).
- **Mandatory "missing-core" test case.** `core/hooks/tests/run-gate-lib-tests.sh:230-246`,
  group 7 ("`missing-core -> guarded source must deny, not allow`"),
  included in the mandatory test-name list at line 246
  (`... bash-write-coverage missing-core`).
- **`gate_bash_write_targets` ported to Python.** sh original at
  `core/hooks/lib/gate-lib.sh:86-95` (permissive token scan:
  `grep -oE '[[:alnum:]_./~$-]+'`); Python mirror at
  `core/hooks/lib/gate-lib.py:159-171` (`_BASH_WRITE_TARGET_RE.findall`),
  documented as sh/py parity-tested in the commit message.

**This repo's own gates already use the guarded form.** Every
`gate-lib.sh`/`role-directive.sh` source line in this repo (e.g.
`observability/hooks/observability-produces-gate.sh:2`,
`observability-phase-trace/hooks/phase-trace-gate.sh:2`) is
`. "${CLAUDE_PLUGIN_ROOT_CORE:-...}/hooks/lib/gate-lib.sh"` with **no
trailing `||` guard** — i.e. this repo predates core issue #75's hardened
usage contract and needs to adopt it. See proposal section (e).

### on-the-record issue #182 — `on-the-record-issue-182-implementation`
worktree, commit `e50fe08` ("issue-182: phase 2 — inject
CLAUDE_PLUGIN_ROOT_CORE into role sessions")

- `spawn.py:1983-1989`: `core_dir` is resolved from the same
  `core_plugins`/`core_plugin_dirs()` list already passed to Claude Code
  via `--plugin-dir` (so "injected path" and "actually loaded core plugin
  path" are structurally the same value), then injected as
  `env["CLAUDE_PLUGIN_ROOT_CORE"] = str(core_dir)` (`spawn.py:1985`). If no
  `core` entry is found, `spawn.py:1987-1989` prints a warning to stderr
  rather than silently continuing.
- Comment at `spawn.py:1975-1982` (Korean) states the motivation
  explicitly: without this injection the relative fallback
  (`.../<repo>/../core`) resolves inside the rulebook clone in real
  deployment, and combined with an unguarded source, gates fail open
  across the board.

This repo's own hardcoded fallback path issue (defect 4 below) is the
same shape of problem `spawn.py:1975-1989` was built to prevent in the
*runtime* environment; it does not, by itself, fix a *test file* that
hardcodes a machine-specific absolute path for `CLAUDE_PLUGIN_ROOT_CORE`.

## 1. Defect: status-recording hook still on PreToolUse

`observability-methodology-selector/hooks/hooks.json:10-17` registers
`methodology-selector-gate.sh` on `PreToolUse` with matcher `.*`
(confirmed: `hooks.json:12`, `"matcher": ".*"`).

The state-write itself is at
`observability-methodology-selector/hooks/methodology-selector-gate.sh:208-219`:

```python
# Passing write: best-effort record state for observability-phase-trace to consume later.
m = ISSUE_RE.search(rel)
if m:
    issue_n = m.group(1)
    try:
        state_dir = posixpath.join(root, ".observability-phase1-methods")
        os.makedirs(state_dir, exist_ok=True)
        state_path = posixpath.join(state_dir, "%s.json" % issue_n)
        with open(state_path, "w", encoding="utf-8") as fh:
            json.dump({"issue": issue_n, "methodology_named": True}, fh)
    except OSError:
        pass  # best-effort only; does not fail the gate
sys.exit(0)
```

This runs inside the same `PreToolUse` invocation that also does the
deny/allow judgment (`methodology-selector-gate.sh:200-206`) — i.e. the
state file is written speculatively, *before* Claude Code has actually
committed the tool call. A prior fix (issue-10 era) declared migrating
this off PreToolUse a non-goal; the 2026-08-01 re-audit overturns that:
A+ now requires the write to happen only once the underlying tool call
is known to have actually gone through, which is what `PostToolUse`
guarantees and `PreToolUse` does not (a later PreToolUse gate in the
same chain, or the tool call itself, could still fail after this hook
runs and exits 0).

## 2. Defect: Bash-write bypass (matcher/gate coverage mismatch)

`observability/hooks/hooks.json:10-17`:
```json
"PreToolUse": [
  {
    "matcher": ".*",
    "hooks": [
      { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/observability-produces-gate.sh" }
    ]
  }
]
```
Matcher `.*` (`hooks.json:12`) fires this gate for every tool, including
`Bash`. The same `.*` pattern is used identically across all seven other
sub-plugins' `hooks.json` (`observability-cardinality-budget/hooks/hooks.json:12`,
`observability-explorability/hooks/hooks.json:12`,
`observability-phase-trace/hooks/hooks.json:12`,
`observability-methodology-selector/hooks/hooks.json:12`,
`observability-signal-use/hooks/hooks.json:12`,
`observability-signal-red/hooks/hooks.json:12`,
`observability-signal-golden/hooks/hooks.json:12`).

But the gate code itself, `observability/hooks/observability-produces-gate.sh:93-106`:
```python
path = None
if tool in ("Write", "Edit", "MultiEdit"):
    p = ti.get("file_path")
    if isinstance(p, str) and p:
        path = p
elif tool == "NotebookEdit":
    p = ti.get("notebook_path")
    if isinstance(p, str) and p:
        path = p
if path is None:
    sys.exit(0)
```
For `tool == "Bash"`, `path` stays `None` and the gate exits 0
immediately — a silent passthrough with no path resolution attempted at
all. A `Bash` command that writes `docs/issue-<n>/reports/observability.md`
via shell redirection (e.g. `cat > docs/issue-13/reports/observability.md
<<EOF ... EOF`, or `cp`, `tee`, `sed -i`) is never inspected for the
required produces-shape components (signal methodology, cardinality
budget, ad-hoc query example), even though the matcher was written wide
enough (`.*`) to have caught the `PreToolUse` event.

The identical `if tool in (...)/elif NotebookEdit/else sys.exit(0)`
shape recurs in every sibling gate that shares this file's structure —
confirmed at `observability-phase-trace/hooks/phase-trace-gate.sh:100-109`.
The other four sub-plugin gates (cardinality-budget, explorability,
signal-golden, signal-red, signal-use) follow the same pattern (each
gate's `if tool in ("Write","Edit","MultiEdit")` block, confirmed by the
shared `elif tool == "NotebookEdit": ... if path is None: sys.exit(0)`
idiom present in each file).

core issue #75's `gate_bash_write_targets` (sh: `gate-lib.sh:86-95`; py:
`gate-lib.py:159-171`) is exactly the reference machinery built to close
this class of bug for the role-agnostic core gates. None of this repo's
role-owned gates currently call it.

## 3. Defect: state-file corruption fails OPEN

`observability-phase-trace/hooks/phase-trace-gate.sh:129-138`:
```python
try:
    with open(state_path, encoding="utf-8-sig") as fh:
        state = json.load(fh)
except (OSError, ValueError):
    # State file exists but is unreadable/invalid — treat as no usable state, informational only.
    sys.stderr.write(
        "%s: note — .observability-phase1-methods/%s.json exists but could not be parsed; "
        "phase-trace check skipped (informational only, not a denial).\n" % (role, issue_n)
    )
    sys.exit(0)
```
On a `JSONDecodeError` (subclass of `ValueError`) or `OSError` reading
`.observability-phase1-methods/<issue-n>.json`, the gate writes an
informational note to stderr and then `sys.exit(0)` — i.e. it **allows**
the write to `docs/issue-<n>/reports/observability.md` to proceed with
no phase-trace check at all. This is a genuine fail-open: a corrupted or
truncated state file (e.g. from a crashed writer, a partial disk write,
or an adversarial edit) silently disables the phase-1→phase-2 tracing
norm rather than blocking until the corruption is resolved.

Contrast with the same file's own read-failure handling for the *target*
record a few lines later, `phase-trace-gate.sh:144-150`, which does fail
closed (`deny(...)`) on an `OSError` reading the record itself — i.e.
this file already has both patterns side by side, fail-open for the
state file and fail-closed for the record file, which is the exact
inconsistency issue-13 asks to resolve.

Note also the missing-state-file case one block earlier,
`phase-trace-gate.sh:120-127` — `not os.path.isfile(state_path)` is
correctly treated as "nothing to trace, not a denial" (there is
genuinely no phase-1 state yet, which is not corruption). Only the
except-branch (`132-138`, an existing-but-unreadable file) is the
fail-open defect; the missing-file branch is working as intended and is
out of scope for the fail-closed fix.

## 4. Defect: hardcoded dev-machine paths

Every test harness under `tests/` hardcodes the same absolute,
machine-specific path as either the sole value or the fallback default
for `CLAUDE_PLUGIN_ROOT_CORE`:

- `tests/signal-use-gate.test.sh:5`: `export CLAUDE_PLUGIN_ROOT_CORE="/home/jwjung/tokenmaxxxer/tokenmaxxxer-core/core"`
- `tests/phase-trace-gate.test.sh:5`: same string
- `tests/methodology-selector-gate.test.sh:5`: same string
- `tests/explorability-gate.test.sh:5`: same string
- `tests/observability-produces-gate.test.sh:5`: same string
- `tests/signal-golden-gate.test.sh:5`: same string
- `tests/signal-red-gate.test.sh:5`: same string
- `tests/cardinality-budget-gate.test.sh:5`: `export CLAUDE_PLUGIN_ROOT_CORE="${CLAUDE_PLUGIN_ROOT_CORE:-/home/jwjung/tokenmaxxxer/tokenmaxxxer-core/core}"`
  (this one file already has an env-override fallback pattern; the other
  seven do not — they unconditionally overwrite any pre-set value).

This is the literal absolute path to the author's local checkout of the
`tokenmaxxxer-core` repo. On any other machine, or in CI, this path does
not exist, and every gate test would either fail outright or (worse,
combined with defect-0's unguarded-source finding) silently no-op if the
gate script itself does not yet carry the `||` guard from core issue #75.

No hardcoded dev-machine paths were found inside the gate/hook scripts
themselves (`observability*/hooks/*.sh`) — the hardcoding is confined to
the eight `tests/*.test.sh` harness files.

## 5. Ghost files / stale references in README and manifest

`README.md:44-50` states: "The role-agnostic gates (`trailer-gate.sh`,
`record-fields-gate.sh`, `handbook-trigger-gate.sh`) and the
`warrant-hunter` hunt agent are no longer vendored here." This is stated
correctly as history, not as a present-tense claim that such files exist
in this repo — confirmed no `trailer-gate.sh`, `record-fields-gate.sh`,
`handbook-trigger-gate.sh`, or `warrant-hunter` files exist anywhere
under this repo's `observability*/` directories. No ghost-file
references were found that name a file no longer present as if it were
still present. This item is carried into the proposal (section g) as a
proposed regression lint regardless, per issue-13's instruction to name
every old role name / ghost file and propose a hard-error check — the
survey finds none currently violating it, which the proposal states
explicitly.

## Scouting reference: already-migrated plugins (bounded pass)

See `docs/issue-13/reports/observability/scout-brief.md` for the bounded
scouting pass on how other already-migrated plugins in this repo
(`observability-cardinality-budget`, `observability-explorability`, per
commit `54a9688`) structure gate-lib sourcing, and why none of them
currently has a PostToolUse status hook or fail-closed state handling to
scout from (this repo has exactly one state-writer/state-reader pair,
methodology-selector → phase-trace, both examined above).
