# Bounded cross-node guest history comparison (0.1.75)

EP-ALERT-05 / UX-06 extends the 0.1.73 guest-history comparison to running same-kind guests on different online nodes within the active profile. The operator selects a single peer and explicitly loads its existing RRD history. Remote peers display the node name; results identify both nodes. There is no automatic fetch, new endpoint, write, permission, persistence or dependency.

## Safety and interpretation

- Require fresh clean inventory, at most 64 nodes and 200 guests, a current unique running non-template primary and peer of the same kind, and globally unique VMIDs. Nodes must be online, exact, nonblank and unambiguous even after trimming.
- Selection retains VMID and node. A migrated peer cannot be silently retargeted. In-flight results retain existing route/profile/generation, exact peer, timeframe and inventory-snapshot guards.
- Reuse exact timestamp matching, bounded RRD coverage, and separate CPU/memory arithmetic sample means. Relative utilization is not absolute workload, allocation-aware headroom, placement advice or a forecast.
- Mixed-kind, cross-profile and multi-resource aggregation remain out of scope.

## Verification

Three model regressions cover scope, offline/missing and ambiguous nodes, duplicate VMIDs, moved primary and inventory bounds. Two widget regressions cover explicit remote reads, visible node attribution and reselection after migration. Existing same-node, refresh and profile-switch cases remain. Exact-head repository and Android CI are required before promotion. Live PVE bucket/ACL and physical Android validation remain pending.
