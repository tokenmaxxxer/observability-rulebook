# observability-phase-trace

Methodology-agnostic cross-cutting norm: phase-2's adopted signal
methodology (RED/USE/Golden Signals) must trace back to what phase-1
already named. This is an **ordering constraint tracked as state, not
prose** — the plugin does not re-derive or re-judge the methodology
choice itself; it only checks that phase-2 doesn't silently claim a
deviation without stating a reason.

This plugin is a **state CONSUMER, never a writer**. It reads
`.observability-phase1-methods/<issue-n>.json` (shape
`{"issue": "<n>", "methodology_named": true}`), which is written
exclusively by the sibling `observability-methodology-selector` plugin
on a passing phase-1 proposal write. If that state file does not exist,
the gate treats this as informational only — it never denies on a
missing state file (phase-1 may simply not have run under this
tracking yet).

If the state file exists with `methodology_named: true`, and the
phase-2 record text contains a deviation marker ("이탈"/"deviat"/
"switch"/"변경"), the record must also contain a reason marker
("때문"/"이유"/"because"/"reason") somewhere in the text, or the write
is denied. No deviation marker present at all means nothing to check.

Install by adding this plugin's entry to `.claude-plugin/marketplace.json`
and enabling it alongside `observability-methodology-selector`.

Kill switch: `export OBSERVABILITY_PHASE_TRACE_GATE_OFF=1`

No `agents/` directory — this is a one-shot cross-cutting consistency
check on a single phase-2 write, not a role with a repeated dispatch
cadence.
