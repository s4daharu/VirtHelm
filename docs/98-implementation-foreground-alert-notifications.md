# Foreground incident notification policy — ALERT-007 milestone (0.1.52)

## Operator outcome

VirtHelm can now optionally raise a generic Android notification when a **new
incident occurrence** is observed while the app is in the foreground. The
setting is disabled by default and scoped to the active saved connection.

Operators can configure device-local quiet hours and a notification cooldown.
These controls suppress only Android notification delivery. They never remove,
acknowledge, resolve, downgrade or hide an incident from Home, the Incidents
tab, durable history or mutation-safety logic.

This milestone deliberately remains **foreground-only**. It does not add
WorkManager, alarms, a foreground service, background credential access or a
new Proxmox endpoint.

## Privacy and permission boundary

Android 13+ notification permission is requested only when the operator enables
foreground incident notifications. Denial leaves the feature disabled. On
older supported Android versions the native bridge reports permission as
available without presenting a runtime prompt.

Native notification content is intentionally generic:

- title: VirtHelm incident / VirtHelm critical incident;
- body: open VirtHelm to review current incidents;
- no profile name or endpoint;
- no node, guest, storage or rule name;
- no VMID, task UPID, task title or task log;
- no credential, response body or authorization state.

ALERT-010 now adds a shared device-wide secure-lock-screen policy: hidden by
default or generic-only. Device/channel policy and OEM behavior remain
operator/system controlled and still require physical-device validation.

## Delivery semantics

- Only a newly created durable occurrence is eligible for one foreground
  notification summary. Repeated refreshes of the same open occurrence do not
  notify again.
- Multiple new occurrences from one refresh collapse to one generic
  notification; critical severity changes only the generic title.
- Quiet hours use the Android device's local clock and support intervals that
  cross midnight.
- From 0.1.57, cooldown is measured against the last successfully displayed
  foreground **or scheduled** notification for that profile through one shared
  native delivery ledger. Suppressed occurrences are not queued for delayed
  delivery.
- Notification delivery failure is best-effort and cannot alter incident
  lifecycle, current health, durable history or write authorization.
- Profile/generation checks are retained around delivery. The persisted
  delivery timestamp contains only a UTC time and is purged with the profile.
- Reappearance after a conservatively closed occurrence creates a new durable
  occurrence and can become notification-eligible again.

## Persistence

The non-secret policy and last-delivery timestamp are stored in
SharedPreferences per profile. Android application backup remains disabled by
the hardened runner. Profile deletion purges both policy and delivery state.

The policy contains only enablement, quiet-hour minutes and cooldown duration.
It does not persist incident payloads beyond the existing privacy-bounded
history introduced in 0.1.51.

## Automated acceptance

Regression coverage includes:

- overnight and same-day quiet-hour evaluation;
- cooldown boundary behavior;
- invalid policy bounds;
- profile-scoped policy/timestamp persistence and deletion cleanup;
- generated Android POST_NOTIFICATIONS hardening;
- a deterministic notification small icon and native channel bridge;
- source checks ensuring the Android payload remains generic and the settings
  are wired through the controller.

Pinned Flutter formatting/analyzer/tests and Android debug compilation remain
the authoritative merge checks. Synthetic and CI checks are not physical
Android notification-permission, lock-screen, OEM, TalkBack or battery signoff.

## Still gated

ALERT-009 scheduled node-state checks, ALERT-010 lock-screen privacy, AND-010
generic Incidents navigation and 0.1.57 cross-mode notification delivery
deduplication are implemented as bounded follow-up slices. Background
failed-task/threshold parity, resource-specific notification links,
authoritative cross-resource correlation, relay/webhook delivery and
production release certification remain gated. Android scheduled work remains
inexact and unsuitable for critical paging.
