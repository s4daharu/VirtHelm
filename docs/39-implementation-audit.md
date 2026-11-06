# Implementation audit — 2026-11-04

> Historical audit record. The current whole-repository review is [docs/45-full-implementation-cross-check.md](45-full-implementation-cross-check.md); subsequent slices added expanded guest filtering/sorting and profile-scoped saved views.

## Purpose
This audit cross-checked the implemented Flutter source, tests, generated Android runner, CI behavior and implementation/status documentation. It is a source-level and automated-build audit, **not** a substitute for the real PVE/device release matrix.

## Issues found and corrected
- Corrected node task-list semantics: request active+archive rows and distinguish raw list `RUNNING`/terminal result from task-detail `status/exitstatus`.
- Added gateway-level request tests for origin, Authorization, redirect rejection, task query parameters, partial 403 storage reads, TLS certificate failure and exact one-POST lifecycle path.
- Made inventory refresh single-flight and task verification bounded; unverified terminal outcomes become `unknown` and remain mutation-blocked.
- Made token revocation discovered during supplemental reads, preflight or task polling fail closed for future writes.
- Added malformed guest inventory accounting so ambiguous/invalid inventory cannot silently authorize mutation.
- Strengthened cross-profile same-VMID, profile deletion, duplicate profile persistence and stale-snapshot regressions.
- Fixed profile persistence ordering/rollback so duplicate IDs cannot overwrite an existing encrypted secret.
- Added node/guest uptime and explicit guest freshness.
- Strengthened force-stop confirmation with exact connection/node/type/VMID identity.
- Audited the generated Flutter 3.44.4 Android runner and added release Internet permission, cleartext/backup disablement, minSdk 26, and removal of debug-key release signing.
- Committed `pubspec.lock`, pinned the Flutter/Dart floor, and changed CI from in-place formatting to an immutable format gate plus coverage tests.
- Removed stale “documentation-only/preimplementation” claims.
- Added profile-isolated local guest favorites and basic favorites/running/stopped workload filtering without adding server-side mutation or unverified API contracts.
- Subsequent user-requested TLS change: added default-off, explicitly confirmed per-profile certificate bypass for any HTTPS host, native exact-host/port scoping, persistent UI warnings and regression coverage. This is a deliberate security tradeoff, not trusted-certificate enrollment; physical-device/security review remains open. See [TLS option](40-profile-tls-option.md).

## Implemented scope that remains intentionally incomplete
The current code is an M1 foundation/safe-operator implementation plus an M2 read-cockpit slice. Subsequent work implemented local type/node/tag/pool filtering, deterministic guest sorting, profile-scoped named saved views and a bounded guest CPU/memory RRD slice. The remaining M2 roadmap still includes broader node/storage charts, notification center/alerts, richer grouping/topology views, persistent offline caching and formal accessibility/performance work. Later milestones cover ticket/MFA, console, snapshots/backups, PBS/PDM, provisioning/migration and infrastructure changes.

Those items are **not defects in the current slice unless advertised as implemented**; repository copy must continue to mark them deferred.

## Release blockers still open
- PVE 9.2 and 8.4 real-server endpoint, ACL, QEMU/LXC and fault-injection evidence.
- Single-node and multi-node tests with limited/revoked tokens and storage/task variants.
- Physical Android certificate validation, secure-storage backup/restore/device-loss behavior, min/current API coverage, VPN/network switching.
- TalkBack, 200% font scale, 200-guest performance/power/request-count evidence.
- Dependency/advisory/license/SBOM review, repository secret/history scan, production signing, signed release artifact and rollback/release review.

Therefore the audited source can be integrated into `main` after CI passes, but it must **not** be described as production-ready or 100% release-verified.
