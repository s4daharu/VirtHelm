# Physical Android UI review and overhaul backlog — 2026-11-24

**Tested:** signed VirtHelm 0.1.76 ARM64 prerelease, build 537, commit `1943108`,
on a Galaxy S25 Ultra running Android 17 (API 37). A separate synthetic
0.1.77 debug build was subsequently checked on the same phone, as noted below.

## Device observations

- Opened all five main destinations (Home, Guests, Tasks, Incidents and
  Settings) at the device's original font scale and at Android font scale
  `2.0`. The five destinations remained reachable. Also opened Connections
  and the guest, node and storage overviews; verified that the guest detail
  tabs could scroll horizontally at `2.0`.
- Let the snapshot age naturally. The guest detail showed a stale warning and
  disabled mutation controls. Home, guest and node content still used
  current/live wording for the outdated measurements, as detailed below.
- A spot check of the Android accessibility tree surfaced labels for the
  five destinations, Refresh inventory, Switch connection, Manage
  connections, High contrast and Reduce motion. A complete spoken TalkBack
  traversal, focus order and announcement changes were **not** verified.
  Original device font and accessibility settings were restored.
- No profiles were edited, no guest operations were submitted, and no task
  logs were opened. No confirmation dialog was exercised against a real
  guest. Use disposable guests for the physical dialog pass; synthetic
  narrow/large-text coverage already exists for selected dialogs.

## Backlog ordered by impact

| Priority | Screen | Finding and proposed change |
|---|---|---|
| P1 | Shared header, Home and resource details | Addressed in 0.1.77: freshness has its own line, stale measurements and badges are marked last observed, and the outage message is tied to Android's default-network signal. Compact connection chrome remains a separate layout item. |
| P1 | Bottom navigation | At font scale `2.0`, **Incidents** broke into `Incident` and `s`, misaligning the destination. Use a layout that adapts to text scale rather than shrinking text. Keep visible destination cues, full screen-reader labels, selected state and generous touch targets. |
| P1 | Guests and Tasks | In wide-status rows at `2.0`, even a short guest name was ellipsized and a task name broke mid-word. Reflow identity, running/result status and secondary controls onto separate lines as needed. Keep node/type/VMID findable and full names accessible. In Tasks, move raw UPIDs and exit metadata below scan-critical content or into Details; this does not require persisting task logs. |
| P1 | Incidents | The introductory explanation took almost the full first screen at `2.0`, hiding the inbox tabs, search and empty state below the fold. Put the inbox status, review list and core controls first. Keep a one-line limitation and put the full privacy, history and correlation explanation in accessible help. |
| P1 | Destructive confirmations | At `2.0` the deletion dialog opened the keyboard immediately and scrolled the target and data-loss warning out of view. The 0.1.77 source follow-up starts with the warning and no automatic keyboard, and replaces the form with a Cancel-only message when the reviewed inventory is no longer safe. Retest on-device and apply the same checks to snapshot delete/rollback, migration and provisioning; retain all existing gates. |
| P2 | Home | The large connection hero and capacity caveats pushed node/storage summaries below the first screen even at normal scale. Compress connection chrome and prioritize infrastructure status and incidents. Keep capacity evidence and limitations available without presenting missing data as healthy. |
| P2 | Guests and guest detail | Two horizontal chip rows plus search crowded the list, and later detail tabs were not discoverable without swiping at `2.0`. Separate browsing/filtering from provisioning, and provide an obvious tab overflow or scale-aware section menu. Keep the guest action area usable without repeating long stale text in both the card and the pinned footer. |
| P2 | Settings and Connections | Connection management and its controls consumed substantial vertical space. Group by intent (connection, appearance/accessibility, refresh, monitoring/privacy), shorten summaries and make the TLS status distinct from secondary actions. Keep Remove explicitly confirmed and separate from routine actions. |
| P2 | Storage | Content-type strings and capacity values competed for room in list rows, truncating some capacity text even at normal scale. Prioritize the name, state and percentage; wrap used/total values and move the full content-type list to details. |

## 0.1.77 synthetic device follow-up

- The 0.1.76 baseline passed [Android CI](https://github.com/s4daharu/VirtHelm/actions/runs/45422464796)
  and [signed prerelease verification](https://github.com/s4daharu/VirtHelm/actions/runs/45423620402).
  This follow-up changes inventory presentation and confirmation behavior, not
  PVE requests, mutation preflight, credential handling, or Android signing.
- A separate debug package with no Internet permission and no live PVE
  gateway showed distinct **Live snapshot**, **Last observed snapshot**,
  and **No default network** states at Android font scale `2.0`. With a
  pre-aged synthetic snapshot left in the foreground, the guest overview
  relabeled itself and its power action disabled at expiry without a refresh.
  The installed signed 0.1.76 app was not replaced.
- Shutdown showed the target and TLS warning with both buttons visible at
  `2.0`. A dialog opened before expiry still appeared to allow confirmation
  after the action bar disabled. Rebuilding and repeating the same test
  verified that Confirm became disabled at expiry, the reason and Cancel
  remained visible, and the controller's existing preflight was unchanged.
  No action was submitted.
- The deletion follow-up has a narrow-screen widget regression for the
  initial target and warning, the typed and backup-acknowledgement gates,
  and invalidation when the snapshot becomes stale. That specific change
  still needs a signed-build device recheck.
- Android reported TalkBack bound and touch exploration active, but its
  setup screen intercepted the test. Spoken announcements and complete
  focus order were not verified. Device accessibility and font settings
  were restored.

## Next checks

- Reproduce the P1 items and build widget regressions at 320dp, 360dp and
  the reviewed phone width, with normal and maximum system text. Test long
  names, stale/partial data, and empty/populated lists.
- Run a spoken TalkBack pass with a human operator: destination selection,
  top-to-bottom focus order, icon-only controls, live/stale announcements,
  and keyboard/Cancel focus in confirmation dialogs. On a disposable test
  profile, verify the exact target, risk warning and disabled reason remain
  visible before confirmation at large text. Do not relax typed confirmation
  or stale/session/permission guards during the redesign.
- Notification delivery, Doze, VPN/radio interruptions, light/high-contrast
  themes, the versioned PVE lab matrix, and production certification remain
  separate checks.
