# Functional Scope and Prioritization

Legend: **P0** mandatory MVP; **P1** follow-up after MVP; **P2** further research. This is a **plan**, not a claim of implemented functionality.

| ID | Priority | Feature | Required checks |
|---|---|---|---|
| F01 | P0 | Profile create/edit/delete (host, alias, token) | HTTPS and host validation, no secret disclosure, cluster isolation |
| F02 | P0 | Token auth, test connection, server version | 401/403/TLS/offline handling, token privilege separation |
| F03 | P0 | Cluster overview and node states | clusters and one-node installations, empty/inaccessible nodes |
| F04 | P0 | VMs (QEMU) and containers (LXC) list/details | node/vmid identity, VM type-specific data and status |
| F05 | P0 | Filter/sort/search, favorite guests locally | no excessive queries; missing or duplicate names |
| F06 | P0 | Status metrics CPU/memory/disk/uptime | correct metric units; stale timestamps; no false precision |
| F07 | P0 | Start and graceful shutdown | confirmation, submit UPID, task state, races |
| F08 | P0 | Force stop and reboot | explicit force warning, task state, guest-type support mapping |
| F09 | P0 | Task list and details | error exit status not treated as successful |
| F10 | P0 | Storage overview read-only | permissions; content types and enabled/disabled |
| F11 | P0 | Local settings (theme, refresh, display prefs) | never store auth secrets in prefs |
| F12 | P0 | Offline/permission/timeout states | retry only idempotent reads automatically |
| F13 | P1 | Username/password ticket auth | CSRF, expiry, 2FA and cookie handling validation |
| F14 | P1 | Snapshots list/create/rollback | per guest type and storage-specific risk; approval gates |
| F15 | P1 | Backups list/trigger and task monitor | storage, schedule, restore safety, large data transfers |
| F16 | P1 | Node detailed usage / graphs | RRD metrics normalization, timezone and interval |
| F17 | P1 | Cluster tasks filtering and logs | permission tests; sanitization and redaction |
| F18 | P1 | Guest configuration read-only | optional fields, privilege/path testing |
| F19 | P2 | noVNC and xterm.js/terminal console | separate session/RFC, WebSocket security, 2FA |
| F20 | P2 | SPICE and advanced remote I/O | OS integration/security spike |
| F21 | P2 | Guest create/clone/migrate/delete | high-risk workflows, extended forms, storage and network validations |
| F22 | P2 | Node reboot/stop, Ceph, SDN, HA changes | separate privileged admin RFC and disaster recovery |
| F23 | P2 | Local notifications | platform permission, background execution, privacy architecture |

## Permissions and feature behavior
- Present only actions supported by guest type **and** backend endpoint. Server-side ACL is authoritative; UI must handle 403 even after prior status/permission checks.
- API tokens with separated privileges can have fewer rights than the associated user. Never force broad `root@pam` privileges for convenience.
- An API token **does not cover console endpoints**. Do not offer “token console mode”. Use a separately designed user-session flow, if implemented.
- No “Shutdown host” or “Delete VM” one-tap shortcuts in the MVP.

## Screen-level acceptance example
Guest details should show `type: QEMU | LXC`, `vmid`, node, name, status, CPU/mem/disk/uptime with units, last refresh timestamp; show states for absent data. Start should be disabled when already running only as a convenience; server remains the authority. Action result contains task ID where endpoint provides one. Unknown status and stale data trigger extra confirmation instead of blind mutation.
