# Read-only guest configuration inspection — 2026-11-08

This increment implements **GUEST-04 configuration read**, the roadmap dependency that precedes future create/clone/migration work. It is deliberately a read-only M4 foundation and does not enable configuration edits or any new mutation.

## Scope

- Adds an on-demand **Configuration** tab to QEMU and LXC guest details.
- Reads the exact visible guest with `GET /nodes/{node}/{qemu|lxc}/{vmid}/config`.
- Shows reviewed compute, platform/boot, storage and network fields when present.
- Supports bounded dynamic disk/mount and network-device keys while keeping all values transient.
- Adds no configuration persistence, export, telemetry or write endpoint.

## Privacy and parsing boundary

VirtHelm does not render the raw config map. The model copies only explicitly reviewed fields. Passwords, cloud-init passwords, SSH keys, arbitrary QEMU arguments, hook scripts, descriptions and unknown future keys remain outside the display model.

Displayed scalar values accept only strings, JSON numbers and booleans, remove unsafe control characters and cap text at 300 characters. Dynamic storage and network lists are capped at 32 entries per section. Unknown/unsupported fields are counted only so the UI can say data was withheld without exposing it.

This deliberately favors incomplete-but-safe inspection over accidentally surfacing a newly introduced sensitive server field.

## Session and authorization safety

The controller requires the active profile ID, connection generation and exact node/kind/VMID to match live inventory before the request and again after it returns. Android default-network loss blocks a new read. An observed HTTP 401 follows the existing authenticated-read-loss path and invalidates live write safety until a clean authenticated refresh.

If the guest disappears or moves after a refresh, previously loaded configuration is no longer rendered. The same increment tightens Recovery so previously loaded snapshot metadata is also hidden when the exact guest is no longer present.

## Automated coverage

Four new regressions cover:

1. QEMU/LXC allowlist parsing and explicit secret/free-form withholding;
2. GET-only `/config` gateway behavior and non-leakage of withheld values;
3. controller read-only behavior and stale-generation rejection;
4. on-demand Configuration UI, withheld-field messaging, guest-removal redaction and profile-switch redaction.

The narrow-phone 200% text-scale guest-detail test now traverses the Configuration tab as well.

## Remaining M4 gates

This is not permission to implement the write side blindly. Configuration editing, snapshot/backup execution, create/clone/migration, ticket/MFA and console remain gated by exact PVE 8.4/9.2 contract and ACL evidence, disposable-lab tests, destructive/unknown-outcome handling, UX confirmation design and the release criteria in [33-test-acceptance-release-gates.md](33-test-acceptance-release-gates.md).
