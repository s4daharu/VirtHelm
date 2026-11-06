# ALERT-001 foreground incident inbox implementation

Status: source-level M2/ALERT-001 increment with local model/controller/widget coverage. It is **not** background monitoring, Android notification delivery, a paging SLA, live PVE 8.4/9.2 validation, or production release certification.

## Scope

VirtHelm now has a fifth bottom-navigation destination, **Incidents**, with a badge showing the current retained incident count. The inbox is evaluated only from data already loaded for the active connection:

- explicit node `offline` inventory states are critical incidents;
- other non-`online` node states are warnings rather than being treated as healthy;
- recent server tasks are incidents only when the normalized task-list state is an explicit failure;
- session-local tracked mutations become incidents when their verified outcome is failed or unknown.

The inbox supports local All/Critical/Warnings filtering. A node incident can open the existing session-scoped node detail route. A task incident can open the existing read-only task detail route only while that exact node/UPID remains known to the active connection.

No additional PVE endpoint is introduced.

## Conservative refresh semantics

A successful inventory refresh is authoritative for node-state incidents because the existing inventory object is retained when the inventory request fails. Therefore network loss cannot erase a previously visible node incident.

Recent task history can be partially readable across nodes. When a task-history refresh is incomplete because of permission denial, node failure or malformed rows, VirtHelm retains previously observed failed-task incidents in a bounded in-memory set while also showing newly visible failures. A later complete task-history refresh may resolve those retained failures. If the entire task-history request fails, the previous server-task list and incidents remain visible.

At most 60 task incidents are retained from incomplete task-history reads. Retention is connection-session-only and clears on profile activation/deletion.

This implements the monitoring requirement that **unknown is not healthy** and avoids falsely showing an incident as resolved merely because a read source disappeared.

## Privacy and safety

The incident center is entirely in-app and foreground-only. This increment adds no:

- Android notification permission or notification channel;
- WorkManager/background poll;
- self-hosted relay or push registration;
- persistent incident database/history;
- acknowledgement, quiet hours, cooldown or hysteresis;
- user-configurable CPU/storage threshold;
- mutation or automatic remediation.

Task incident cards do not display UPIDs. UPIDs remain available only after an explicit drill-down to the existing task detail surface, which already treats them as local operator references. No task log content is copied into incident state.

Node names and task resource identifiers remain visible inside the unlocked app because they are already visible on the existing node/task screens. Nothing is exposed to a lock screen by this increment.

## Verification added

Synthetic regressions cover:

- explicit offline and unknown node states, while online nodes stay non-incidents;
- explicit failed server tasks without treating successful or terminal-unknown rows as failures;
- failed/unknown session tasks and deterministic critical-before-warning ordering;
- retention of a failed task incident across an incomplete task-history refresh;
- removal of retained failures after a later complete clean task-history refresh;
- incident badge/tab rendering, absence of UPID text in the inbox, safe task-detail drill-down and stale-data warning after Android default-network loss.

The app version is bumped to `0.1.11+1`. Repository CI remains the formatter/analyzer/test/debug-APK gate for the pushed commit.

## Deliberately deferred

This does **not** complete ALERT-002 through ALERT-014 or Android-polish notification stories. Configurable thresholds, state-machine acknowledgement/history, quiet hours/cooldown, WorkManager checks, lock-screen privacy controls for system notifications, notification deep links, certificate/backup reminders and relay/webhook integration remain gated future work.

Live PVE 9.2/8.4 node/task payloads, ACL variants, partial multi-node reads, 200-guest/task performance, TalkBack/font-scale behavior and physical Android lifecycle/network testing remain required before release claims.
