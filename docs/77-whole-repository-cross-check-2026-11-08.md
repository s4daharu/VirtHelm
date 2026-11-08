# Whole-repository cross-check — 2026-11-08

This report records a current-state cross-check of VirtHelm after the connection-management, accessibility/theme, and Android launcher-branding milestones. It is source/CI/repository evidence only; it does **not** claim live Proxmox VE compatibility, physical-device certification, or production release approval.

## Audited baseline

- Audited `main` before fixes: `027e15dc44960cce2deb3fde130d2b39655e2c70` (`feat(android): add VirtHelm launcher icon`).
- No open pull requests were present.
- GitHub listed four non-main feature branches. They were not deleted by this audit because branch deletion is not required to correct implementation state and squash-merged history makes a simple ahead/behind comparison insufficient proof for destructive cleanup.
- The branches API reports `main.protected=false`. The connected GitHub App cannot read the administration-only branch-protection/ruleset endpoint, so no stronger ruleset claim is made.

## Cross-check coverage

The review covered the current implementation/status documents, generated-Android workflow, recent connection and accessibility milestones, transport/auth/TLS invariants, profile persistence, guest mutation guards, task verification/reconciliation, foreground polling, current CI evidence, and prerelease publication evidence.

Targeted source review confirmed:

- HTTPS-only normalized profile endpoints and redirects blocked before credentials can be forwarded elsewhere.
- The certificate exception remains profile-local and exact host/port scoped; no global `HttpOverrides` path is present.
- Idempotent GET retry remains bounded to three total attempts and excludes TLS/auth/permission/redirect failures.
- Guest mutation still reserves the exact target synchronously before the first await, performs fresh live preflight, submits exactly one POST, and locks ambiguous outcomes.
- Terminal task completion does not unlock writes until an authoritative inventory refresh begun after terminal status completes.
- Authentication loss invalidates live write safety and clears/withholds offline cached authorization data.
- Saved-profile test/version metadata updates do not rewrite the encrypted credential.
- Connection onboarding remains Server → API token → Verify; limited inventory permission is reported read-only and does not authorize a save.
- AMOLED/high-contrast/reduced-motion settings remain device-local presentation preferences and do not touch credential storage.
- Launcher resources persist outside the ignored Android runner and are installed by `harden_android.py` after generation.

## Findings and fixes

1. **Main CI caught display-version drift.** The launcher commit bumped `app/pubspec.yaml` to 0.1.28 but left `virthelmDisplayVersion` at 0.1.27. The docs job failed `scripts/check_source.py` with `display version drift`. This audit bumps the next change to 0.1.29 and synchronizes the display constant.
2. **Launcher source-of-truth needed a source smoke guard.** Delivery regression coverage already verifies copied Android resources, but `check_source.py` did not require the committed SVG/adaptive resources themselves. The source check now requires the branding files and asserts the installer, round icon, foreground/background references, and VirtHelm teal master.
3. **Current documentation had stale feature-state claims.** Both READMEs still listed alert duration/hysteresis as unimplemented even though ALERT-006 is implemented. `PROJECT_STATUS.json` also retained “future”/“CI pending” language for connection management and AMOLED/high-contrast completion. Current-state text is corrected; historical milestone documents remain historical.
4. **The current audit pointer was stale.** `PROJECT_STATUS.json` still treated the November 6 audit as current. It now points to this November 8 cross-check and records the newer CI/release evidence.
5. **Repository-control wording was too strong for current permissions.** The branches API confirms `main.protected=false`, but this GitHub App cannot read the administration-only protection/ruleset endpoint. Status now records only what is actually verified.

No new core mutation, credential-storage, TLS, retry, task-verification, or session-isolation defect was found in this pass.

## CI and release evidence reviewed

- Connection-management main commit `401cfffe51efcc9abc9f9e16093dbf633a48c30e`: Docs and Android checks completed successfully.
- Accessibility/theme main commit `ef1208c26546fee42485170173aecd5f5e61ed1f`: Docs and Android checks completed successfully; signed prerelease `v0.1.27-build-242` was published with ARM64, ARMv7, and SHA256SUMS assets.
- Launcher commit `027e15dc44960cce2deb3fde130d2b39655e2c70`: generated runner check, Dart formatting, `flutter analyze --fatal-infos`, and `flutter test --coverage` passed. The docs job failed only at the display-version synchronization assertion identified above. Its debug APK build was still in progress while this audit was prepared, so it is not claimed as successful evidence here.
- The audit/fix commit itself must pass fresh main-branch CI before it is treated as the new compile gate.

## Current intentional gaps

These remain release/product gaps rather than missed implementation in this audit:

- live PVE 9.2 primary and 8.4 regression fixtures, including ACL/partial-permission behavior;
- physical Android TLS, secure storage, backup behavior, TalkBack, large text, touch targets, lifecycle/VPN/default-network transitions, and performance validation;
- persistent offline guest/node detail cache beyond optional aggregate counts;
- alert acknowledgement/history, quiet hours/cooldown, Android background checks/notifications, lock-screen privacy, certificate/backup reminders, and relay/webhook delivery;
- app lock/biometrics, widgets/shortcuts, ticket/MFA, console, snapshots/backups, PBS/PDM, migration/provisioning and broader infrastructure mutation;
- independent dependency/security review and production certification;
- enforced branch protection/ruleset verification.

## Conclusion

The current implemented safety architecture remains internally consistent in the reviewed paths. The concrete defects found were repository-integrity/status defects rather than a newly discovered unsafe PVE write path: a version synchronization failure, stale current documentation, and insufficient source-level guarding of the new launcher resources. Those are corrected by the accompanying commit, which remains subject to the normal main-branch CI and signed-prerelease gates.
