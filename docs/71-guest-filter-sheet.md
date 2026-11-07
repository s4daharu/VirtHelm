# Guest filter sheet and compact filter chrome

This note records the guest-list filter overhaul. It is source-level synthetic coverage only; it is not physical Android, TalkBack, performance, live PVE or release evidence.

## Structure

The Guests tab no longer stacks four separate filter rows before the workload list. It now uses:

- Search with a filter button showing an active-filter count badge.
- A compact quick-status row: All / Favorites / Running / Stopped.
- Saved view chips, unchanged.
- Removable active-filter chips for type, node, tag, pool and non-default sort.
- A bottom sheet for **Type / Node / Tag / Pool / Sort**, with Reset and Apply actions.
- The existing workload count, freshness label and Clear filters action.

Applying or clearing filters remains local widget state. Saved views continue to store the same search, status, kind, node, tag, pool and sort criteria.

## Safety boundaries

- Presentation and local state only. No API request, credential, persistence or mutation behavior is added.
- Filters cannot authorize guest actions; guest writes remain tied to the exact profile, node, kind, VMID and fresh inventory.
- Saved-view compatibility is preserved for legacy views without tag or pool fields.
- Filter state still resets on profile switch.

## Verification

- `flutter analyze --fatal-infos` passes.
- The full Flutter suite passes locally: 161 tests.
- Guest browse/filter/sort and saved-view regressions were rewritten to exercise the filter sheet and active-filter chips instead of the removed popup-menu rows.
- The 320dp/200% text-scale shell regression still opens the Guests tab without layout overflow.
- Physical Android TalkBack, touch-target, sheet-at-scale and 200-guest performance validation remain open.

## Remaining work

Task timeline virtualization, a full-screen threshold-rule editor with searchable grouped targets, dedicated connection management, AMOLED/high-contrast themes, app lock/biometrics, notifications and golden screenshots remain future work.
