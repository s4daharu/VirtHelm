# Task summary, compact rows and lazy task lists

This note records the Tasks-tab presentation overhaul. It is source-level synthetic coverage only; it is not physical Android, TalkBack, performance, live PVE or release evidence.

## Structure

- Added a task summary card with counts for **Running / Succeeded / Failed / Unknown** recent server tasks.
- Session tasks and recent server tasks now render through sliver lists instead of eagerly building every card.
- Recent server task rows are compact and fully tappable:
  - State icon and status badge.
  - Operation label and resource ID.
  - Node and relative time.
  - Exit status and truncated UPID where available.
  - Chevron affordance opens the existing bounded task-detail route.
- The separate per-card “View details” button was removed in favour of the whole-row target.
- Search, node/state filters, clear-filter recovery and the snapshot count remain unchanged.

## Safety boundaries

- Read-only presentation. No task mutation, polling, persistence or log caching is added.
- Task details still perform on-demand, bounded GETs and remain profile/generation scoped.
- UPIDs remain visible but truncated in the list; the detail route retains the full selectable UPID.
- No API, credential or transport behavior changes.

## Verification

- `flutter analyze --fatal-infos` passes.
- The full Flutter suite passes locally: 161 tests.
- Task history/filter and task-detail regressions pass with the whole-row target; the 320dp/200% shell regression still opens the Tasks tab without overflow.
- Physical Android TalkBack, touch-target, 200-task performance and 360/393/412dp review remain open.

## Remaining work

A full-screen threshold-rule editor with searchable grouped targets, dedicated connection management, AMOLED/high-contrast themes, app lock/biometrics, notifications and golden screenshots remain future work.
