# VirtHelm M2 — profile-scoped saved guest views

## Scope
This slice implements HOME-006 saved smart filters using only local application preferences. A saved guest view captures the current search text, status filter, QEMU/LXC filter, optional node filter, and guest sort order. It does not add a Proxmox endpoint, make a network request, or authorize a mutation.

Each connection may keep at most 12 named views. Names are trimmed, limited to 40 characters, and compared case-insensitively. Saving the same name updates the existing view while retaining its local identifier. Deleting a connection removes its saved views on a best-effort basis after credential/profile removal.

## Isolation and malformed-data behavior
Saved views are keyed by profile ID and are loaded when that profile is activated. UI save/delete intents include the profile ID captured by the rendered guest screen; if the active connection changes before the local write, the controller ignores the stale intent. Switching profiles resets the currently applied transient view and ordinary filter state.

Persisted rows are validated before use. Unsupported enum/status values, invalid identifiers, oversized fields, duplicate IDs/names, and malformed JSON rows are ignored rather than crashing the guest browser. A corrupted saved-view document produces no views; it never changes credentials or write-safety state.

## UX behavior
The guest browser exposes a **Save view** chip and profile-local chips for stored views. Applying a saved view restores its search/filter/sort criteria. Any manual change makes the current criteria custom again. Deleting the selected saved view leaves its currently applied criteria in place, so deletion cannot unexpectedly broaden the visible workload set.

Saved views may reference a node no longer present in the latest inventory. In that case the ordinary empty state is shown; the app does not silently rewrite the user's saved criteria.

## Verification boundary
Automated coverage checks model validation, profile isolation, same-name update behavior, cleanup on profile deletion, malformed persistence, the 12-view limit, stale-profile write rejection, and widget save/restore behavior. The normal branch CI remains responsible for formatting, analysis, all Flutter tests and Android debug compilation.

This local-only feature does not satisfy the broader M2 release gate. Physical accessibility/large-text checks, 200-guest performance evidence, live PVE 8.4/9.2 compatibility evidence, charts/RRD, alerts/notification center, tag/group filters and persistent offline cache remain open.
