# Advanced QEMU/LXC Guest Management — Workflow RFC
These are proposed workflows. **Every exact endpoint, parameter, privilege and behavior remains PENDING on PVE 9.2 and 8.4 until versioned API viewer and test-lab evidence.** QEMU and LXC are distinct APIs; never assume feature parity.

## Module capabilities
- Inventory: status, normalized CPU/memory/storage, uptime, agent-reported guest details when available, tags, pools, HA group membership, location and historic tasks.
- Power: start, graceful shutdown/reboot, forced stop, suspend/resume when supported; avoid equating pause/suspend with power off.
- Configuration: read and proposed edits for vCPU/memory/ballooning, disk controllers, boot options, NICs, cloud-init, startup order, CPU types; validate hotplug/offline requirements.
- Provisioning wizard: QEMU from ISO/template/clone; LXC from available template; selected storage and bridge, address/cloud-init, resources, credentials avoidance, uniqueness and reservation checks.
- Clone/template: full/linked clone choice only when backend/storage allows; source/destination and resulting VMID explicit.
- Snapshot lifecycle: list/tree, create with memory only if supported, descriptions, rollback and delete. Warn that snapshots are **not backups**.
- Backup: schedule/one-off creation, retention visibility, verify latest jobs, document restore dry-run proposal.
- Migration: between cluster nodes, validate storage accessibility/network/HA state, preflight expected downtime and active tasks, UPID progress.
- Destructive: stop/delete/disk detach/remove protected behind named resource confirmation and current backup/quorum safety gate.
- Console: on-demand separately authenticated QEMU noVNC or LXC terminal after [console RFC](08-console-rfc.md), not through token-only auth.

## Example preflight: move guest
1. Read source guest and nodes; verify profile, guest type, VMID, lock, HA ownership, workload state and freshness.
2. Fetch destination capabilities/storage/network constraints; compute what is known and **unknown** (e.g. passthrough devices may prevent migration).
3. Estimate impact from server-sourced metadata; don't assert live migration without verified compatibility.
4. Confirm source/destination, estimated outage risk and ticket/ACL; show mutation options and disable bulk execution when unsupported.
5. Submit exactly one request; persist non-secret operation correlation and UPID, monitor server task.
6. Refresh guest identity/location only after task terminal success; on timeout/partial failure, show **investigation** rather than automatic retry.
7. Show linked logs and runbook, never claim rollback of a migration unless a separate action really happened.

## Example restore risk contract
Use guided wizard: pick source snapshot/backup -> show timestamp/time zone and target storage/VMID -> validate disk/CPU/network and overwrite implications -> require explicit target acknowledgment -> create task -> monitor -> post-restore boot/check evidence. Restore can overwrite and be non-idempotent; no auto-resubmit. A successful restore task **does not guarantee** guest boot/application correctness.

## Proposed domain API
- GuestIdentity(profileId, node, guestKind, vmid): immutable key; guard against stale/moved-node lookups.
- GuestCommand: typed union Start/Shutdown/Stop/Reset/Clone/Snapshot/Migrate/Restore/Delete; no arbitrary URL/path command.
- PreflightSnapshot: resource ETag/digest if available, observedAt, ACL hints, blockers, unverifiedConditions, confirmationLevel.
- OperationState: Draft -> Preflighted -> Confirmed -> Submitted(UPID?) -> Running -> Succeeded/Failed/Unknown -> Postchecked.
- Task DTO: raw UPID opaque; status and exitstatus interpreted only when confirmed by actual API response.

## Permission and concurrency safeguards
PVE server ACL is authoritative. Limit “operator power” tokens by paths. Mutation request must bind to profileID and freshly read guest key; revalidate on confirmation. Unique client-side operation nonce is **for local duplicate-suppression only**, not proof the server deduplicates POSTs. Keep no batch destructive operations in F1.

## Console usability acceptance (separate gated RFC)
Mobile virtual keyboard (Ctrl/Alt/Del, arrows, Esc, F1–F12), mouse touch modes, resize-to-fit, clipboard opt-in, orientation switching, reconnect, password masking; no credential or VNC ticket leaks in logs/URLs; certificate trust is identical to REST. Prototype and security test WebView versus a maintained VNC implementation before declaring it deliverable.
