# Implementation — ALERT-009 Android periodic node-state checks

## Milestone

VirtHelm 0.1.53 implements the first Android scheduled-monitoring slice from ALERT-03 / ALERT-009. A saved connection with normal certificate and hostname verification can opt into a best-effort WorkManager check while the app is not foregrounded.

This milestone is intentionally narrower than the full alert catalogue. It checks node state only. It does not claim background parity with foreground failed-task or threshold-rule incidents, authoritative cross-resource correlation, relay delivery, an SLA, 24/7 monitoring, or critical paging.

## Operator behavior

The Connections screen exposes **Scheduled checks** for each saved profile. The scheduled-check page makes the Android execution contract explicit before opt-in:

- WorkManager execution is inexact and can be delayed by Android power policy, network state or VPN availability.
- The minimum requested interval is 15 minutes. The UI offers 15, 30, 60, 120 and 240 minutes.
- The worker requires Android's connected-network constraint and skips a run when VirtHelm is already foregrounded.
- Coverage evidence shows the last attempt, last complete check, latest outcome and last scheduled notification. A missed or incomplete read is never represented as continuous coverage.
- Quiet hours and a scheduled-notification cooldown suppress delivery only. Suppressed occurrences are not queued for later.

Android notification permission is requested only when the operator first enables scheduled checks. If permission is denied, the schedule is not enabled.

## Read-only contract

The worker issues one bounded HTTPS GET to:

`/api2/json/cluster/resources?type=node`

It filters returned rows to node records and treats a complete response containing any non-`online` node state as the scheduled incident signal. A complete healthy response is required to clear that local occurrence state.

The worker:

- never submits POST, PUT, PATCH or DELETE;
- disables HTTP redirects;
- uses 10-second connect and read timeouts;
- caps a successful response at 512 KiB while reading the stream;
- uses the platform HTTPS certificate and hostname verifier;
- never requests an immediate WorkManager retry after a failed read.

Authentication denial, blocked redirects, malformed/empty node evidence and transport failures remain incomplete evidence. They do not clear an already observed node-state incident and do not generate a misleading healthy result.

## Credential and profile lifecycle

WorkManager cannot call Flutter secure storage after the Dart isolate is gone, so the opt-in path maintains a separate native worker credential copy.

The copy is protected as follows:

- the PVE authorization value is encrypted with AES-256-GCM;
- the encryption key is generated and held by Android Keystore;
- encrypted ciphertext/IV are stored in private native SharedPreferences;
- the profile ID is SHA-256-derived before it is used as a WorkManager input, unique-work name or native preference suffix;
- the endpoint is stored only inside the encrypted worker payload;
- Android application backup remains disabled.

Scheduled mode is refused for profiles with the saved insecure TLS exception. Editing a connection clears the schedule, native policy and encrypted worker token before the new profile configuration is committed. Removing a profile clears that native state before the Flutter profile/vault credential is deleted. These cleanup calls live in `AppController`, not only in one UI route.

If native encrypted credential state becomes unavailable or undecryptable, the status surface reports the configuration as unavailable instead of claiming the schedule is active.

## Notification privacy and deduplication boundary

A scheduled notification is emitted only for a new transition into a complete non-online node-state observation. The Android notification is private and generic:

- title: `VirtHelm scheduled incident`;
- body: `Open VirtHelm to review current incidents.`

No profile name, endpoint, node name, guest name, VMID, task ID, task log, credential, raw response or authorization result is included.

Scheduled-mode occurrence state and cooldown are native and profile-scoped. Foreground durable incident history and foreground notification cooldown remain separate in this slice. Cross-mode notification deduplication is therefore still gated and must not be inferred.

## Generated Android runner

The committed Android runner remains intentionally absent. `scripts/harden_android.py` now installs:

- `androidx.work:work-runtime:2.12.0`;
- the reviewed `BackgroundIncidentWorker.kt` template beside the generated `MainActivity.kt`;
- the existing network/notification permissions, cleartext/backup restrictions and notification icon.

`scripts/check_android_generated.py` verifies the dependency and reviewed worker invariants after generation.

## Verification and remaining gates

Repository checks assert the scheduled-check source and generated-runner safety boundary: minimum 15-minute periodic work, connected-network constraint, GET-only request method, Android Keystore use, redirect blocking, generic notification payload and controller-owned cleanup.

This is source-level implementation evidence until exact-head CI passes. Physical Android validation must still cover Doze/app-standby timing, reboot persistence, VPN/network transitions, notification permission changes, OEM battery restrictions and profile edit/delete cleanup. Disposable PVE 8.4 and 9.2 environments remain required for endpoint/ACL/incident behavior evidence.

Deferred work includes background failed-task and threshold-rule parity, authoritative incident correlation, cross-mode notification deduplication, richer lock-screen privacy/deep links, optional relay delivery and any production critical-alert guarantee.
