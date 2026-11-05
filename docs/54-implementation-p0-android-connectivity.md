# F12 implementation — Android default-network observation and recovery

**Increment:** 2026-11-05. Source-level Android F12/CORE-04 work following the [offline overview](53-implementation-p0-offline-overview.md). Not a claim of live PVE compatibility or certified Android release.

## Android signal and limitations

- A native `ConnectivityManager.registerDefaultNetworkCallback` observes default-network arrival/loss only while an activity stream listener exists. It emits an initial state, unregisters on cancellation/activity destruction, and uses `ACCESS_NETWORK_STATE`. A Kotlin template at `scripts/android/MainActivity.kt` is applied to the ignored generated runner during the existing security hardening step.
- `available` means Android reports a default network; it **does not** establish Internet access, working VPN routing, or PVE host reachability. `unavailable` means no default network was reported; unusual LAN-only and multi-network paths may still work. Missing native data, errors or unsupported platforms yield `unknown`.
- Loss shows a contextual **NO DEFAULT NETWORK** indicator, pauses foreground auto-refresh and task-status polling, and disables all guest writes. Historical inventory is displayed as stale, and the optional counts cache remains opt-in, profile-specific and read-only.
- Return to `available` requests a new authenticated inventory read on the same foreground session; cold offline startup reactivates the saved profile and checks PVE server version. Generation/profile guards prevent obsolete results from authorizing a different session. Even if the native observer later reports `unknown`, the post-loss action guard remains until a successful live inventory read.
- Recovery performs only idempotent reads, never POST retry. No background network watcher worker, background refresh, or credential export is added. Pending UPIDs retain their existing ambiguous-outcome constraints.

## Insecure certificate display

The repeated shell and guest screen `TlsWarning` blocks are removed. The shell header and connection switcher still label opted-in profiles **TLS UNVERIFIED**, Settings displays the explicit certificate-verification state, onboarding/editing requires explicit confirmation, and guest action dialogs repeat the risk. HTTPS-only origins, redirect blocking, platform TLS validation by default and per-profile exact-host-and-port exception remain unchanged. See [TLS policy](40-profile-tls-option.md).

## Verification boundary

Synthetic controller/widget tests check offline lockout, unknown-state guarding, foreground recovery, cold startup, and contextual labels. Native runner regression checks cover network permission, callback registration/cancellation and idempotent generation. Exact-head Flutter formatting, analyzer, tests and Android debug build plus Python delivery checks remain gating.

**Still open:** physical airplane-mode, isolated Wi-Fi/LAN, VPN failover, process-death lifecycle and permission testing; live PVE 9.2/8.4 compatibility; a separate privacy decision for any persistent guest/node details; independent Android/TLS/release review. Android network presence is **not** proof of token privilege or host availability.
