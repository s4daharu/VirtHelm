# VirtHelm — pre-merge whole-repository source and delivery audit (2026-11-05)

**Scope:** Current `main` plus the complete stacked #22 → #23 → #24 source feature work (task log pages, task-history filters, guest network/disk I/O, and this security review). This is a code/CI evidence assessment, **not a claim of bug-free software**, PVE compatibility certification, or production release approval.

## Inventory and process

- Enumerated the feature branch Git tree (**109 tracked files**, no suspiciously named private key/keystore files in paths) and searched the **16 Dart implementation files (6,092 lines)** for application logging, unrestricted HTTP, file/process/clipboard calls, TLS overrides, POST call sites and local preferences. A filename and literal-code search is **not** a comprehensive repository-history secret/SBOM/license/security audit.
- Reviewed the PVE gateway, controller, model decoding and guards, profile repository, lifecycle/network observer, UI/navigation, task route, widget tests, generated Android hardening policy, SDK/lockfile/bootstrap, and the release workflows and delivery caveats. Reviewed per-PR deltas for #22, #23, #24 and compared their commit ancestry.
- Upstream PR CI: **#22 exact head `89e48f1`** — [run 42062526693](https://github.com/s4daharu/VirtHelm/actions/runs/42062526693) green; **#23 exact head `974acc0`** — [run 42064988752](https://github.com/s4daharu/VirtHelm/actions/runs/42064988752) green; **#24 pre-audit head `9f853c8`** — [run 42067795840](https://github.com/s4daharu/VirtHelm/actions/runs/42067795840) green. **The post-audit feature head needs its own complete CI run** before merging; passing older heads does not validate the remediation.
- Pinned CI gate: Flutter 3.44.4, Java 17, generated minSdk 26 Android runner, lockfile exactness, Python docs/source/security/delivery tests, Dart format, fatal-info analyzer, Flutter tests and debug APK compilation. Debug builds are not signed release/install/device verification.

## Cross-check findings

### Fixed in this audit: cross-session guest detail leakage and stale action confirmation

The guest details route previously validated only its profile ID, not its connection generation; if the user switched profiles while a guest page was open, the page still displayed the original guest's **name/node/VMID** as fallback text. Reconnecting the **same profile** also allowed an older route to display updated guest data without re-establishing the route's original session. Moreover, a power-confirmation dialog could remain open showing its previous target.

Remediation: capture both profile ID and controller generation **when opening** guest details; render a neutral **Guest unavailable** page on mismatch; change a pending power confirmation to a redacted dialog with only **Dismiss**, and recheck session identity after the dialog before invoking the existing `runAction` preflight. New widget regressions cover switching profiles (including old I/O and identifier redaction) and same-profile reconnect while a confirmation is open. The controller's single-flight, live preflight, one-POST and unknown-outcome guards were not relaxed.

### Reviewed without changing critical write/transport boundaries

- API credential metadata/vault separation, origin-bound HTTPS token client, default trusted certificate checks and explicit exact-origin insecure exception; redirects remain blocked; no automatic POST retries.
- Inventory data and model parsers, null/malformed handling, freshness and permission warnings, local preferences/offline **counts-only** cache and profile isolation.
- Read-only task-detail pagination (five pages of 100 maximum) with current-session validation, ephemeral log content, read-only refresh; task-history search/status/node filters operate locally on the bounded visible task snapshot.
- Guest power confirmation and stale/profile/race guards, UPID tracking, status reconciliation and uncertainty lockout.
- Release workflow uses explicit release keystore secrets, signed APK verification and public **prerelease** upload after successful push checks on `main`. There is no claim that those secrets are present or that a signed build has succeeded for this commit.

## Known gaps that remain — not accidentally declared complete

- No captured/live PVE 9.2 or 8.4 versioned endpoint fixtures, ACL matrix or disposable QEMU/LXC mutation/fault-injection evidence, so task log pagination, statuses and I/O counter schemas remain provisional.
- No physical Android TLS/hostname/private-CA/Keystore/backup, VPN/default-network, resume/process-death, disclosure/screenshot, large-text/TalkBack, memory/performance (200 guests) or installed APK upgrade/rollback evidence.
- Unknown write outcomes are locked **in memory**, not persisted across process death; operators must reconcile server tasks before submitting again. No full offline inventory/detail archive, console/ticket/2FA, charts/RRD, notifications, snapshots, backup/restore or high-risk infrastructure actions.
- Comprehensive repository-history secret scan, dependency/advisory and SBOM/license review, and independent security review are outstanding. No top-level `LICENSE` is selected; the public repo is not automatically open-licensed.
- GitHub integration reports no repository rulesets, but direct main branch-protection inspection returned **403**, so protection/reviewer requirements cannot be asserted. The PRs have no independent review submissions. Follow the owner's requested source merge only after clean exact-head CI; do **not** equate this with release-signoff.
- Repo currently has `delete_branch_on_merge: false`. If branch deletion is unavailable through the connected GitHub actions, remove the three feature branches separately through GitHub after verifying their commits are integrated.

## Merge/release control

The three feature branches are cumulative. A **single merge commit** from the final audited #24 branch into `main` preserves all #22/#23/#24 commits, avoids publishing multiple intermediate versions, and should close/reconcile superseded PRs. Retarget #24 from its stacked base to `main`, verify GitHub's mergeability and **new base-aware exact-head CI**, then merge only if docs, analyzer, tests and debug APK all pass. The resulting main push will itself trigger CI and, if successful and signing secrets exist, an automatic public signed GitHub **prerelease** for version `0.1.9`. Keep certification/physical device gates open and verify integration and remote branch cleanup separately.
