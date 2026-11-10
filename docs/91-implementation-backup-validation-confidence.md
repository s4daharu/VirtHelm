# BKP-009 Partial: Backup Validation Confidence Card

**Date:** 2026-11-11  
**Version:** 0.1.44  
**Milestone:** M4 recovery operations / BKP-009 partial

## Scope delivered

VirtHelm now derives a deterministic, read-only backup validation evidence card for the exact guest Recovery view.

The card combines only evidence the PVE-only client already has:

- whether exact-guest backup archive visibility has been explicitly loaded;
- whether one or more matching archives are currently visible;
- exact QEMU/LXC + VMID identity already validated from each accepted volume ID;
- latest archive timestamp and size when PVE reports them;
- unusable/truncated storage-content response warnings;
- the newest visible recent `vzdump` task for the exact VMID.

No additional mutation or background API traffic is introduced.

## Confidence states

The card deliberately has only three states:

- **Not assessed** — archive visibility has not been loaded for the selected storage.
- **Insufficient evidence** — the storage was checked but no matching exact-guest archive is visible.
- **Partial evidence** — at least one matching exact-guest archive is currently visible.

There is intentionally no `verified`, `safe`, `healthy`, or `restorable` state in this PVE-only milestone.

A successful recent `vzdump` task cannot upgrade an unloaded or empty archive read. Conversely, a visible archive remains only partial evidence even if the newest task succeeded.

## Evidence dimensions

### Archive visibility and identity

Accepted archive rows have already passed the BKP-002 exact-identity parser:

- file style: `vzdump-qemu-{vmid}-...` or `vzdump-lxc-{vmid}-...`;
- PBS-style PVE volume IDs: `backup/vm/{vmid}/...` or `backup/ct/{vmid}/...`.

The card reports count, exact type/VMID identity, latest reported creation age, size when present, and incomplete-response warnings.

### Recent task evidence

The card independently shows the newest visible `vzdump` task from the current recent-task window as:

- running;
- succeeded only when terminal exit status is exactly `OK`;
- failed when terminal exit status is non-OK;
- unknown when terminal result is missing;
- not visible when the recent-task window contains no matching task.

Task history remains supporting evidence only. It never proves archive presence or integrity.

### Integrity verification

Integrity verification is always shown as unavailable in this milestone.

Proxmox Backup Server has distinct backup verification facilities that validate stored backup data against recorded checksums. VirtHelm's current PVE API-token connection does not connect to PBS verification state, execute verification, or inspect archive contents.

### Restore test

Restore-test evidence is always shown as unavailable. VirtHelm has not performed or recorded a tested restore for the archive, and this card does not authorize or enable restore.

## Safety boundary

The confidence card:

- is computed locally from transient Recovery data;
- performs no new POST/PUT/DELETE;
- performs no automatic GET;
- adds no persisted backup metadata;
- never bypasses the existing profile/generation/guest/storage redaction rules;
- cannot authorize a future restore mutation;
- never converts a protected flag, task success, archive size, or archive age into an integrity claim.

The `protected` storage flag remains retention/deletion metadata only and is not validation evidence.

## Automated coverage

Synthetic regressions cover:

- task success with no archive read remains **Not assessed**;
- task success with an empty exact-guest archive read remains **Insufficient evidence**;
- visible exact-guest archive becomes **Partial evidence** and never verified;
- malformed/truncated archive-read warnings remain visible evidence limitations;
- the newest task wins when recent task history contains mixed outcomes;
- a newer failed task is shown as failed without downgrading archive visibility into a false integrity conclusion;
- Recovery UI transitions from **Not assessed** to **Partial evidence** only after explicit archive loading;
- the UI states that PBS verification is unavailable and that the card never authorizes restore.

## Remaining gates

Still gated:

- PBS authenticated connector and per-snapshot verification state;
- checksum/integrity verification from a trusted source;
- backup freshness policy thresholds;
- operator-declared or automatically recorded tested-restore history;
- restore plan/conflict preflight;
- actual restore mutation;
- disposable PVE 8.4/9.2 plus PBS-backed integration fixtures and physical Android certification.
