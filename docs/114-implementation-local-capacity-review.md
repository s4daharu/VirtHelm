# Bounded Local Capacity Review

## Milestone

VirtHelm 0.1.69 implements a first **EP-ALERT-05** / M6 local capacity
review on the Home screen. It uses the foreground inventory and storage
measurements already loaded; it does not ask Proxmox for any new data.

## Operator experience

When the active connection has a fresh (under two minutes), complete inventory
and storage read, Home shows an explicit **Capacity review** section with
snapshot-only indicators for:

- online node RAM usage;
- running, non-template QEMU/LXC guest RAM usage, only with an unambiguous
  online host node; and
- active, enabled per-node storage used/total capacity.

Measurements at or above **85%** are displayed highest-first with one-decimal
percentage, source type and exact visible resource scope. There are at most
five cards. The section states usable and missing/ambiguous metric counts,
plus a candidate-scan cap when applicable. It never calls an empty or missing
metric "healthy". Shared storage is **not** summed or counted as cluster-wide
free capacity. No inferred trend, forecast, runway or server-derived root
cause is claimed.

On stale or partial refresh, during an in-flight refresh, or after connection
loss, the section shows only an explicit unavailable state. Optional offline
counts/identity caches cannot supply capacity advice.

## Data and safety contract

The evaluator reads only existing transient Inventory and StoragePool
objects. It processes at most 128 nodes, 512 guests and 256 storage records,
and holds only the top five readings. Invalid, negative, over-total, zero
denominator, inactive and ambiguous values are excluded. Duplicate exact
node+storage ID entries do not produce duplicate cards. Readings are
sorted deterministically and recomputed on each foreground build.

No insights, measurements or resource names are persisted, sent to Android
notifications, exposed to background workers or shared with an external
service. This feature does not change incident history, health badges,
threshold rules, alerts, task handling, secure profile metadata, API
permissions, network requests or mutation authority. Guidance is to inspect
the resource manually, not execute a server action.

## Evidence and release limitations

Synthetic unit tests cover thresholds, sorting, five-card cap, missing and
invalid measurements, templates, stopped/offline/duplicate node records,
inactive and shared storage, and capped scans. Widget tests exercise
snapshot wording, absence of server actions and stale/incomplete gating.
Source guards and documentation matrix track the feature. GitHub CI is the
available pinned Flutter/analyzer/Android-build gate; no Flutter/Dart SDK or
outbound Git network is available in this implementation container.

The findings are advisory heuristics, not measured forecasts or independent
capacity verification. Physical Android accessibility/large text/performance,
PVE 8.4/9.2 ACL/storage backend fixtures and site capacity planning remain
release gates. Historical trends, trend uncertainty, allocation-aware
headroom, per-resource notification thresholds and auto-remediation remain
out of scope.
