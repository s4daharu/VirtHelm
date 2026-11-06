# VirtHelm — whole-repository implementation cross-check (follow-up)

**Reviewed:** 2026-11-04. **Baseline:** `main` at `b90a4a7b4fc29a4122e4d33780198a1fbe181bb1` plus the F12 GET-retry feature branch and this audit's F09 task-history fix. **Assurance:** source-level review and GitHub Actions, **not** live PVE compatibility testing or a certified release.

## Verification scope and evidence boundaries

Inspected the tracked Flutter Android application, its models/gateway/controller/profile repository, guest filtering and saved views, connection and guest UX, task/status presentation, generated Android hardening scripts, CI and signed-prerelease workflow, lockfile/toolchain documentation, tests, and the complete documented implemented-versus-proposed feature boundaries. The current `docs/45-full-implementation-cross-check.md` is retained as the **historical** pre-F01/F02/F12 audit; use this document and `PROJECT_STATUS.json` for the latest scope.

The full `Docs and Android checks` workflow must pass **at the exact final feature-branch commit** before merging. Earlier green builds, successful Python documentation jobs, and any cancelled CI jobs do **not** validate a newer commit. The workflow regenerates/hardens Android, verifies `pubspec.lock`, runs Python documentation/source/delivery checks, `dart format`, `flutter analyze --fatal-infos`, `flutter test --coverage`, and compiles a debug Android APK. Check the linked Actions run for final results. The automated release workflow runs separately after successful **main** push CI and may publish a signed GitHub **prerelease**; a prerelease is not production approval.

## Safety-critical implementation reviewed

| Area | Source-level behavior reviewed | Evidence still required |
|---|---|---|
| HTTPS/API tokens | HTTPS-only normalized origins, origin-scoped gateway, redirect refusal, default TLS trust; explicit warned profile-only insecure override; encrypted vault separate from nonsecret metadata | Physical-device certificate/hostname/CA and token isolation under VPN/network changes; independent security review |
| Profiles and local data | Create/edit/switch/delete, serialize metadata/credential writes, retain profile identity/favorites/saved views, best-effort rollback, profile-generation guards | Process-death, corrupted-storage and Keystore/backup/restore tests on devices |
| Inventory/read cockpit | Node/guest metrics and freshness, filters/sorts/favorites/saved views, storage and recent tasks, malformed/partial records and 401/403 handling | PVE 9.2/8.4 response and least-privilege ACL fixtures; 200-guest/4-node device measurements |
| Guest operations | Exact profile+node+type+VMID checks, clean/fresh snapshot, live preflight, single-flight, exactly one POST, UPID verification, unknown lockout, post-terminal inventory reconciliation | Disposable VM/LXC mutation, disconnect, timeout, migration and token-revocation matrix against both versions |
| Retry/offline | Only transient GET transport/timeouts or 408/429/5xx get up to 3 total attempts with jittered backoff; no retry after TLS, redirect, permanent 4xx or POST | Physical offline/radio/VPN tests and full error-type classification; read cache still absent |
| Delivery | Generated, hardened Android runner; immutable formatting/analyzer/test/debug build CI; signed ARM prerelease script with certificate and ABI checks | Production signing recovery, APK install/update/rollback, history secret scan, SBOM/license/advisories, independent signoff |

## Findings during this follow-up

1. **Task-list ambiguity (F09, fixed with regression).** A recent task with `status: stopped` and `exitstatus: OK` was interpreted as failed because the parser treated the literal word `stopped` as the exit code. The decoder now prefers an explicit exit status, accepts the list-style terminal `status: OK`, keeps an active task active even if a stale exitstatus field appears, and displays an unlabeled stopped task as **unknown**, not failed/succeeded. Both shapes remain **synthetic contract cases** pending PVE fixtures.
2. **Retry source-format drift (F12, fixed).** The pinned CI formatter reported deviations in the gateway GET-call layout and TLS-error condition. The exact formatter output was applied; the final branch still must pass its own formatter gate.
3. **Status and assurance (documentation clarified).** The F12 GET-retry increment is source-implemented only. Remaining user-visible P0 features and release gates are not closed by an audit. Historical audit notes are not retroactively rewritten to claim contemporary coverage.
4. **Repository controls.** The connected GitHub branch metadata currently reports `main` as **not protected**. CI/PR approval must therefore be enforced operationally for this merge; do not claim an enforced branch-protection rule.
5. **Unknown outcomes across restarts remain a risk.** Mutations and uncertain-task locks are in memory, not a durable operation journal. After process death/reconnect, do not infer that a previous command failed; manually check authoritative task history before another write.

## Current implementation completeness

**Source-level implemented slices:** HTTPS token profiles, validated edits, last-observed version display, inventory and node/guest metrics, local discovery/favorites/saved views, storage/recent task lists, guarded QEMU/LXC power operations, in-session UPID task tracking, and bounded transient GET retries.

**P0 gaps still open:** detailed task/log explorer (F09), user-controlled theme/refresh/display preferences (F11), persistent offline read cache (F12), complete DNS/timeout/offline differentiation and network-aware state transitions (F12), and real target-system/instrumented release verification.

**Premium features still proposed/deferred:** ticket/2FA, console, snapshots/backups/restore, broader storage/capacity and long-range RRD charts, alert center, infrastructure mutations, HA/Ceph/SDN, PBS/PDM, multi-site and operations wizards. These are not delivered merely because their designs exist in docs 21–36.

## Merge/release decision

Merge only when the **final** feature-branch SHA has a green `Docs and Android checks` result (docs, Python tests, Dart format, analyzer, Flutter tests, Android debug APK); require no unaddressed CI failures. Successful merge to `main` is a **source integration milestone only**, not evidence that no bugs remain or that the product has met `docs/19-definition-of-done.md` and `docs/33-test-acceptance-release-gates.md`.
