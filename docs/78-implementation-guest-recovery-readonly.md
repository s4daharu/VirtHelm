# Read-only guest recovery visibility — 2026-11-08

This increment completes the remaining source-level **M3 Safe Operator read-only recovery visibility** planned in [32-delivery-epics-sequencing.md](32-delivery-epics-sequencing.md): guest snapshot inventory plus bounded backup-status visibility. It does **not** enable snapshot mutation, backup execution, archive verification, or restore.

## Scope

- Adds an on-demand Recovery tab to QEMU and LXC guest details.
- Reads the exact visible guest's snapshot inventory with `GET /nodes/{node}/{qemu|lxc}/{vmid}/snapshot`.
- Shows the Proxmox `current` pseudo-entry separately from real snapshots.
- Displays snapshot parent, creation time, description and VM-memory metadata only when supplied and safely parsed.
- Shows recent `vzdump` task outcomes only when the existing bounded recent-task window associates them with the exact guest VMID.
- Keeps snapshot responses page-local and transient; no snapshot metadata is persisted.

The endpoint shape follows the existing typed guest-path contract. **Live PVE 9.2 and 8.4 schema/ACL evidence is still required** before compatibility or permission coverage is claimed.

## Safety boundary

Snapshot inspection reuses the same fail-closed route boundary as guest metrics: active profile ID, connection generation, exact node, guest kind and VMID must still match the live inventory before the request and after it returns. Explicit Android default-network loss blocks a new read, and an observed HTTP 401 invalidates authenticated live state through the controller's existing auth-loss path.

No new POST endpoint exists in this increment. Snapshot create, rollback and delete remain unavailable. Backup execution and restore remain unavailable.

A successful `vzdump` task is shown only as a **task outcome**. The UI explicitly states that this does not prove a backup archive exists, was verified, or is restorable. Archive discovery, backup schedules, retention, verification/confidence and restore require their own contracts and evidence.

## Parsing and bounded behavior

- Snapshot responses must be lists; malformed top-level responses fail explicitly.
- At most 500 entries are parsed locally.
- Invalid rows and invalid snapshot names are counted and ignored without discarding valid neighboring rows.
- Names/parents are bounded and reject control characters.
- Descriptions are sanitized of unsafe control characters and capped at 500 characters.
- The `current` pseudo-entry is ordered first; real snapshots are ordered newest-first when timestamps exist.
- Existing GET retry policy remains unchanged: only transient idempotent reads may retry, at most three total attempts. TLS/auth/permission/redirect failures are not retried.

## Automated coverage

Three regressions accompany the increment:

1. gateway path/method/bounded parsing for the guest snapshot GET;
2. controller read-only behavior and stale-generation rejection;
3. Recovery-tab on-demand loading, exact-VMID backup-task scoping and profile-switch redaction.

The existing large-text guest-detail test now also traverses Recovery. Repository smoke checks require the new model, gateway, controller, UI safety wording and this implementation note.

## Remaining gates

This source-level milestone does not satisfy release certification. Still open are real PVE 9.2/8.4 snapshot fixtures and ACL cases, physical Android lifecycle/TalkBack/performance validation, backup archive discovery and verification, snapshot mutation review, backup execution, restore safety, independent security review and production certification.
