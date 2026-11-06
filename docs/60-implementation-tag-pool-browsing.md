# Tag and pool browsing — read-only discovery metadata

**Increment:** 2026-11-06. This source-level milestone implements the planned HOME-007 discovery slice using metadata already present in the cluster inventory. It does **not** establish live PVE 9.2/8.4 compatibility, ACL completeness, or production readiness.

## Scope

- QEMU/LXC inventory rows may expose optional `tags` and `pool` metadata from the existing `GET /cluster/resources` response.
- Tags are parsed from the Proxmox semicolon-delimited string, trimmed, de-duplicated without changing case, bounded to 32 entries, and limited to 64 characters per tag.
- Pool identifiers are trimmed and bounded. Missing, wrong-type, oversized, or control-character metadata becomes unavailable instead of invalidating the guest record.
- Guest search now includes tag and pool text.
- The Guests view adds exact tag and pool filters alongside existing status/type/node filters and sorting.
- Tag/pool filters are persisted only when the operator explicitly saves a profile-scoped named guest view. Existing saved views without these fields remain compatible.
- Guest list rows and guest detail show available pool/tag metadata.

## Safety and privacy

This increment adds **no API request**, background poll, Android permission, write endpoint, or mutation parameter. Tag/pool metadata is presentation-only and cannot authorize, block, retarget, or modify a guest action. The existing action path still relies on exact profile/node/type/VMID identity, clean fresh inventory, live status preflight, and task tracking.

Malformed optional tag/pool metadata does not increment `malformedGuestRecords`; otherwise a decorative server field could incorrectly disable all guest mutations. Invalid core identity fields remain fail-closed exactly as before.

Saved views may persist operator-selected tag/pool names in SharedPreferences under the existing profile-scoped local metadata store. They never contain API credentials, task logs, RRD samples, or raw server responses. Android app backup remains disabled.

## Contract evidence and verification boundary

Proxmox upstream added virtual-guest tags to `/cluster/resources` in the PVE 7.2 line, and the current PVE resource tree continues to support tag-based browsing. The source implementation accepts an optional `pool` field when present but does not assume every guest or token can see one.

Automated coverage checks parser bounds, missing/malformed metadata behavior, case-sensitive tag identity, search/filter composition, saved-view backward compatibility, and UI save/restore behavior.

**Still open:** sanitized PVE 9.2 and 8.4 QEMU/LXC fixtures confirming exact tag and pool field presence, ACL behavior, case-sensitivity settings, nested pool naming, large inventories, and physical Android TalkBack/large-text/200-guest performance evidence.
