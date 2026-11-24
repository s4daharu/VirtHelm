# Bounded conditional storage runway scenario

VirtHelm 0.1.71 extends EP-ALERT-05 with an explicitly conditional,
read-only estimate on Storage > Capacity. It reuses the existing on-demand
RRD averages and fresh complete foreground storage snapshot. There are no
new network requests, permissions, dependencies, notifications, persisted
data, background tasks or write authority.

## Evidence and computation

The existing [retrospective review](115-implementation-storage-history-review.md)
must accept the entire series first. Only 24-hour or 7-day selections with
at least six valid samples, at least 75% window coverage and two halves of
at least one-quarter window duration qualify. All adjacent used-byte
measurements must be nondecreasing. Net growth must be at least 1% of fixed
total capacity. Both half-window slopes must be positive and differ by no
more than a factor of two.

The current uniquely visible, active, not-explicitly-disabled storage must
have the same total bytes, valid used bytes below total and be within one
percentage point of the last historical average. The existing freshness,
partial-read, refresh and session gates still apply. Current values are
a consistency check, not the scenario's starting point.

Remaining bytes at the last historical average are divided by the faster
and slower half-window slopes, yielding two conditional linear times to
100%. The display rounds outward to whole hours, only when both estimates
are within 1 hour to 90 days. The comparison's UTC endpoint and sample
count above the scenario identify its as-of time and source. Half-window
rates are also displayed. These are illustrative extrapolations of two
observed rates, not a statistical confidence interval, reliable forecast,
available allocatable capacity or time-to-failure claim. Reclamation,
thin provisioning, backend reservations, workload and capacity changes
can invalidate them. Shared storage is never combined across nodes.

Missing, inconsistent, declining, flat, sparse, stale, resized, malformed
or highly variable data produces an unavailable state; absence of an
estimate never means storage is healthy.

## Verification and release limits

Seven synthetic model tests and three widget tests cover steady and varying
growth, outward rounding, window and coverage limits, missing/incompatible
current data, bad history, horizon limits and non-actionable presentation.
Pinned exact-head PR CI must pass formatting, analysis, full tests and
Android compile before promotion. No live PVE 8.4/9.2 or physical Android
validation is claimed. Reverting this slice removes only local computation
and presentation; no data migration is required.

Seasonal/statistical forecasting, allocation-aware estimates, historical
cross-resource comparisons, physical-device validation and production
certification remain gated.

Exact feature head 8f3cbd10afc087bc75b1800a03f2edf4309faa67 passed Android CI 45353245870 and repository checks 45353245880 (20 Python tests, pinned formatting/analyze, 476 Flutter tests, generated runner/lockfile checks and ARM64 debug compilation). Merged main f1c3f2154f03448643afb1628cbc347b2d34dff4 also passed Android CI 45353775704 and repository checks 45353775535. No live PVE or physical Android validation claimed.
