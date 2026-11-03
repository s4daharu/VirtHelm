# Domain Models and Normalization Rules

## Main entities
```text
ClusterProfile { id: UUID, label, baseUri(https), authKind, credentialRef,
                 lastConnectedAt?, serverVersion?, tlsTrustConfigRef? }
GuestKey { profileId, node, guestType(qemu|lxc), vmid:int }
Guest { key, name?, status:GuestState, cpuFraction?, memBytes?, maxMemBytes?,
        diskBytes?, maxDiskBytes?, uptimeSeconds?, tags[], fetchedAt }
Node { profileId, name, status:NodeState, cpuFraction?, memoryBytes?, maxMemoryBytes?,
       uptimeSeconds?, fetchedAt }
Storage { profileId, node?, storageId, type?, active?, totalBytes?, usedBytes?, fetchedAt }
Task { profileId, node, upid, type?, subjectId?, status, exitStatus?,
       startedAt?, endedAt?, logSummary? }
ResourceSnapshot<T> { value:T, fetchedAt, stale, source, profileId }
```

Use nullable fields for fields that may be absent, not default zero. `Unknown` status is a first-class enum; never convert unknown to `Stopped` or `Offline`.

## Units, boundaries, and formatting
- PVE common usage metrics use `cpu` fractional utilization; display `% = cpu * 100` only once confirmed by endpoint schema/version. Never multiply by cores a second time.
- `mem`, `maxmem`, `disk`, `maxdisk` are generally bytes; format in IEC units (KiB, MiB, GiB), differentiate used vs allocated vs total and node vs guest.
- `uptime` generally seconds. Show minutes/hours/days; never treat as Unix epoch.
- Unix timestamps may be in seconds; convert to UTC then display Android local timezone. Do not assume milliseconds.
- To avoid invalid calculations: null or zero denominators => “N/A”; nonfinite fractions => “N/A”; clamp display if out-of-range but preserve raw value for diagnosis.
- IDs are `int` for `vmid`; node and storage IDs are strings. Preserve full `UPID` punctuation as opaque input, encode when used in URLs.
- Some JSON numeric values can decode as int or double; use controlled parsing `(value as num?)?.toDouble()` after type validation; avoid bare casts of optional numbers.

## Parsing contracts
- Decode server JSON once in service; validate `data` type according to endpoint; report `ProtocolError` if unexpected.
- Retain unknown fields only in diagnostics if sanitized; don't persist potentially sensitive raw JSON.
- Sort null names after named resources, stable key fallback; duplicate VMIDs across profiles not equal.
- `status` from server may introduce new values; map unrecognized to `unknown` and optionally show raw sanitized status detail.

## Sensitive vs non-sensitive data
**Sensitive:** token secret, access ticket, CSRF token, username/password, VNC tickets, task logs that contain secrets, private connection endpoints under sensitive user policy. Only secrets in encrypted storage, temporary memory when needed. Avoid exporting credentials in backups. **Potentially private:** hostname/IP, guest names and tags; local cache optional, minimized, and cleared upon disconnect/profile delete. No user cloud sync in MVP.
