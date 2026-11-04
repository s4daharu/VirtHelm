# VirtHelm — full implementation cross-check

**Reviewed:** 2026-11-04. **Scope:** the complete tracked Flutter/Dart implementation, tests, Android generation/hardening, CI/release workflows, status claims and implementation documentation through the profile-scoped saved-view slice.

## Assurance boundary

This is a source-level and automated-build cross-check. It can establish that the tracked implementation is internally consistent with its automated tests and documented safety rules; it cannot prove that every defect is absent. VirtHelm is still an implementation preview, not a production-certified Proxmox management client.

The pre-audit saved-view head had two successful GitHub Actions runs with documentation/source checks, immutable Dart formatting, `flutter analyze --fatal-infos`, 71 Flutter tests and Android debug APK compilation. The delivery suite contained 14 passing Python workflow/hardening tests. This cross-check adds four Flutter regressions; the final audit commit must pass the same complete CI gate before merge.

## Entire implemented surface reviewed

The review covered:

- HTTPS-only API-token connection creation, exact-origin normalization, encrypted credential-vault separation, profile switching and deletion;
- default certificate/hostname verification and the explicit warned per-profile exact-host/port insecure exception;
- cluster resource parsing, nodes, QEMU/LXC guests, storage, server task history, freshness and malformed/partial-read handling;
- guest search, favorites, status/type/node filters, deterministic sorting and profile-scoped named saved views;
- guarded QEMU/LXC start, shutdown, reboot and force-stop submission, live status preflight, single-flight locking, ambiguous-outcome handling, UPID polling and post-terminal inventory reconciliation;
- Flutter lifecycle/navigation behavior, large-text regression coverage and failure-message sanitization;
- generated Android manifest/Gradle hardening, dependency lockfile handling, CI checks and the manual signed split-APK prerelease workflow;
- all current implementation/status documents and the difference between implemented source and the proposed premium catalogue.

No application `print`, `debugPrint` or equivalent application logging calls were found in the tracked Dart source during this review.

## Findings corrected in this cross-check

1. **Disposal during credential persistence.** Earlier coverage proved that disposal while the server inventory check was pending prevented persistence, but it did not cover disposal after `ProfileRepository.save` had already entered the secure-vault write. A connection could therefore finish persisting after its controller was disposed. The controller now removes that newly created profile/credential on a best-effort rollback and restores the previous active-profile selection when possible. A regression pauses the vault write at exactly that boundary.
2. **Dismissed add-connection flow.** A pushed add-connection screen could previously be popped while its asynchronous connection check was active, leaving an invisible onboarding operation running. The route is now non-poppable while the check is busy; a widget regression exercises system back during the pending operation.
3. **Malformed local metadata cleanup.** Invalid saved-view/favorite preference roots were ignored for reading, but a malformed root could survive profile deletion. Deletion now removes invalid roots, with regression coverage, so corrupted local guest-discovery metadata is not deliberately retained.
4. **Coverage of repository smoke checks.** The source/document smoke-check manifests predated guest filtering and saved views. They now require the current filter/saved-view source, tests and current implementation cross-check documents.
5. **Stale implementation claims.** Earlier audits still listed saved views and expanded filtering as deferred and reported older 57-Flutter/5-delivery-test evidence. Those files are retained as historical evidence but now point to this review; current status no longer treats already-implemented saved views/sorting as missing.
6. **Malformed profile metadata recovery.** A malformed profile preference document could previously make every later profile save fail because onboarding re-read the same corrupt root. Profile parsing now ignores invalid rows, rejects non-canonical/unsafe stored endpoints, de-duplicates IDs, retains valid neighboring profiles and permits a new valid connection to replace an unusable root. A regression covers both partial and whole-document corruption.
7. **Repeated task polling after authentication loss.** A task-status 401 invalidated write freshness but left the task locally `running`, so the foreground timer could continue making verification requests until the 15-minute TTL. A 401 now immediately records the task outcome as `unknown`, moves the target into the uncertain lock and stops further polling for that task. This does not claim the server-side operation failed or succeeded.

## Implemented versus still missing

The table below cross-checks the P0 feature plan in [functional scope](02-feature-scope.md). “Source implemented” does not substitute for the live PVE/device evidence required by the Definition of Done.

| P0 area | Current implementation | Remaining gap |
|---|---|---|
| F01 profiles | Create, switch and delete named API-token profiles; exact HTTPS origin and per-profile TLS option | **Profile editing is not implemented**; changing endpoint/TLS requires remove + re-add |
| F02 auth/test/version | Token format validation; `/version` plus inventory permission check during onboarding | Server version is not retained/presented as a user-facing capability; PVE 8.4/9.2 live auth/ACL evidence is missing |
| F03 cluster overview | Node/guest counts, node state and read cockpit | Live single/multi-node compatibility/permission matrix missing |
| F04 guests | QEMU/LXC inventory/details with node/type/VMID identity | Live version/ACL fixtures missing |
| F05 discovery | Search, favorites, status/type/node filters, deterministic favorites/name/VMID/CPU/memory sorting and up to 12 profile-scoped named saved views | Tag/group filtering and 200-guest device evidence remain later scope |
| F06 metrics | CPU/memory/disk/uptime formatting with null/invalid handling and freshness | Live schema/unit validation and device presentation evidence missing |
| F07/F08 power | Guarded start/shutdown/reboot/force-stop, confirmation, one POST, UPID tracking and unknown-outcome lock | Disposable PVE 8.4/9.2 mutation/fault-injection matrix missing |
| F09 tasks | Session mutation tracker plus recent server task list and terminal result normalization | **Rich task detail/log explorer is not implemented**; live task fixtures missing |
| F10 storage | Read-only per-node storage list with partial/malformed handling | Live local/shared/PBS-backed storage fixtures missing |
| F11 local settings | System light/dark theme and connection/security settings exist | **User theme/refresh/display preferences are not implemented** |
| F12 offline/error | Stale/fresh gating, 401/403/TLS/network errors, no stale mutation, no mutation replay | **No persistent offline read cache**; process-death resilience remains unverified |

Because F01, F02 presentation, F09, F11 and the target-environment gates are incomplete, the repository must not claim that the whole P0 MVP or premium roadmap is complete.

## Security and lifecycle conclusions

Within the implemented source, the reviewed write path remains fail-closed: an action requires the same active profile, a fresh clean inventory snapshot, an unambiguous guest identity, a live current-status preflight and a locally reserved single-flight target. POSTs are not automatically retried. Network/timeout/5xx/redirect ambiguity after a mutation keeps the target uncertain for that connection session. Terminal task status does not itself unlock writes; a new inventory read must reconcile afterward.

Important limitations remain deliberate and visible:

- task tracking and unknown-outcome locks are in memory only; process death, profile reconnection or a new app session does not provide a durable operation journal;
- disabling certificate verification explicitly sacrifices server authentication and can expose the API token to an impersonated server;
- profile/search/node metadata is ordinary app-sandbox preference data, not credential-grade encrypted storage; Android app backup is disabled, but physical-device data-at-rest behavior remains a release test;
- credential screens do not yet have a separately verified screenshot/privacy-screen policy on physical Android;
- there is no ticket/MFA/console path, no mutation queue, no hidden cloud relay and no automatic write replay.

## Delivery and repository conclusions

The normal checks regenerate and harden the Android runner, preserve/enforce `pubspec.lock`, verify generated security settings, run formatter/analyzer/tests and compile a debug APK. The manual release workflow is main-only, restores signing material from protected secrets, configures release signing only in the generated runner, verifies the signer and ARM ABIs, deletes temporary signing files and publishes prerelease assets directly to GitHub Releases.

The repository is private and `main` is the default branch. The connected integration could not read branch-protection settings, and repository rulesets were reported unavailable for this private repository under the current GitHub plan. Therefore branch protection is **not verified by this audit** and must not be claimed as a completed control.

## Release blockers that remain open

- sanitized/live PVE 9.2 and 8.4 endpoint, ACL, task, storage and QEMU/LXC mutation evidence;
- physical Android API-level TLS/Keystore/backup/restore/process-death/VPN tests;
- TalkBack, actual 200% system font, localization/contrast and 200-guest performance/power/request-count evidence;
- production signed APK install/update/rollback verification and independent encrypted signing-key recovery;
- comprehensive repository-history secret scan plus dependency/advisory/license/SBOM and independent security review;
- the P0 product gaps explicitly listed above, if the release is to be called the complete MVP.

## Merge criterion

This audit branch may merge to `main` only after the final branch SHA passes the repository's full **Docs and Android checks** workflow, including documentation/source checks, all delivery regressions, Dart formatting, fatal-info analysis, all Flutter tests and Android debug APK compilation. A green merge does not close the external release gates above.
