# Phase-2 record: gate A+ hardening via core gate-lib adoption (issue-10)

Approved by `APPROVE issue-10/observability` (single-account mode, JiwonJung94,
docs/specs/approvers.md). Implements
`docs/issue-10/proposals/2026-08-01-gate-a-plus-hardening.md` conservatively,
against the defects catalogued in
`docs/issue-10/reports/observability/2026-08-01-current-state-survey.md`.

## What changed

All eight `*-gate.sh` scripts (`observability/hooks/observability-produces-gate.sh`
and the seven `observability-*/hooks/*-gate.sh` scripts) now source
`core/hooks/lib/gate-lib.sh` / `gate-lib.py` (referenced via
`CLAUDE_PLUGIN_ROOT_CORE`, never vendor-copied) instead of hand-rolling:

- **Trap-at-top** — `gate_trap_fail_closed` replaces the per-gate `__fc`/`trap` pair.
- **Kill switch** — `gate_kill_switch_active` replaces the
  `case ... in ""|0|false|no|off) ;; *) exit 0 ;; esac` pattern that treated
  every unrecognized value (including typos) as "disable" (survey §2c, the
  confirmed defect). Every gate keeps its own env var name unchanged.
- **Malformed-JSON deny** — `gate_lib.gate_parse_json_or_deny` replaces the
  `if raw else {}` + `isinstance` dance (survey §2b); denies directly on
  empty/unparseable/non-dict payload rather than via a downstream side effect.
- **Path normalization** — `gate_lib.gate_normalize_path` replaces each
  gate's own `resolve()` + prefix-strip, and the `_under()` bash pre-filter
  now calls through the same function instead of its own copy (survey §1:
  two independently-maintained copies of the same algorithm collapse to one).
- **Edit/MultiEdit/replace_all/NotebookEdit reconstruction** —
  `gate_lib.gate_reconstruct_write` replaces each gate's hardcoded
  `.replace(o, n, 1)` chain (survey §3's confirmed `replace_all`-skipped
  defect) and adds `NotebookEdit` cell-source reconstruction, previously
  unhandled by any of the eight gates.

## Semantic check overhaul (issue defect #2)

`has_any()` flat whole-document substring matching (survey §5) replaced per
gate per the proposal's assignment table:

| Gate | Primitive |
|---|---|
| `observability-produces-gate.sh` | Section-scoped, 3 sections (methodology/cardinality/ad-hoc) |
| `cardinality-budget-gate.sh` | Structural (per-dimension policy pairing); same-line placeholder check kept as-is |
| `explorability-gate.sh` | Adjacency-scoped (same-paragraph / 3-line window) |
| `methodology-selector-gate.sh` | Section-scoped, bounded-window fallback as primary path |
| `phase-trace-gate.sh` | Adjacency-scoped (the issue's most literal named complaint) |
| `signal-golden-gate.sh` / `signal-use-gate.sh` | Section-scoped for signal-presence checks; whole-doc trigger check kept as-is |
| `signal-XX-gate.sh` (rate/errors/duration methodology, one gate) | Section-scoped for signal-presence checks; whole-doc trigger check kept as-is |

Needle vocabulary is unchanged in every gate — only where in the document a
needle must be found changed.

## Test suite

Each gate's `tests/*.test.sh` extended with the six mandatory case groups
(issue requirement #3 / proposal §e): Edit shape, MultiEdit shape,
`replace_all` (Edit + MultiEdit, multiply-occurring `old_string`), malformed
JSON (truncated / non-object / empty stdin, 3 sub-cases), kill-switch
(on/off/garbage, 3 sub-cases), absolute-path + `./`-relative-path variants.
`tests/observability-produces-gate.test.sh` created from scratch (survey §6's
zero-coverage gap for the role-owned gate).

Full suite run (`bash tests/<name>.test.sh` per file, `CLAUDE_PLUGIN_ROOT_CORE`
pointed at the local core checkout):

| File | Result |
|---|---|
| `observability-produces-gate.test.sh` | 17 passed, 0 failed |
| `cardinality-budget-gate.test.sh` | 21 passed, 0 failed |
| `explorability-gate.test.sh` | 22 passed, 0 failed |
| `methodology-selector-gate.test.sh` | 20 passed, 0 failed |
| `phase-trace-gate.test.sh` | 22 passed, 0 failed |
| `signal-golden-gate.test.sh` | 20 passed, 0 failed |
| `signal-XX-gate.test.sh` (the third signal plugin's own suite) | 18 passed, 0 failed |
| `signal-use-gate.test.sh` | 19 passed, 0 failed |

**All eight files: fail=0.** Two pre-integration bugs were caught and fixed
during this verification pass, both in test fixtures, not gate logic
(confirmed by reading each gate's own semantic-check code before touching the
fixture): one Edit-shape fixture dropped its own trigger word when
the Edit's `new_string` replaced the line carrying it, and one gate's three
kill-switch cases called the harness `report()` helper with its `name` and
`got` arguments swapped.

## Compliance-check

`core/hooks/tests/compliance-check.sh` run against this repo's `hooks/`
tree — all eight gates pass (rc=0, no gate flagged for a hand-rolled
kill-switch or a hand-rolled write-reconstruction call):

```
compliance-check: ok — observability-phase-trace/hooks/phase-trace-gate.sh
compliance-check: ok — observability-signal-golden/hooks/signal-golden-gate.sh
compliance-check: ok — (third signal plugin's gate script)
compliance-check: ok — observability-signal-use/hooks/signal-use-gate.sh
compliance-check: ok — observability-explorability/hooks/explorability-gate.sh
compliance-check: ok — observability-methodology-selector/hooks/methodology-selector-gate.sh
compliance-check: ok — observability-cardinality-budget/hooks/cardinality-budget-gate.sh
compliance-check: ok — observability/hooks/observability-produces-gate.sh
```

## README

Root `README.md` realigned per proposal §f: added a "Plugins" section listing
all eight plugin directories with links to their own READMEs, a table of all
eight `*_GATE_OFF` kill-switch env vars with the record/proposal path each
gates, and a paragraph stating every gate now sources `gate-lib.sh`/`gate-lib.py`
per the gate-house standard (referenced, not vendor-copied). No ghost-file removal
needed (none found in the survey) — purely additive.

## Non-goals kept as-is (per proposal)

Each gate's own record/proposal path pattern, needle vocabulary, denial
message text, and kill-switch env var name; the
`.observability-phase1-methods/<issue-n>.json` state-file contract between
`methodology-selector-gate.sh` and `phase-trace-gate.sh`; `gate-lib.sh`/
`gate-lib.py` themselves (referenced only, never vendor-copied).

## What was done

Summary of work done this phase: all eight gates migrated to
`core/hooks/lib/gate-lib.sh`/`gate-lib.py`, the semantic checks reworked
from whole-document substring matching to the section/adjacency/structural
primitives above, the six mandatory test-case groups added to every gate's
suite, the root README realigned, and `compliance-check.sh` run clean.

## Why

Rationale: the phase-1 proposal
(`docs/issue-10/proposals/2026-08-01-gate-a-plus-hardening.md`), approved by
`APPROVE issue-10/observability`, committed this repo to adopting core's
shared gate library and closing the confirmed defects the current-state
survey documented (kill-switch fail-open, `replace_all` ignored, whole-doc
substring semantic checks, zero test coverage on the role-owned gate).

## Upstream basis

Based on: `docs/issue-10/proposals/2026-08-01-gate-a-plus-hardening.md` and
`docs/issue-10/reports/observability/2026-08-01-current-state-survey.md`,
against core canon `core/hooks/lib/gate-lib.sh`/`gate-lib.py` and
`docs/handbooks/gate-house-standard.md` (core issue #72).

## Status

loop_state: landed

## Open findings

None outstanding — the full test suite is green and `compliance-check.sh`
passes on all eight gates.
