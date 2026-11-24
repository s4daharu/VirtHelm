# Bounded two-node historical utilization comparison

VirtHelm 0.1.72 advances EP-ALERT-05 / UX-06 on Node > Metrics. After
explicitly loading a node's RRD averages, the operator may select one other
uniquely visible online node in the same fresh, complete inventory and
explicitly request its history for the same selected timeframe. This reuses
the existing authenticated GET node RRD endpoint (AVERAGE); no endpoint,
permission, persistence, dependency, automatic polling or write is added.

## Evidence rules

Both series must have 3–1500 samples, no malformed/truncated response,
complete finite CPU and memory fractions in [0, 1], increasing unique
timestamps, recent endpoints, at least half-window coverage, and gaps no
larger than one-sixth of the selected 1h/24h/7d window. The comparison uses
only exact UTC instant matches, with at least 80% of each series matched,
at least three matches, the same coverage, gap and freshness bounds. No
interpolation, zero fill, timezone bucketing or extrapolation is used.
The two CPU and two memory arithmetic sample means are displayed separately
with matched count and UTC endpoints. They are not time-weighted averages,
absolute resource capacity, workload equivalence or placement advice.
A missing result is not evidence of healthy capacity.

## Session and request boundaries

Only one logical peer read is initiated per explicit tap, subject to the
existing bounded transient GET retry policy. A maximum of 64 visible node
records is considered; ambiguous/offline peers and trimmed-name aliases are
excluded. Current profile,
generation, unique primary/peer identity, current inventory freshness,
partial-read and refresh gates are rechecked before and after the peer read.
Peer selection, timeframe change or primary reload invalidates the result;
profile changes redact the route, and late results are discarded. No
background request or shared/persisted series is introduced.

## Verification and release limits

Seven synthetic model tests and three route widget tests cover exact matching,
boundary overlap, mismatched timestamps, stale/future/sparse data, invalid
fractions, duplicates, explicit loading, ambiguity and delayed profile switch.
Exact-head pinned Flutter CI is required before merging. Live PVE 8.4/9.2
bucket/ACL behavior, physical Android accessibility and performance remain
gated. Guest-to-guest comparisons, mixed-resource aggregation and statistical
forecasting are not part of this slice. Revert removes only this local
presentation and one explicit GET path; no data migration is required.
