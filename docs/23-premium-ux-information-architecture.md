# Premium Android UX — Information Architecture and Design System
Design target: portrait Android **phone** (min 360dp width); landscape only where helpful for graphs/console, adaptive for foldable phone widths. Android-only Material 3. No tablet, desktop or web-specific target.

## IA: five destinations and global affordances
| Bottom navigation | Purpose | Primary views |
|---|---|---|
| **Home** | operational command cockpit | overview, severity summary, activity, favorite resources, daily health |
| **Explore** | find and inspect | clusters, nodes, guests, storages, tags, smart filters |
| **Tasks** | observe operations | live/recent tasks, failed log explorer, action history, timeline |
| **Alerts** | surface actionable signals | incident inbox, rules, alert history, notification preferences |
| **More** | advanced modules | backups, Ceph, HA, SDN, network, integrations, settings/security |

Global top app bar: current profile/site switcher always visible; explicit health/freshness dot; global search; context actions. Floating compose button **only** on contexts where permitted creation exists, never universal “do something” CTA.

## Screen inventory and responsibilities
1. Splash/locked state; connection chooser; add server + TLS trust enrollment; token permission test; ticket/MFA session flow (gated).
2. Dashboard: resource state strip, outage banner, uptime, 24h trend, utilization, latest tasks, favorites, quick safe actions.
3. Explore: hierarchical browse, smart filters, global search, saved views, “recently used” and permission-denied discoverability.
4. Cluster: status/quorum, capacity, HA, load balancer (9.2), nodes, tasks, cluster settings read-only.
5. Node: usage/graphs, disks, ZFS, storages, network, services, logs, updates; guarded maintenance.
6. Guest: overview, metrics, config, snapshots, backups, hardware, network, task history, console; tabs scroll horizontally **within** guest page.
7. Tasks/alerts: grouped by severity/profile with search, timestamps, copy-redacted support reference.
8. Operations: bottom sheet preflight -> typed-risk confirm -> UPID job status -> results/failure/runbook.
9. PBS workspace and PDM workspace (future separately authenticated).
10. Settings: themes, accessibility, refresh interval, privacy/telemetry opt-in, local cache, lock, trust store and export.

## Visual language specification
- Theme: Material 3 dynamic color optional; signature deep navy/charcoal + muted teal/cyan surfaces; neutral text with WCAG-tested contrast; semantic red/orange/green reserved for real state.
- Typography: large short numeric readouts, tabular figures for metrics, monospaced IDs only, max two information hierarchy levels in cards.
- Layout: 8pt spacing scale, 48dp minimum touch targets, density variants, responsive overflow and inset-safe buttons; never hide last action under IME or nav bar.
- Animations: 120–240ms purposeful transitions; skeleton loading; reduced motion setting obeyed; animations never mask stale/mutation uncertainty.
- Charts: readable axes and units, selectable ranges 1h/24h/7d/30d where server provides points; zoom/drag with accessible textual table.
- Feedback: subtle haptics on selection and successful confirmation, stronger haptic and text for destructive warning; don't use sound by default.
- Color alone never conveys status. Always pair icon, words and time.
- Empty/no access/offline/error/syncing/trust changed states get dedicated UX copy and obvious safe next steps.
- App lock and secret entry use privacy-sensitive secure screens; biometrics unlock **local access**, not PVE authentication.

## Premium differentiators
- **Incident-first cockpit:** health cards sorted by actionability, not just CPU percent.
- **Smart diff:** show configuration changes before/after a user-driven mutation where backend data permits.
- **Task story:** progress and related logs, linked resource, server-generated UPID, final verified state.
- **Context-safe quick actions:** start/shutdown only after up-to-date target, clear single-target confirmation.
- **Command palette:** phrases map to **navigation or draft actions**; never execute typed free-form requests without full preflight.
- **Offline reading room:** last-known inventory with giant STALE label, explicit age and read-only guard.

## Copy rules
Never say “fixed”, “backed up”, “restored”, “healthy”, “safe”, or “complete” until evidence supports it. Prefer “submitted”, “running”, “permission denied”, “last seen”, “verification pending”, “outcome unknown”. A UI error message must not include tokens, upstream cookie values, secret task log text or raw stack traces.

## Design deliverables
Figma or equivalent screen map, token sheet, component library, 360/393/412dp screenshots, Android dark/light/high-contrast snapshots, localization-ready string catalogue and TalkBack annotated flows. Acceptance: user can identify profile before every write; all high-risk actions have correct state/freshness; accessibility test passes.
