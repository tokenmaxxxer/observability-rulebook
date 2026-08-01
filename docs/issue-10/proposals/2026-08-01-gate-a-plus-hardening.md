# Proposal: gate A+ hardening via core gate-lib adoption (issue-10)

Phase-1 design doc. No code in this repo changes as part of this
document — the survey
(`docs/issue-10/reports/observability/2026-08-01-current-state-survey.md`)
is the evidence base every claim below cites back to. This is a
conservative refactor plan, not a rewrite spec: every one of the eight
gate scripts keeps its own file, its own record path, its own needle
vocabulary, and its own kill-switch name; only the trap/kill-switch/
path-normalize/reconstruct/deny machinery moves from eight hand-rolled
copies to one shared call each, per the precondition landed in core
issue #72.

## Scout grounding

Three angles, pulled from the precondition library sitting right at
hand rather than external search, since the "field" here IS
`core/hooks/lib/gate-lib.sh`/`gate-lib.py` plus the gate-house standard
doc:

1. **Sourcing convention.** `gate-lib.sh`'s own header comment
   (`/tmp/claude-1000/core-check/core/hooks/lib/gate-lib.sh:11-13`) gives
   the exact line every migrated gate should use:
   `. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}/hooks/lib/gate-lib.sh"`.
   `core/hooks/approval-gate.sh:37-38` is a landed example doing exactly
   this, immediately after the trap line and before `set -uo pipefail` —
   the same position this repo's eight gates currently give their
   hand-rolled `__fc`/`trap` pair
   (survey §2a, e.g. `observability/hooks/observability-produces-gate.sh:1-3`).
   `approval-gate.sh:41` then calls `gate_kill_switch_active "${CORE_OFF:-}" || { trap - EXIT; exit 0; }`
   right after sourcing — the exact call-shape §b below reuses per gate,
   substituting each gate's own `*_GATE_OFF` var name for `CORE_OFF`.
2. **Python-payload loading convention.** `gate-lib.py`'s own header
   comment
   (`/tmp/claude-1000/core-check/core/hooks/lib/gate-lib.py:6-10`) gives
   the `importlib.util.spec_from_file_location` + `GATE_LIB_PY` env var
   pattern; `gate-lib.sh:28-29` exports `GATE_LIB_PY` as the sibling
   file's path so a sourcing gate's own heredoc-Python payload can load
   it without a package import. This repo's eight gates already run
   their content-judging logic inside a `python3 <<'PY' ... PY` heredoc
   fed via env vars (survey §2b/§3, e.g.
   `observability-produces-gate.sh:68-69`,
   `OG_PAYLOAD="$payload" OG_ROOT="$root" OG_ROLE="$role" python3 <<'PY'`)
   — the same env-var-into-heredoc idiom `GATE_LIB_PY` slots into with one
   more line (`GLPY="$GATE_LIB_PY"` added to that same env-var prefix).
3. **What already-migrated core gates DON'T change.** `approval-gate.sh`'s
   own `deny()`/`allow()` wrapper functions inside its Python payload
   (lines 64-69) are role-specific enough (custom messages, `DENY = 2`
   naming) that the file keeps its own local `deny`/`allow` wrappers
   rather than calling `gate_lib.gate_deny`/`gate_allow` directly inside
   the heredoc — those are bash-level functions in `gate-lib.sh`
   (`gate-lib.sh:70-79`), not exposed to a nested Python payload. The
   working pattern in a landed core gate is: bash-level `gate_deny`/
   `gate_allow` used directly when the whole gate never needs Python
   (not this repo's case — every one of the eight gates here needs
   Python for JSON/content judgment), OR the Python payload keeps its own
   thin `deny(msg)`/`allow()` that call `sys.exit(2)`/`sys.exit(0)`
   after writing to stderr — semantically identical to `gate_deny`/
   `gate_allow` but callable from inside the heredoc without a bash/
   Python boundary crossing per call. This repo's migration follows the
   second shape: the bash frame calls `gate_trap_fail_closed` and
   `gate_kill_switch_active` directly (no Python needed for those two),
   and the Python payload keeps a local `deny()`/`allow()` pair whose
   bodies are now one-line calls into `gate_lib.gate_parse_json_or_deny`
   /`gate_lib.gate_normalize_path`/`gate_lib.gate_reconstruct_write`
   instead of hand-rolled equivalents — see §a-§c.

## (a) Absolute-path normalization per gate

Every gate's `resolve()` function (survey §1, eight near-identical
copies, e.g. `observability-produces-gate.sh:95-102`) is replaced by a
single call:

```python
rel = gate_lib.gate_normalize_path(root, path)
if rel is None:
    sys.exit(0)  # resolves outside root: not this gate's business
```

`gate_normalize_path` (`gate-lib.py:39-66`) already handles absolute,
relative, and `./`-prefixed inputs uniformly and returns a root-relative
tail directly comparable against each gate's own `RECORD_RE`/
`PROPOSAL_RE` pattern (no `r.startswith(root + "/")` + manual
`rel = r[len(root):].lstrip("/")` dance — that two-step, repeated at
e.g. `observability-produces-gate.sh:116-118`, collapses into the one
call above). The `_under()` bash pre-filter that currently duplicates
this logic a second time to pick `root` (survey §1) is retired the same
way: `gate-lib.py` is loaded once and `gate_normalize_path` is the only
normalize path, so there is exactly one algorithm instead of two that
must independently agree. `gate_normalize_path`'s docstring
(`gate-lib.py:44-56`) is explicit that it does pure string/path algebra
with no filesystem symlink resolution — callers needing symlink safety
still realpath their own `root` first, which every gate here already
does when computing `root` from `CLAUDE_PROJECT_DIR`/`git rev-parse
--show-toplevel` (unchanged from today).

## (b) Fail-closed trap-at-top / malformed-JSON-deny / kill-switch-unrecognized-enforces

Each gate's first three lines become:

```bash
#!/usr/bin/env bash
. "${CLAUDE_PLUGIN_ROOT_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}/hooks/lib/gate-lib.sh"
gate_trap_fail_closed
set -uo pipefail
gate_kill_switch_active "${OBSERVABILITY_PRODUCES_GATE_OFF:-}" || { trap - EXIT; exit 0; }
```

replacing the current `__fc`/`trap __fc EXIT` pair (survey §2a) and the
`case ... esac` kill-switch block (survey §2c) — the exact wildcard-arm
bug `gate_kill_switch_active` (`gate-lib.sh:61-67`) was built to close:
only `1`/`true`/`yes`/`on` (case-insensitive) disable; every off-spelling
AND every unrecognized value stays active. Each gate keeps its own env
var name (`OBSERVABILITY_PRODUCES_GATE_OFF`,
`OBSERVABILITY_METHODOLOGY_SELECTOR_GATE_OFF`, etc.) — only the check
function changes, not the eight kill-switch names or the README lines
that document them.

Inside the Python payload, the current two-step "if raw else {}" +
`isinstance(ev, dict)` dance (survey §2b) is replaced by one call:

```python
ev = gate_lib.gate_parse_json_or_deny(raw, deny)
```

`gate_parse_json_or_deny` (`gate-lib.py:19-36`) denies directly on
empty payload, `json.loads` failure, or non-dict top level — closing the
"empty payload becomes `{}` and only denies via the *next* field lookup
finding it missing" coincidence flagged in survey §2b, so the deny now
happens for the actual reason (malformed input) rather than a downstream
side effect. The existing shell-side `[ -n "$payload" ] || deny ...`
empty-stdin guard stays as a fast-path (no behavior change, still
correct) — `gate_parse_json_or_deny` is what backs it up so the
Python-side guarantee no longer depends on that shell guard never being
refactored away independently.

## (c) Edit/MultiEdit/replace_all extraction

The `new_text` reconstruction block that appears in all eight gates
(survey §3, e.g. `observability-produces-gate.sh:130-152`) is replaced
by one call:

```python
new_text, ok = gate_lib.gate_reconstruct_write(tool, ti, current)
if not ok:
    deny(
        "this write targets %s but the gate cannot determine the resulting "
        "content from the tool input (tool=%r, replace_all honored). Write "
        "the full file with Write, or use an Edit/MultiEdit whose "
        "old_string matches, so the shape can be checked." % (rel, tool)
    )
```

`gate_reconstruct_write` (`gate-lib.py:87-152`) honors each edit's own
`replace_all` flag independently for `MultiEdit` (survey §3's confirmed
gap: today every gate hardcodes `.replace(o, n, 1)`, ignoring
`replace_all` entirely) and additionally reconstructs `NotebookEdit`'s
edited-cell source (survey §3's second gap — not named in the issue's
four numbered requirements, but the same class of tool-shape omission,
and free once `gate_reconstruct_write` is adopted, so it is folded in
rather than left out for no reason). No gate needs to special-case
`NotebookEdit`'s record path matching beyond what it already does for
Write/Edit/MultiEdit — the same `RECORD_RE`/`PROPOSAL_RE` match against
`gate_normalize_path`'s output applies uniformly regardless of which of
the four tools produced the write, since the tool-dispatch now lives
inside `gate_reconstruct_write` rather than in each gate's own
`if tool == "Write": ... elif tool == "Edit": ...` block.

`gate_deny`/`gate_allow` (`gate-lib.sh:70-79`) are the bash-level
building blocks; per the scout finding in §3 above, each gate's Python
payload keeps a local `deny(m)`/`allow()` wrapper (unchanged interface:
write to stderr, `sys.exit(2)`/`sys.exit(0)`) rather than crossing the
bash/Python boundary per call — this preserves the already-correct
stderr-deny behavior (survey §4, no defect found, no regression risk)
while still eliminating the duplicated trap/kill-switch/path/reconstruct
logic that IS the defect.

## (d) Section/adjacency/structural semantic check redesign

Survey §5 is the concrete defect: `has_any(*needles)` is a flat
substring test over the whole lowercased document (e.g.
`observability-produces-gate.sh:163-164`,
`phase-trace-gate.sh:193-194`), so a mention anywhere in the document
satisfies a check meant to verify a specific, located judgment. The
redesign replaces `has_any` with three escalating check primitives,
applied per gate based on what that gate is actually verifying:

1. **Section-scoped check** (for gates verifying "does the record's
   dedicated section for X say the required thing," e.g.
   `signal-golden-gate.sh`'s four-signal requirement,
   `cardinality-budget-gate.sh`'s handling-policy requirement): split
   `new_text` on markdown `^#{1,6}\s` heading lines into
   `(heading_text, section_body)` pairs (a plain regex split, no markdown
   library dependency — consistent with these gates' existing
   dependency-free style), find the section whose heading matches the
   gate's own topic (case-insensitive substring match on the heading
   only, e.g. a heading containing "cardinality" or "golden signals"),
   and run the needle checks against THAT section's body only, not the
   whole document. A document with a "## Cardinality Budget: N/A (out of
   scope)" heading followed by an unrelated "## Ad-hoc Queries" section
   that happens to mention "hash" in a different context no longer lets
   the cardinality gate's `POLICY_NEEDLES` check
   (`cardinality-budget-gate.sh:207-214`) pass on that unrelated mention.
   If no section header matches the gate's topic at all, fall back to
   requiring the check to pass within a bounded window (see #2) around
   the FIRST topic mention in the whole document, rather than silently
   passing or silently failing — an explicit, named fallback rather than
   an implicit one.
2. **Adjacency-scoped check** (for gates verifying "does a claim carry
   its own justification nearby," e.g. `phase-trace-gate.sh`'s
   deviation-needs-a-reason check, survey §5's most literal instance of
   the issue's named complaint): instead of
   `has_any(*deviation_markers) and not has_any(*reason_markers)` against
   the whole document (`phase-trace-gate.sh:199`), locate each line
   containing a deviation marker and require a reason marker within a
   fixed window (the same paragraph — i.e. within the run of
   non-blank lines bounded by blank lines on either side — as the
   narrowest scope that still tolerates a marker split across two
   sentences of one paragraph; a fixed N-line window, e.g. 3, as a
   simpler alternative if paragraph-splitting proves fragile against
   real record prose during implementation). `cardinality-budget-gate.sh`'s
   existing `for ln in lines: if CARD_RE.search(ln): ... placeholder_hit`
   loop (`cardinality-budget-gate.sh:192-199`) is the one already-correct
   precedent in the tree for this shape (same-line adjacency, negative
   direction) — the redesign generalizes it to a same-paragraph/N-line
   window, positive direction (reason marker must be found, not merely
   absent), and reuses it for `phase-trace-gate.sh`.
3. **Structural (key:value / list-item) check** (for gates verifying "is
   there a per-item pairing," e.g. `cardinality-budget-gate.sh`'s
   "confirmed high-cardinality dimension list and an explicit handling
   policy per dimension" requirement, which today only checks that SOME
   policy word occurs SOMEWHERE in the document via `POLICY_NEEDLES`
   at line 207-214, with no per-dimension pairing at all): require each
   detected dimension token (a line matching a `- <identifier>:` or
   `| <identifier> |` list/table-row shape within the matched section)
   to itself carry a policy needle on the same line or list item, not
   merely somewhere in the document. This is the most invasive of the
   three primitives and is scoped to the gates whose current requirement
   language already implies per-item pairing (cardinality-budget's
   README and header comment, `cardinality-budget-gate.sh:9-14`, already
   say "an explicit handling policy per dimension" — the code just
   doesn't check that yet).

Which gate uses which primitive:

| Gate | Current check (survey §) | New primitive |
|---|---|---|
| `observability-produces-gate.sh` | whole-doc `has_any` x3 (§5) | Section-scoped, one section per required component (methodology/cardinality/ad-hoc) |
| `methodology-selector-gate.sh` | whole-doc `has_any` x2 | Section-scoped (proposal has no fixed headings yet — falls back to bounded-window around first mention per §d.1's fallback clause) |
| `phase-trace-gate.sh` | whole-doc `has_any` deviation+reason (§5, the literal instance) | Adjacency-scoped (paragraph/N-line window) |
| `signal-golden-gate.sh` | whole-doc `has_any` x4 (gated behind a whole-doc "golden signal" trigger) | Section-scoped: trigger check stays whole-doc (cheap, low false-positive risk — detecting the METHODOLOGY NAME itself, not judging its content), but the four signal-presence checks move inside the matched section |
| `signal-red-gate.sh` | same shape as golden, x3 signals | Same treatment as golden |
| `signal-use-gate.sh` | same shape as golden, x3 signals | Same treatment as golden |
| `explorability-gate.sh` | whole-doc `has_any` x2 (mention + query-shape) | Adjacency-scoped: query-shape marker required within the same section/paragraph as the explorability mention, not merely present anywhere in a phase-2 record |
| `cardinality-budget-gate.sh` | partial: same-line placeholder check (already correct shape) + whole-doc policy check (§5) | Keep the existing same-line placeholder check; upgrade the policy check to structural (per-dimension pairing, §d.3) |

Every gate's needle vocabulary (the actual Korean/English words checked)
is unchanged — this redesign only changes WHERE in the document a needle
must be found, not WHICH needles are searched for. That keeps the
migration reviewable as "same substantive bar, verified honestly" rather
than a new judgment call about what counts as RED/USE/Golden Signals
content.

## (e) Mandatory test cases

Enumerated directly from the issue's requirement #3, applied to EVERY
one of the eight gates (closing survey §6's "7/8 tested, 0/8 have these
categories" gap):

1. **Edit** — a passing and a failing case via the `Edit` tool shape
   (`tool_input.old_string`/`new_string`), not just `Write`.
2. **MultiEdit** — a passing and a failing case via `MultiEdit`'s
   `edits` array.
3. **`replace_all`** — a case where an `Edit` or `MultiEdit` edit sets
   `"replace_all": true` against an `old_string` occurring more than
   once in the current file, asserting the gate judges the FULLY
   replaced content (all occurrences), not just the first.
4. **Malformed JSON** — three sub-cases per gate: truncated/invalid JSON
   on stdin, a valid-JSON-but-non-object top level (e.g. a bare JSON
   array or string), and a genuinely empty stdin payload. All three must
   deny (exit 2).
5. **Kill-switch on/off/garbage** — three sub-cases per gate: the
   corresponding `*_GATE_OFF` var set to a recognized on-spelling
   (assert the gate exits 0 without evaluating content at all — e.g. by
   feeding it a payload that would otherwise deny), set to a recognized
   off-spelling (assert normal enforcement), and set to an unrecognized
   garbage value such as a typo (assert the gate STAYS ACTIVE and still
   denies a failing case — this is the direct regression test for
   survey §2c's confirmed defect).
6. **Absolute path variants** — for each gate's already-covered relative
   record/proposal path fixture, an additional case using the absolute
   form of the same path (`$td/docs/issue-<n>/...`) and a `./`-prefixed
   relative form, both asserting the identical allow/deny verdict the
   relative-path fixture already gets.

Test harness shape: extend each existing `tests/*.test.sh`'s `run()`
helper (currently `run allow|deny <name> <path> <content>`,
`tests/cardinality-budget-gate.test.sh:7-14`) with an optional tool-shape
parameter so the same harness constructs `Write`/`Edit`/`MultiEdit`
payloads and optional env-var overrides for the kill-switch cases,
rather than inventing a second harness shape per gate. Additionally,
create the currently-missing `tests/observability-produces-gate.test.sh`
(survey §6's zero-coverage gap for the original role-owned gate) with
the same full case list as the other seven.

Per the gate-house standard's own stated harness
(`docs/handbooks/gate-house-standard.md`, "Standard test harness"), this
repo's per-gate test suites are the downstream analog of
`core/hooks/tests/run-gate-lib-tests.sh`'s six mandatory case groups —
the six bullets above are this repo's instantiation of that same list
against these eight gates' specific record/proposal paths and needle
vocabularies, not a new list invented independently.

Full-suite-green at ship time (phase 2) means: all eight gates' test
files, including the new/extended cases above, pass with `fail=0` in
each file's own `report()` counter (the pattern every existing test file
already ends on, e.g. `tests/cardinality-budget-gate.test.sh:22`,
`[ "$fail" -eq 0 ]`).

## (f) README realignment plan

**What's currently wrong** (survey §7): the root `README.md` documents
only the `observability` plugin (`README.md:1-48`, no mention of the
other seven plugin directories that exist in the repo today) and does
not link out to the seven sub-plugin READMEs, which are themselves
individually accurate (spot-checked, survey §7b) with no ghost-file
references found anywhere in the tree.

**What the corrected root README will state** (phase-2 work, not this
phase's deliverable, but planned here so the phase-2 diff has a target):

1. A top-level "Plugins" section listing all eight plugin directories
   (`observability`, `observability-cardinality-budget`,
   `observability-explorability`, `observability-methodology-selector`,
   `observability-phase-trace`, `observability-signal-golden`,
   `observability-signal-red`, `observability-signal-use`), each with a
   one-line description matching that plugin's own README's opening
   paragraph, and a relative link to that plugin's `README.md`.
2. A table of every real kill-switch env var (the eight enumerated in
   survey §7c: `OBSERVABILITY_PRODUCES_GATE_OFF`,
   `OBSERVABILITY_METHODOLOGY_SELECTOR_GATE_OFF`,
   `OBSERVABILITY_PHASE_TRACE_GATE_OFF`,
   `OBSERVABILITY_SIGNAL_GOLDEN_GATE_OFF`,
   `OBSERVABILITY_SIGNAL_RED_GATE_OFF`, `OBSERVABILITY_SIGNAL_USE_GATE_OFF`,
   `OBSERVABILITY_EXPLORABILITY_GATE_OFF`,
   `OBSERVABILITY_CARDINALITY_BUDGET_GATE_OFF`) with the record/proposal
   path each one gates, replacing the current single-gate description at
   `README.md:28-35`.
3. A new paragraph naming the gate-house-standard adoption itself: that
   every gate now sources `core/hooks/lib/gate-lib.sh`/`gate-lib.py` per
   `docs/handbooks/gate-house-standard.md`'s per-repo migration
   checklist, replacing the current `README.md:25-27` line's framing of
   the produces-gate as "fail-closed, not a core canon copy" (accurate
   pre-migration, stale post-migration — the corrected line should say
   it explicitly sources core's shared library, matching the pattern
   `README.md:38-44` already uses to describe the earlier
   trailer/record-fields/handbook-trigger canon switch).
4. No removal work is needed for "ghost files" — the survey found none
   (survey §7c) — so this axis of the realignment is purely additive
   (documenting what exists) rather than subtractive (deleting stale
   references), which keeps the phase-2 README diff smaller and lower-risk
   than the issue's framing implies.

## Non-goals / what stays exactly as-is

- Each gate's own record/proposal path pattern
  (`RECORD_RE`/`PROPOSAL_RE`), needle vocabulary, and denial message
  text — untouched. This is a plumbing migration, not a re-litigation of
  what each gate requires.
- Each gate's own kill-switch env var NAME — untouched; only the
  recognizer function changes (survey §2c → §b above).
- The `.observability-phase1-methods/<issue-n>.json` state-file
  producer/consumer contract between `methodology-selector-gate.sh` and
  `phase-trace-gate.sh` — untouched.
- `gate-lib.sh`/`gate-lib.py` themselves — referenced via
  `CLAUDE_PLUGIN_ROOT_CORE`, never vendored or copied into this repo,
  per the gate-house standard's "reference only, never copy" rule
  (`gate-lib.sh:7`, `docs/handbooks/gate-house-standard.md`'s
  "Compliance detector" section) — this repo's own phase-2 work should
  add this repo's hooks directory to a `compliance-check.sh` run before
  claiming the migration done, per that same handbook's per-repo
  migration checklist.
