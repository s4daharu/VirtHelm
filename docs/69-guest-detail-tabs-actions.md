# Guest detail tabs and bottom action bar

This note records the guest-detail restructure. It is source-level synthetic coverage only; it is not physical Android, TalkBack, performance, live PVE or release evidence.

## Structure

The guest detail route now has three tabs inside one `DefaultTabController`:

- **Overview** — guest identity, freshness/guard copy, live CPU/memory, disk usage, uptime and the preview-scope note.
- **Metrics** — the existing explicit 1h/24h/7d RRD history loader, sample count, CPU/memory sparkline cards and text alternatives.
- **I/O** — cumulative network and disk byte counters with the existing “not live rates” explanation.

A persistent bottom action bar replaces the long list of power-control cards:

- Primary action is **Start** for a stopped guest and **Shut down** for a running guest.
- The overflow menu exposes the remaining actions, with per-action enablement based on the same live-state policy.
- An operation-pending, stale, incomplete-inventory, refreshing or moved-guest reason is shown directly above the buttons.
- Submit progress is shown in the primary button.

## Safety boundaries

- `execute` still opens the same typed-risk confirmation dialog, including exact target, profile, node, kind/VMID, force-stop warning and contextual TLS notice.
- Profile ID and connection generation are still checked before opening and before accepting the confirmation.
- Guest writes still require a fresh clean inventory, live preflight, per-guest single-flight and the existing unknown-outcome lockout.
- No API endpoint, credential, persistence, retry or background behavior is added.

## Verification

- `flutter analyze --fatal-infos` passes.
- The full Flutter suite passes locally: 161 tests.
- Added a 320dp/200% text-scale guest-detail regression that switches all three tabs and checks for layout overflow.
- Existing guest metrics, I/O, confirmation-redaction and session-switch tests pass after selecting the relevant tab or the bottom action button.
- Physical Android TalkBack, touch targets, 360/393/412dp screenshots and performance benchmarks remain open.

## Remaining work

Guest-list filter consolidation, a task timeline with virtualization, a full-screen threshold-rule editor with searchable grouped targets, dedicated connection management, AMOLED/high-contrast themes, app lock/biometrics, notifications and golden screenshots remain future work.
