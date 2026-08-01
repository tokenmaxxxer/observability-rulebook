# Current-state survey: observability gate scripts (issue-10)

Scope: every `PreToolUse` gate script in this repo —
`observability/hooks/observability-produces-gate.sh` and the seven
`observability-*/hooks/*-gate.sh` scripts — plus their tests
(`tests/*.test.sh`) and the root/plugin `README.md` files. Every claim
below cites an actual `file:line` in the current tree (branch
`issue-10/observability`, commit `9d4923c`). This is the rigor floor for
`docs/issue-10/proposals/2026-08-01-gate-a-plus-hardening.md`; nothing
here is a fix, only an inventory of what currently exists.

All eight gates are structurally identical (same bash preamble, same
`_under()` python helper, same JSON-payload python heredoc shape,
different only in which record path and which needle words they check).
Where a defect is common to all eight, it is cited once against
`observability-produces-gate.sh` as the representative instance, with the
other seven's matching line numbers listed alongside.

## 1. Path-matching approach (relative-only, no absolute-path normalization)

Every gate resolves `tool_input.file_path` against a `root` it computes
from `CLAUDE_PROJECT_DIR` or `git rev-parse --show-toplevel`, then does:

```
observability/hooks/observability-produces-gate.sh:95-102
    def resolve(p):
        n = p.replace("\\", "/")
        a = n if posixpath.isabs(n) else posixpath.join(root, n)
        a = posixpath.normpath(a)
        try:
            return posixpath.normpath(os.path.realpath(a).replace("\\", "/"))
        except OSError:
            return a
```

This DOES handle an absolute `file_path` correctly in the sense that
`posixpath.isabs(n)` short-circuits the join — an absolute path is used
as-is, then realpath'd. So a literal absolute path that already matches
the project root resolves fine. The actual gap is narrower than "no
absolute-path support": there is no test proving it (see §5), and the
`_under()` bash pre-filter used to pick the `root` in the first place
(same file, lines 44-55) re-implements the identical resolve-and-compare
logic a second time in bash-invoked Python, so the two normalization
paths (`_under()` at line 44-55, and the `resolve()`/`RECORD_RE` match at
line 92-120) are two independently-maintained copies of the same
algorithm that happen to agree today — exactly the "same shape, quietly
different idiom" pattern flagged in `docs/handbooks/gate-house-standard.md`
for core's own gates pre-issue-72. A `./`-prefixed relative path (e.g.
`./docs/issue-10/reports/observability.md`) is not specifically exercised
either; `posixpath.normpath` collapses it, but again untested.

Identical `resolve()` shape (line numbers of the def):
- `observability-methodology-selector/hooks/methodology-selector-gate.sh:95`
- `observability-phase-trace/hooks/phase-trace-gate.sh:100`
- `observability-signal-golden/hooks/signal-golden-gate.sh:93`
- `observability-signal-red/hooks/signal-red-gate.sh:94`
- `observability-signal-use/hooks/signal-use-gate.sh:93`
- `observability-explorability/hooks/explorability-gate.sh:100`
- `observability-cardinality-budget/hooks/cardinality-budget-gate.sh:100`

**Verdict**: not a correctness bug today, but eight independent
hand-rolled copies of path-normalization logic with no absolute-path or
`./`-prefix test coverage — the issue's "absolute-path normalization"
defect is really "unverified, undifferentiated, and duplicated," which
is exactly what `core/hooks/lib/gate-lib.py`'s `gate_normalize_path` (see
proposal §a) was written to collapse into one tested function.

## 2. Fail-closed posture

### 2a. Trap-at-top: present and correctly ordered

Every gate installs its EXIT trap as literally the first two
non-shebang lines, before `set -uo pipefail`:

```
observability/hooks/observability-produces-gate.sh:1-3
#!/usr/bin/env bash
__fc(){ rc=$?; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "fail-closed: gate aborted (rc=$rc)" >&2; exit 2; fi; }
trap __fc EXIT
```

`set -uo pipefail` only appears at line 17 (and equivalently in every
other gate), i.e. after the trap is armed — matching the gate-house
standard's stated rationale ("so a syntax error or unset-variable abort
on the next line is still caught," `gate-lib.sh:34-35`). This part is
already A-grade and needs no behavior change, only a swap to call
`gate_trap_fail_closed` instead of a hand-rolled `__fc`/`trap` pair (eight
copies of the identical four-line idiom, one per gate file, same
line-1-3 position in each).

### 2b. Malformed-JSON handling: present, but the shell-side path is a silent pass-through, not a deny

The Python payload denies correctly on bad JSON:

```
observability/hooks/observability-produces-gate.sh:79-84
    raw = os.environ.get("OG_PAYLOAD", "")
    try:
        ev = json.loads(raw) if raw else {}
    except ValueError:
        deny("the tool-call payload is not valid JSON; the gate cannot judge the produces shape on an unparseable write.")
    if not isinstance(ev, dict):
        deny("the tool-call payload is not a JSON object; failing closed on produces shape.")
```

Note `if raw else {}` at line 81: an **empty** payload does not reach
`json.loads` at all — it becomes `{}`, which IS a dict, so the
`isinstance` check does not catch it either. Nothing downstream denies
on `{}` by itself; instead `tool_input` lookup at line 88-90
(`ti = ev.get("tool_input"); if not isinstance(ti, dict): deny(...)`)
denies because `{}` has no `tool_input` key. So an empty *Python-side*
payload does still deny, but via the `tool_input` check, not the
JSON-object check — a coincidental save, not a designed one, and it only
works because `tool_input` happens to be the very next field accessed.
Earlier in the same script, the *shell-side* empty-payload guard is
already stricter and correct:

```
observability/hooks/observability-produces-gate.sh:29-30
payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || deny "observability-produces-gate: empty tool-use payload on stdin; cannot evaluate the produces gate."
```

So the shell layer already denies on empty stdin before the Python
payload ever runs; the Python-side `if raw else {}` fallback is
dead/redundant code given that guard, but is a latent trap if that shell
guard is ever refactored away independently (e.g. during the gate-lib
migration) without carrying the equivalent fix. `gate_parse_json_or_deny`
(`gate-lib.py:19-36`) collapses both layers into one call that denies on
empty, unparseable, or non-dict JSON uniformly — see proposal §b.

Same shell-guard-plus-Python-`if raw else {}` pair, one occurrence each:
- `observability-methodology-selector/hooks/methodology-selector-gate.sh:29,79-84`
- `observability-phase-trace/hooks/phase-trace-gate.sh:35,85-90`
- `observability-signal-golden/hooks/signal-golden-gate.sh:28,78-83`
- `observability-signal-red/hooks/signal-red-gate.sh:29,79-84`
- `observability-signal-use/hooks/signal-use-gate.sh:28,78-83`
- `observability-explorability/hooks/explorability-gate.sh:34,84-89`
- `observability-cardinality-budget/hooks/cardinality-budget-gate.sh:34,84-89`

### 2c. Kill-switch: THE confirmed defect — every gate has the exact backwards pattern gate-lib.sh was built to fix

All eight gates use the identical case statement:

```
observability/hooks/observability-produces-gate.sh:22-25
case "${OBSERVABILITY_PRODUCES_GATE_OFF:-}" in
  ""|0|false|no|off) ;;
  *) exit 0 ;;
esac
```

This is precisely the bug documented in
`core/hooks/lib/gate-lib.sh:43-54` and
`docs/handbooks/gate-house-standard.md` ("The two bugs this issue fixed",
item 1): the off-spellings are enumerated, but the wildcard `*` branch —
which catches every unrecognized value, including a typo like
`OBSERVABILITY_PRODUCES_GATE_OFF=1x` or `=TRUE` (trailing space,
wrong case not caught by this pattern since it's not lowercased first) —
disables the gate (`exit 0`) rather than staying active. A stray env var
typo silently turns every one of these eight gates off. This is a
direct, confirmed hit on issue defect #1's fail-closed requirement, not
speculative — the case arms are read verbatim above.

Identical case block, one per gate:
- `observability-methodology-selector/hooks/methodology-selector-gate.sh:21-24`
- `observability-phase-trace/hooks/phase-trace-gate.sh:27-30`
- `observability-signal-golden/hooks/signal-golden-gate.sh:20-23`
- `observability-signal-red/hooks/signal-red-gate.sh:21-24`
- `observability-signal-use/hooks/signal-use-gate.sh:20-23`
- `observability-explorability/hooks/explorability-gate.sh:26-29`
- `observability-cardinality-budget/hooks/cardinality-budget-gate.sh:26-29`

## 3. Edit/MultiEdit/replace_all handling

All eight gates DO handle `Write`, `Edit`, and `MultiEdit` (the issue's
claim of "Write-only" support does not hold against the current tree —
this is scaffolding that has already moved past that state). Representative
shape:

```
observability/hooks/observability-produces-gate.sh:130-152
    new_text = None
    if tool == "Write":
        c = ti.get("content")
        if isinstance(c, str):
            new_text = c
    elif tool == "Edit":
        o, n = ti.get("old_string"), ti.get("new_string")
        if isinstance(o, str) and isinstance(n, str) and current is not None and o in current:
            new_text = current.replace(o, n, 1)
    elif tool == "MultiEdit":
        edits = ti.get("edits")
        text = current
        if isinstance(edits, list) and text is not None:
            ok = True
            for e in edits:
                if not isinstance(e, dict):
                    ok = False; break
                o, n = e.get("old_string"), e.get("new_string")
                if not isinstance(o, str) or not isinstance(n, str) or o not in text:
                    ok = False; break
                text = text.replace(o, n, 1)
            if ok:
                new_text = text
```

Two real gaps, confirmed by reading this code, not by assumption:

1. **`replace_all` is never read.** Both the `Edit` branch (line 137,
   `current.replace(o, n, 1)`) and each `MultiEdit` edit (line 150,
   `text.replace(o, n, 1)`) hardcode the `count=1` (first-occurrence-only)
   form of `str.replace`. `ti.get("replace_all", ...)` / `e.get("replace_all",
   ...)` do not appear anywhere in any of the eight gate files (confirmed:
   no match for the string `replace_all` in any `*-gate.sh` in this repo).
   A real `Edit` or `MultiEdit` call with `"replace_all": true` against a
   multiply-occurring `old_string` is reconstructed by this gate as if only
   the first occurrence changed — the gate can then judge stale/wrong
   resulting content. This is the identical bug
   `docs/handbooks/gate-house-standard.md` documents core's own
   `record-fields-gate.sh` had before its gate-lib migration ("The two
   bugs this issue fixed," item 2).
2. **`NotebookEdit` is not handled by any of the eight gates at all** (no
   match for `NotebookEdit` in any gate file) — a notebook-cell write to
   one of the guarded record paths passes through unchecked (falls into
   `if tool in ("Write","Edit","MultiEdit"): ... path = p` /
   `if path is None: sys.exit(0)` at
   `observability/hooks/observability-produces-gate.sh:107-113`, silently
   allowed). Not called out by name in the issue's four numbered
   requirements, but is the same class of tool-shape gap as
   `replace_all`, and `gate_reconstruct_write` (`gate-lib.py:87-152`)
   already covers it, so the proposal folds it in as a freebie rather
   than leaving it out of scope arbitrarily.

Identical `new_text` reconstruction block, one per gate (line numbers of
the `if tool == "Write":` line):
- `observability-methodology-selector/hooks/methodology-selector-gate.sh:130`
- `observability-phase-trace/hooks/phase-trace-gate.sh:160`
- `observability-signal-golden/hooks/signal-golden-gate.sh:128`
- `observability-signal-red/hooks/signal-red-gate.sh:129`
- `observability-signal-use/hooks/signal-use-gate.sh:125`
- `observability-explorability/hooks/explorability-gate.sh:138`
- `observability-cardinality-budget/hooks/cardinality-budget-gate.sh:138`

## 4. Deny reasons to stderr

Already correct everywhere, and should stay that way through the
migration (this is one axis the gate-house standard's `gate_deny`
preserves as-is, not a behavior change). Every `deny()` helper writes to
`sys.stderr` / the bash `deny()` writes via `>&2`:

```
observability/hooks/observability-produces-gate.sh:20
deny() { echo "${role}: refused — $1" >&2; exit 2; }

observability/hooks/observability-produces-gate.sh:76-77
    def deny(m):
        sys.stderr.write("%s: refused — %s\n" % (role, m)); sys.exit(2)
```

Confirmed identically in all eight gates (bash `deny()` one-liner near
the top of each file, Python `def deny(m): sys.stderr.write(...)` inside
each heredoc). No defect found here; the issue's "deny reasons to
stderr" requirement is already met and the proposal's job is only to not
regress it while switching to `gate_deny`.

## 5. Semantic/deviation check logic — bare substring matching, confirmed in every content-judging gate

This is the issue's #2 requirement and the clearest defect class in the
tree. Every gate that inspects *content* (as opposed to just a file path)
does it via a `has_any(*needles)` helper that is a flat substring
membership test over the entire lower-cased document, with no structural
anchor:

```
observability/hooks/observability-produces-gate.sh:161-174
    low = new_text.lower()

    def has_any(*needles):
        return any(nd in low for nd in needles)

    missing = []
    if not has_any("red method", "use method", "golden signals", "rate/errors/duration",
                    "red (rate", "red(rate", " red/", "/red ", "red 방법", "use 방법",
                    "golden signal"):
        missing.append("signal-selection-methodology ...")
    if not has_any("cardinality", "카디널리티"):
        missing.append("cardinality-budget ...")
    if not has_any("ad-hoc", "adhoc", "ad hoc", "애드혹", "탐색 쿼리", "explorability", "탐색가능"):
        missing.append("ad-hoc-query-example ...")
```

Concretely: a phase-2 record containing the single unrelated sentence
"We considered RED but rejected it; cardinality is out of scope for this
sprint; ad-hoc queries were not explored" would pass this gate — every
needle (`"red"`-family via `" red/"`... actually not quite, but
`"cardinality"` and `"ad-hoc"`) matches regardless of the surrounding
clause negating or hedging the claim. This is exactly the audit's
"checking a doc merely contains the word '변경'/'change' plus any 'reason'
string" complaint, generalized: `has_any` never checks section
membership (is the mention inside a "## Cardinality Budget" heading?),
adjacency (is the reason marker within N lines/tokens of the claim it's
supposed to justify?), or structure (is this a list item with the
expected key: value shape?) — it is bag-of-words presence over the raw
document text.

The most literal instance of the issue's exact complaint is
`observability-phase-trace/hooks/phase-trace-gate.sh:191-206`:

```
    low = new_text.lower()

    def has_any(*needles):
        return any(nd in low for nd in needles)

    deviation_markers = ("이탈", "deviat", "switch", "변경")
    reason_markers = ("because", "때문", "이유", "reason")

    if has_any(*deviation_markers) and not has_any(*reason_markers):
        deny(
            "record at %s claims a deviation from the phase-1 methodology (contains a deviation "
            ...
```

This is word-for-word the pattern the issue names: "문서 전역('변경'+아무
'reason')" — any occurrence of "변경" anywhere in the document, paired
with any occurrence of "reason"/"이유"/"때문"/"because" anywhere else in
the document, regardless of whether the two are in the same sentence,
same paragraph, or even related to each other, passes. A record that says
"USE method 변경... [500 words of unrelated content] ...for other reason,
we chose Golden Signals for a different surface" would pass, because
"변경" and "reason" both occur somewhere in the 500+ word document with
no adjacency requirement.

`observability-cardinality-budget/hooks/cardinality-budget-gate.sh:189-205`
is the one partial exception already in the tree — it has a real,
if narrow, adjacency check (same physical line only):

```
    PLACEHOLDER_NEEDLES = ("n/a", "tbd", "해당 없음")
    lines = new_text.splitlines()
    placeholder_hit = False
    for ln in lines:
        if CARD_RE.search(ln):
            low_ln = ln.lower()
            if any(nd in low_ln for nd in PLACEHOLDER_NEEDLES):
                placeholder_hit = True
                break
```

This checks that a cardinality mention and a placeholder token are NOT
on the same line, which is adjacency in one direction (a same-line
negative check) but still has no positive structural requirement (no
"the handling policy must appear within N lines of the dimension it
names," no section-heading anchor, no per-dimension pairing — the
`POLICY_NEEDLES` check right after it at
`cardinality-budget-gate.sh:207-214` is right back to whole-document
`has_any`). This is the strongest existing prior art in the repo for
what an adjacency check looks like, and the proposal's §d design
generalizes exactly this shape.

Every other content-judging gate (`signal-golden-gate.sh:162-187`,
`signal-red-gate.sh:162-184`, `signal-use-gate.sh:158-186`,
`explorability-gate.sh:172-206`,
`methodology-selector-gate.sh:161-181`) uses the same flat
whole-document `has_any` with no section or adjacency check at all.

## 6. Test coverage gaps

`tests/` has one `.test.sh` per plugin **except** the root `observability`
plugin — there is no `tests/observability-produces-gate.test.sh` anywhere
in the repo (confirmed: `tests/` contains exactly
`cardinality-budget-gate.test.sh`, `explorability-gate.test.sh`,
`methodology-selector-gate.test.sh`, `phase-trace-gate.test.sh`,
`signal-golden-gate.test.sh`, `signal-red-gate.test.sh`,
`signal-use-gate.test.sh` — seven files for eight gate scripts). The
`observability-produces-gate.sh` gate — the original, role-owned gate
this repo's README foregrounds — has zero test coverage today.

Representative existing test file,
`tests/cardinality-budget-gate.test.sh:1-23` (full file, 22 lines):
every one of the seven existing test files follows this same
`run allow|deny <name> <path> <content>` harness, driving the gate only
through a synthetic `Write` tool call:

```
tests/cardinality-budget-gate.test.sh:7-14
run() { # want name path content
  td="$(cd "$(mktemp -d)" && pwd -P)"; git init -q "$td"; mkdir -p "$(dirname "$td/$3")"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":%s},"cwd":"%s"}' \
    "$3" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$4")" "$td" \
    | env CLAUDE_PROJECT_DIR="$td" /bin/bash "$GATE" >/dev/null 2>&1
  rc=$?; case "$rc" in 0) got=allow ;; 2) got=deny ;; *) got="exit-$rc" ;; esac
  rm -rf "$td"; report "$1" "$got" "$2"
}
```

Confirmed gaps, present in ALL seven existing test files, not just this
one:
- No `Edit`-tool test case anywhere (`grep -l '"tool_name":"Edit"' tests/*.test.sh` → no matches).
- No `MultiEdit`-tool test case anywhere.
- No `replace_all` test case (the flag does not appear in any test file,
  consistent with §3's finding that no gate reads it).
- No malformed-JSON test case (every `run()` call constructs valid JSON
  via `python3 -c 'import json...json.dumps(...)'` — there is no fixture
  that feeds truncated/non-object/empty stdin).
- No kill-switch test case at all — none of the seven test files sets
  the corresponding `*_GATE_OFF` env var in any case, on, off, or
  garbage.
- No absolute-path test case — every `path` argument passed to `run()`
  is a relative path like `docs/issue-7/proposals/x-observability.md`
  (`tests/cardinality-budget-gate.test.sh:15-20`); none constructs an
  absolute `file_path` pointing at the same target.

Given eight gate scripts and one missing test file entirely, plus six
categories of untested behavior repeated across all seven existing test
files, this is the widest gap of the four issue requirements.

## 7. README drift from reality

### 7a. Root `README.md` documents only one of eight plugins

`README.md:1-48` (the entire file) describes only the `observability`
plugin's manifest, hooks, and produces-gate. It does not mention
`observability-cardinality-budget`, `observability-explorability`,
`observability-methodology-selector`, `observability-phase-trace`,
`observability-signal-golden`, `observability-signal-red`, or
`observability-signal-use` anywhere — seven of the eight plugin
directories that exist in the repo today (confirmed:
`find . -maxdepth 1 -type d -name 'observability*'` lists all eight;
`grep -c observability- README.md` finds none of the seven sibling names
in the root README's prose). A reader of the root README would believe
this repo ships a single plugin.

`README.md:38-44` explicitly asserts, in the present tense, that
"role-agnostic gates (...) are no longer vendored here" and "This repo
stopped shipping per-role copies of both" — accurate as a historical
note about `trailer-gate.sh`/`record-fields-gate.sh`/
`handbook-trigger-gate.sh`, but silent on the fact that this repo *itself*
now has eight bespoke gates duplicating the trap/kill-switch/path-resolve
shape across each other (the exact pattern the paragraph criticizes core
canon for, pre-issue-72, just at repo scope instead of core scope).

### 7b. Sub-plugin READMEs are individually accurate but the root never links them

Spot-checked
`observability-methodology-selector/README.md` (full file, 27 lines):
this file's own claims check out against its gate script (fires on
Write/Edit/MultiEdit targeting `docs/issue-<n>/proposals/*observability*.md`,
line 6 of the gate's own header comment matches; the state-file path
`.observability-phase1-methods/<issue-n>.json` matches
`methodology-selector-gate.sh:188-192` exactly; the kill-switch name
matches `methodology-selector-gate.sh:15,21`). No ghost-file references
found in this or the other six sub-plugin READMEs (spot check across all
eight `README.md` files found no dangling path). The drift is entirely
at the root README's level: it never mentions that seven other
`README.md` files (and plugins) exist, so a reader who only opens the
root doc has no path to them.

### 7c. No ghost files, but no manifest of the real kill-switch set either

Every kill-switch name cited in this report
(`OBSERVABILITY_PRODUCES_GATE_OFF`, `OBSERVABILITY_METHODOLOGY_SELECTOR_GATE_OFF`,
`OBSERVABILITY_PHASE_TRACE_GATE_OFF`, `OBSERVABILITY_SIGNAL_GOLDEN_GATE_OFF`,
`OBSERVABILITY_SIGNAL_RED_GATE_OFF`, `OBSERVABILITY_SIGNAL_USE_GATE_OFF`,
`OBSERVABILITY_EXPLORABILITY_GATE_OFF`,
`OBSERVABILITY_CARDINALITY_BUDGET_GATE_OFF`) is a real, working env var
read by its corresponding gate script — none is a ghost. The gap is
omission (root README lists one of eight), not fabrication (nothing in
either README references a path or switch that does not exist in the
tree).

## Summary table

| Issue defect | Found in repo? | Where |
|---|---|---|
| Absolute-path normalization missing | Partial — handled, untested, duplicated 8x | §1 |
| Fail-closed trap-at-top | Already correct | §2a |
| Malformed-JSON = deny | Correct at shell layer; Python layer denies via a side-effect (missing `tool_input`), not a direct empty/non-dict check | §2b |
| Kill-switch unrecognized = ACTIVE | **Confirmed backwards in all 8 gates** | §2c |
| Edit/MultiEdit support | Already present in all 8 gates | §3 |
| `replace_all` support | **Confirmed absent in all 8 gates** | §3 |
| Deny reasons to stderr | Already correct | §4 |
| Semantic checks beyond substring | **Confirmed bare substring in 7/8; 1 partial adjacency precedent** | §5 |
| Mandatory test cases | **7/8 gates tested; 0/8 have Edit/MultiEdit/replace_all/malformed-JSON/kill-switch/absolute-path cases** | §6 |
| README reality match | Root README covers 1/8 plugins; no ghost files found | §7 |
