# Implementation — scheduled node CPU thresholds

## Milestone

VirtHelm 0.1.59 implements the first scheduled threshold-rule parity slice for
Android Mode B monitoring. Operators can separately opt scheduled checks into
the enabled **node CPU** rules already configured for the active connection.

This does not make all foreground threshold rules background-capable. Guest CPU
and storage-usage rules remain foreground-only, and scheduled execution remains
best-effort WorkManager polling rather than continuous monitoring or critical
paging.

## Operator behavior

The Scheduled checks screen adds **Include node CPU threshold rules** beneath
the existing node-state and recent failed-task options.

When enabled:

- only enabled node-CPU rules are copied into the worker configuration;
- the existing authenticated
  `GET /api2/json/cluster/resources?type=node` response supplies the CPU
  samples, so this slice adds no PVE request endpoint;
- up to 32 node-CPU rules can be evaluated, matching the existing local rule
  limit;
- consecutive-sample confirmation and hysteresis use the same rule values as
  foreground evaluation;
- a newly firing scheduled rule is eligible for the same generic Android
  incident notification, quiet-hours policy and shared foreground/scheduled
  cooldown ledger already used by other Mode B signals.

WorkManager intervals remain inexact and begin at 15 minutes. Consecutive
scheduled samples therefore mean consecutive usable worker runs, not an exact
wall-clock duration.

## State-machine semantics

For each enabled node-CPU rule:

- a usable CPU fraction at or above the firing threshold increments the pending
  confirmation count;
- the rule becomes active only after its configured 1–10 consecutive usable
  samples;
- while inactive, a usable sample below the firing threshold resets pending
  confirmation;
- while active, 0% hysteresis requires a sample below the firing threshold to
  resolve;
- while active with positive hysteresis, resolution requires a sample at or
  below `threshold - hysteresis`;
- a missing or unusable node CPU sample resets pending confirmation but does not
  resolve an already-active rule.

If any opted-in node-CPU rule lacks a usable sample, the threshold side of the
scheduled run is marked incomplete. Other independently complete scheduled
signals can still transition and notify. An incomplete threshold side does not
advance the last-complete-check timestamp.

Rule configuration changes are not samples. Editing, enabling, disabling or
removing a rule synchronizes the worker copy and reconciles state without
advancing pending confirmation.

Malformed or corrupt native threshold runtime state is treated as incomplete
evidence and is not automatically rewritten by an ordinary worker sample. An
explicit rule/schedule synchronization may rebuild that local runtime state.
This prevents corrupted state from being silently converted into a healthy
observation.

## Privacy and persistence

The worker needs exact node selectors to evaluate node CPU rules, but they are
not stored as new plaintext native metadata.

The scheduled rule copy is embedded inside the existing AES-256-GCM
Android-Keystore-encrypted worker payload alongside the worker endpoint and API
token. Only these rule fields are copied:

- stable local rule ID;
- node selector;
- threshold percentage;
- consecutive-sample count;
- hysteresis percentage.

Display labels, severity text, guest identifiers, storage identifiers, metric
samples and incident details are excluded.

Runtime threshold state is kept separately in private native preferences but is
keyed only by SHA-256 hashes of local rule IDs. It contains bounded pending
sample counts and active booleans; it contains no node names, thresholds,
credentials, VMIDs, storage names or sampled CPU values.

Disabling scheduled checks removes the encrypted worker payload and threshold
runtime state. Profile edit/deletion keeps the existing controller-owned
scheduled-state cleanup boundary.

## Synchronization safety

Foreground rule changes are persisted first, then the Android worker copy is
synchronized. If that native synchronization fails, VirtHelm disables the
scheduled worker rather than allowing stale background threshold configuration
to continue silently. The foreground rule remains saved and the rule editor
reports that scheduled checks were disabled.

When no scheduled configuration is active, rule synchronization is a no-op and
does not create a native worker copy.

## Read-only and notification boundary

This milestone preserves all existing scheduled-worker safety constraints:

- GET only; no POST, PUT, PATCH or DELETE;
- redirects disabled;
- platform HTTPS certificate and hostname verification;
- 10-second connection/read timeouts and the existing 512 KiB response cap;
- no immediate WorkManager retry;
- generic notification title/body only;
- no node name, rule ID, threshold, sampled CPU value, guest name, VMID, task
  ID, endpoint or credential in the notification or navigation intent.

ALERT-010 secure-lock-screen privacy, AND-010 generic Incidents navigation and
the 0.1.57 shared delivery-cooldown ledger remain unchanged.

## Verification

Regression coverage includes:

- backward-compatible default-off policy decoding;
- MethodChannel serialization of only enabled node-CPU rules;
- filtering out disabled, guest-CPU and storage rules;
- controller resynchronization after rule edits;
- fail-closed scheduled-worker disable when rule synchronization fails;
- source/generated-runner assertions for the encrypted rule copy, 32-rule
  bound, hashed runtime rule IDs, consecutive-sample confirmation and
  hysteresis evaluation.

PR implementation run 43202139457 at
`aebc50e91cf70af5ead154e4f0ba478023a56e70` passed source/docs checks,
generated Android hardening, pinned Dart formatting,
`flutter analyze --fatal-infos`, 413 Flutter runtime tests and debug APK
compilation. The subsequent verification-record-only PR head is required to
pass the same workflow before merge.

Physical-device WorkManager/Doze behavior and live PVE 8.4/9.2 node CPU
payload/ACL validation remain release gates.

## Remaining work

Still gated:

- scheduled guest CPU threshold parity;
- scheduled storage-usage threshold parity;
- richer window/time-duration rules;
- authoritative foreground/background incident correlation;
- resource-specific notification links;
- optional relay/webhook delivery;
- production critical-alert guarantees and release certification.
