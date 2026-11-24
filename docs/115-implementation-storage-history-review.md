# Bounded storage history review

VirtHelm 0.1.70 advances EP-ALERT-05 with a retrospective storage capacity
comparison on the existing Storage > Capacity detail tab. It uses only the
explicitly loaded per-storage RRD averages described in
[the storage history implementation](63-implementation-storage-rrd-history.md).
No additional GET, mutation, polling, dependency, permission, notification
or persistence is introduced.

## Behavior and evidence

The card reports the signed direction, absolute used-byte change, absolute
percentage-point change, first/last UTC timestamps and sample count for the
selected 1h, 24h or 7d response. This is an endpoint-to-endpoint observation
of averages, not a fitted trend, current free-space reading or forecast.
A comparison requires an active uniquely visible storage, fresh, complete foreground
inventory and storage reads, with no in-flight inventory refresh. Existing profile/generation
route isolation is preserved. Starting an explicit history refresh clears
the previous history, so an old comparison cannot be presented as new.

The local evaluator refuses truncated or malformed responses, fewer than
three or more than 1,500 samples, invalid ratios, changing total capacity,
duplicate or non-increasing timestamps, future samples, stale endpoints,
gaps greater than one-sixth of the requested window and a span shorter than
half the window. The oldest point may be at most one window plus one-sixth
old. These are conservative application coverage heuristics, not server
bucket guarantees; even accepted averages may hide changes between samples.
Shared storage is never combined across nodes.

## Validation and rollback

Eight synthetic model tests and two widget tests cover signed changes,
coverage boundaries, duplicate/future/stale timestamps, malformed/truncated
series, invalid metrics, resized storage, explicit unavailable states and
non-actionable evidence. Pinned Flutter formatting, analyzer, complete test
suite and Android debug compilation are required in PR CI before promotion.
No live PVE or physical-device validation is claimed. Reverting this slice
removes only local presentation/evaluation; no data migration is necessary.

Forecasting, allocation-aware estimates, seasonal uncertainty, historical
cross-resource comparison and production certification remain gated.

Exact feature head `97305ed0b899aedd9ba9857edabb1806aaf45fe3` passed
[Android CI](https://github.com/s4daharu/VirtHelm/actions/runs/45327213971)
and [repository checks](https://github.com/s4daharu/VirtHelm/actions/runs/45327213979),
including 466 Flutter tests and ARM64 debug compilation. The merged `main`
commit `c3fa58a83dc19602fde515a094ef1d9fc44987a2` has the identical Git tree.
A separate bounded conditional runway scenario follows in [milestone 116](116-implementation-storage-runway-scenario.md).
