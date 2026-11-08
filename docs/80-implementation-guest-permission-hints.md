# Guest effective permission hints — 2026-11-08

This increment adds a read-only M4 capability-discovery foundation for one exact visible QEMU/LXC guest. It does **not** add a mutation, does not change existing power-action authorization, and does not claim that a reported privilege is sufficient to safely execute an unimplemented operation.

## Upstream contract

VirtHelm uses `GET /access/permissions?path=/vms/{vmid}` for the authenticated user/API token itself. Upstream Proxmox access-control source documents this endpoint as returning effective permissions for a user/token and permits each user/token to dump its own permissions. The response is a map of ACL path to privilege names with propagation flags.

The client requests one exact `/vms/{vmid}` path rather than the whole permission tree. This bounds disclosure and avoids persisting or rendering unrelated node, storage, pool or guest ACL paths.

## Scope and presentation

- Adds an on-demand **Access** tab to guest details.
- Shows reviewed guest-relevant privilege hints such as `VM.Audit`, `VM.PowerMgmt`, `VM.Backup`, snapshot, clone, migrate and selected `VM.Config.*` privileges.
- Treats a privilege as effective when the exact path map contains it, even when the returned propagation flag is false/non-propagating; that flag affects descendants, not the exact requested object.
- Does not render unknown privilege names individually. It reports only a count for additional valid privileges and ignores malformed privilege entries.
- Permission results are transient and never written to SharedPreferences, secure storage, exports or telemetry.

## Session and mutation safety

The controller revalidates active profile ID, connection generation and the exact node/type/VMID inventory identity before and after the permission read. Explicit Android default-network loss blocks a new read. A 401 follows the existing authenticated-read-loss path and invalidates live write safety until a clean authenticated refresh.

Permission hints do **not** unlock, disable or authorize existing power controls. Existing live inventory freshness, status preflight, exact-target guards, single-flight submission and server ACL enforcement remain authoritative. Likewise, seeing `VM.Snapshot`, `VM.Clone` or `VM.Migrate` does not enable those still-unimplemented M4 operations or prove that every companion privilege/storage/node requirement is satisfied.

## Automated coverage

Four regression layers cover:

1. exact-path permission parsing, including non-propagating grants and malformed entries;
2. GET-only `/access/permissions` request shape with `path=/vms/{vmid}`;
3. controller profile/generation/guest isolation with no mutation submission;
4. on-demand Access UI plus guest-removal/profile-switch redaction.

## Remaining gates

Live PVE 8.4/9.2 fixtures must still verify the endpoint response shape, token privilege-separation behavior and ACL edge cases. Physical Android accessibility/network lifecycle validation also remains open. Snapshot/backup execution, create/clone/migration, ticket/MFA and console stay gated by their own contract, destructive-action and release evidence requirements.
