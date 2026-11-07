# ALERT-006 foreground rule duration and hysteresis implementation

Status: source-level foreground alert state-machine increment. It is **not** background monitoring, a wall-clock paging guarantee, Android notification delivery, persisted incident history, live PVE 8.4/9.2 validation, or production release certification.

## Implemented scope

Foreground CPU and storage threshold rules now carry two backward-compatible state-machine controls:

- `consecutiveSamples` / `consecutive_samples`: 1–10 usable foreground live samples must meet or exceed the firing threshold before a new incident is created. The rule editor exposes 1–5 samples.
- `hysteresisPercent` / `hysteresis_percent`: 0–20 percentage points are subtracted from the firing threshold to form the clear threshold. The rule editor exposes 0–10 percentage points.

Existing saved rules that predate these fields decode as **1 sample / 0% hysteresis**, preserving the prior immediate-fire behavior.

This implements the ALERT-006 duration/hysteresis slice from the premium alert design without introducing a new API endpoint, background worker, Android permission, relay, or credential write.

## State-machine semantics

A non-firing rule starts confirmation only from a usable sample at or above its configured threshold. Each subsequent usable foreground sample at or above the threshold increments confirmation. The incident becomes active only when the configured consecutive-sample count is reached.

A missing or unusable sample resets **pending** confirmation. This avoids claiming continuous threshold duration across a data gap. Once a rule is already firing, however, missing data does not resolve it: the previous firing remains visible because unknown is not healthy.

With positive hysteresis, an active rule resolves only when a usable sample is at or below:

`clear threshold = firing threshold - hysteresis`

Samples between the clear threshold and firing threshold remain inside the hysteresis band and keep the existing incident active. With zero hysteresis, the prior behavior is preserved: a value exactly at the firing threshold remains active and resolution requires a sample below that threshold. The original firing timestamp is retained while the incident remains active rather than being reset on every refresh.

Because this is foreground-only polling, “consecutive samples” is deliberately not presented as an exact number of minutes. Actual wall-clock spacing depends on manual refreshes and the selected foreground auto-refresh interval.

## Persistence and isolation

Only rule configuration is persisted as profile-scoped non-secret SharedPreferences metadata. Saving, enabling, disabling or deleting rule configuration does not count as a live sample; those changes only reconcile runtime state. Pending counters and active firing state remain runtime-only and are cleared when the threshold engine is cleared during profile switch/reconnect.

Credential storage is unchanged. The new metadata does not contain tokens, task logs, metric samples, endpoints, or notification payloads.

## UI

The threshold-rule editor now exposes:

- consecutive live samples required before firing;
- clear hysteresis in percentage points, including the resulting resolve percentage;
- existing target, threshold and severity controls.

Saved rule cards summarize threshold, required samples, hysteresis and severity so operators can see the anti-flapping policy without opening another screen.

## Verification

Synthetic coverage now checks:

- JSON round-trip of duration/hysteresis fields;
- safe defaults for legacy rule JSON;
- pending confirmation does not fire early;
- missing data resets pending confirmation;
- hysteresis keeps an active rule firing inside the band;
- a sample at the lower clear threshold resolves a positive-hysteresis incident;
- zero hysteresis keeps an active incident firing at exactly the configured threshold;
- rule configuration writes do not advance confirmation counters;
- existing node, guest and storage threshold behavior remains compatible.

Repository CI remains the required formatter, analyzer, Flutter test and Android debug-APK gate. Test count is tracked in `PROJECT_STATUS.json`.

## Deliberately deferred

ALERT-007 quiet hours/cooldown and ALERT-008 acknowledgement/persisted alert history remain separate stories. ALERT-009/010 Android scheduled checks, notification channels/privacy and all relay/webhook work also remain deferred.

Live PVE 9.2/8.4 field behavior, physical Android lifecycle/accessibility/performance testing, signing review and production release certification are still required before broader release claims.
