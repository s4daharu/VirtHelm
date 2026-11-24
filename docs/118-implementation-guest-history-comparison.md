# Bounded same-node guest historical utilization comparison

VirtHelm 0.1.73 extends EP-ALERT-05 / UX-06 on Guest > Metrics. After
explicitly loading history for a running non-template QEMU VM or LXC
container, choose one running non-template guest of the same type on the
same uniquely visible online node. One explicit logical peer read uses the
existing guest RRD GET endpoint and bounded transient retry policy.

The guest adapter reuses the tested node matching algorithm for all three
windows: 1h, 24h and 7d. Both series must have 3–1500 complete finite CPU
and memory fraction samples, no malformed/truncated response, increasing
unique timestamps, at least half-window coverage, bounded gaps and recent
endpoints. At least 80% of each series must match by exact UTC instant.
Separate arithmetic sample means and UTC endpoints are shown; no
interpolation, time-weighted utilization, absolute capacity, forecast,
placement recommendation or workload equivalence is implied.

The selector considers at most 200 guest records from a fresh authenticated
inventory with no partial or malformed warning. It excludes duplicate
cluster-wide VMIDs, stopped/template guests, other kinds/nodes, unknown or
ambiguous node identity and guests with blocked operations. Session/profile,
generation, selected peer, timeframe, eligible identities and inventory
snapshot are rechecked after the read. Inventory replacement invalidates completed comparisons;
selection, primary reload and timeframe changes clear the peer series.
No automatic read, new endpoint, permission, persistence, dependency,
background polling or mutation is added. Historical identity continuity
across past migrations/restarts is not established.

Seven model and four route widget tests cover adapter parity, all windows,
data rejection, candidate selection, duplicate IDs, incomplete inventory,
explicit loading, timeframe invalidation, inventory refresh and profile
switch during a pending read. Exact-head CI must pass before promotion.
Live PVE 8.4/9.2 RRD/ACL fixtures and physical Android accessibility and
performance remain gated. Cross-node/mixed-kind guests and broader
aggregations remain deferred. Revert removes local presentation and an
explicit read path; no migration is needed.
