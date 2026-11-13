# Implementation — scheduled guest CPU thresholds

> Follow-up: bounded scheduled storage-usage thresholds are implemented in
> [107-implementation-scheduled-storage-usage-thresholds.md](107-implementation-scheduled-storage-usage-thresholds.md).


## Milestone

VirtHelm 0.1.61 implements the next bounded Android Mode B threshold-parity slice:
operators can separately opt scheduled checks into the enabled **guest CPU**
rules already saved for the active connection.

This does not enable storage-usage thresholds in the background. Scheduled
execution remains best-effort WorkManager polling with an inexact minimum
15-minute cadence; it is not continuous monitoring or a production critical
paging guarantee.

## Operator behavior

The Scheduled checks screen adds **Include guest CPU threshold rules** beneath
the existing node-CPU option.

When enabled and at least one enabled guest-CPU rule exists:

- the worker receives only enabled guest-CPU rules;
- it performs one additional bounded authenticated
  `GET /api2/json/cluster/resources?type=vm`;
- it matches samples by exact guest kind (`qemu` or `lxc`), node and positive
  VMID rather than guest display name;
- it accepts only finite CPU ratios in the inclusive 0..1 range;
- duplicate, missing or malformed target samples are incomplete evidence, never
  healthy evidence;
- consecutive-sample confirmation and hysteresis reuse the existing foreground
  rule values;
- a newly firing rule is eligible for the same generic Android notification,
  quiet-hours policy and shared profile cooldown ledger as the other scheduled
  signals.

If the guest option is enabled but there are no enabled guest rules, no guest
inventory request is issued.

## State-machine semantics

Each scheduled guest rule uses the same bounded firing semantics as the existing
foreground and scheduled node-CPU rules:

1. a valid sample below the threshold resets pending confirmation;
2. a sample at/above the threshold increments the pending count;
3. the incident becomes active only when the configured 1-10 consecutive
   samples have been observed;
4. an active incident stays active until CPU falls below the threshold when
   hysteresis is zero, or to/below `threshold - hysteresis` when hysteresis is
   non-zero;
5. a missing/unusable sample resets pending confirmation but does **not** clear
   an already-active incident.

A failed guest inventory read makes that scheduled component incomplete, so the
run cannot become a last-complete check merely because node/task data succeeded.

## Privacy and storage boundary

The Flutter profile preferences continue to hold only the normal non-secret
threshold-rule configuration. The native worker copy stores endpoint,
authorization and enabled guest selectors/threshold values only inside the
existing AES-256-GCM Android-Keystore-encrypted scheduled secret.

Guest runtime state is stored separately from the encrypted selector copy and is
keyed only by SHA-256-derived rule IDs. It contains bounded pending counters and
active booleans; node names, VMIDs, guest kinds, thresholds, CPU samples, task
identifiers, logs and guest display names are not written to that runtime state.

The existing controller-owned profile edit/delete cleanup and worker disable
paths clear the guest runtime state together with the encrypted scheduled
credential copy.

## Synchronization and compatibility

Rule edits now use one atomic threshold-rule synchronization channel carrying
both supported scheduled categories (node CPU and guest CPU). Native code
revalidates the per-rule bounds, rejects duplicate IDs across categories and
enforces the existing maximum of 32 combined scheduled threshold rules.

Synchronization failure disables scheduled monitoring fail-closed rather than
leaving a partially updated node/guest rule set active.

Upgrade compatibility is fail-safe:

- old policy JSON has no guest flag, so guest monitoring defaults off;
- old encrypted worker payloads have no guest-rule array, so they decode as an
  empty guest list;
- the existing node-CPU runtime-state key is unchanged;
- guest runtime state uses a separate key and is created only for configured
  guest rules.

## Network and safety boundary

This milestone adds one read-only PVE request family already covered by the
cluster-resource contract: `GET /cluster/resources?type=vm`.

The worker still:

- uses HTTPS and the platform certificate/hostname verifier;
- rejects redirects;
- uses 10-second connect/read timeouts and a 512 KiB successful-response cap;
- performs no POST, PUT, PATCH or DELETE;
- never asks WorkManager for an immediate retry;
- emits only the existing generic incident notification and carries no resource
  identifier in the notification navigation intent.

Restricted-token or partial-visibility responses can therefore make a target
sample unavailable; they cannot make the worker guess that the target is
healthy.

## Verification

Focused regression coverage adds six Flutter tests for:

- legacy default-off guest policy decoding;
- guest-rule MethodChannel serialization and filtering;
- atomic node+guest synchronization with storage rules excluded;
- status decoding without guest identity exposure;
- controller resynchronization after guest-rule edits;
- fail-closed worker disable after synchronization failure.

Repository source/generated-runner checks also assert the guest opt-in,
read-only VM resource endpoint, separate hashed runtime-state key, encrypted
guest-rule copy, combined 32-rule cap, atomic synchronization and absence of
selector fields from runtime-state JSON.

Exact-head GitHub Actions, physical Android scheduling/Keystore/OEM behavior,
and sanitized PVE 8.4/9.2 type-filter/ACL/partial-visibility fixtures remain
release gates.

## Remaining work

Still gated:

- scheduled storage-usage threshold parity;
- richer window/time-duration rules;
- authoritative foreground/background incident correlation;
- resource-specific notification links;
- optional relay/webhook delivery;
- production critical-alert guarantees and release certification.
