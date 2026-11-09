# QEMU create branch cross-check — 2026-11-09

## Scope and branch completeness

Reviewed all 21 changed paths between `main` at `4aa30f3` and
`feat/qemu-create-wizard-ci` at `d474dc2`, including model/API/controller/UI,
test, version, status, endpoint-index and documentation changes. The CI branch
contains `feat/qemu-create-wizard` at `e809517` in full, plus eight context/test
follow-ups; integrating the CI branch therefore preserves both implementations.
PR #37 was closed, not merged. During this review another agent merged PR #38
as `44d9802`; its tree is identical to `d474dc2`. The safety corrections below
are a separate post-merge follow-up, not a second merge of those feature branches.

The feature is deliberately an **empty stopped QEMU configuration**, not a full
disk/NIC/media wizard. LXC creation and richer QEMU provisioning remain deferred.
That limitation is consistently disclosed in the UI, README and implementation
record, not counted as missing implemented functionality.

## Confirmed findings and fixes

| Finding | Resolution |
| --- | --- |
| Destination reservations were scoped to node/type; two creates on different nodes or create versus clone could race for the same cluster VMID. Clone reserved only its source. | Reserve a cluster-wide destination VMID synchronously alongside the exact target/source key; track both through task success, failure and uncertainty. |
| A newly discovered clone destination could authorize a power action before provisioning completed. | Both UI availability and controller power preflight honor destination VMID reservations across nodes/types. |
| Create accepted only a profile ID and captured the generation at invocation, rather than requiring the original generation. | Require and validate the caller's originating generation, including reconnects to the same profile and all async preflight boundaries. |
| Open create/clone confirmations did not observe session changes and could retain the previous identity above a redacted page. | A shared dialog listens to controller changes, redacts invalidated identity and removes submission controls. Current-session unsafe inventory/targets disable submission. |
| Dialog text controllers were disposed when `showDialog` returned, while the exit transition could still use them. | The dialog widget owns and disposes its controller with its route lifecycle. |
| Task reconciliation accepted fresh but malformed guest inventory; a skipped read was not explicitly distinguished from a new successful read. | Require an accepted post-terminal inventory revision and clean write-safe inventory before releasing any associated locks. Otherwise retain uncertainty. |
| Create node validation allowed path/control characters and task validation checked only a UPID prefix. | Reject unsafe node syntax before I/O and require a structurally valid UPID matching node, VMID and `qmcreate`. |
| Initial create coverage lacked negative/race/dialog cases; an existing large-text shell test missed offscreen taps. | Add parameterized safety/API/input/dialog tests, scroll controls into a hit-testable position and assert the filter sheet actually closes. |

## Contract cross-check

Reviewed the [official API viewer](https://pve.proxmox.com/pve-docs/api-viewer/)
and [official upstream QEMU source at 530b95c](https://git.proxmox.com/?p=qemu-server.git;a=blob;f=src/PVE/API2/Qemu.pm;hb=530b95c630316d76f06c74f9c2488b76aee194fc).
`create_vm` checks destination allocation, quorum, VMID uniqueness and
option-specific privileges, then returns the `qmcreate` worker UPID. The five
submitted fields require VM allocation and CPU/memory/options privileges; no
disk, storage, network, pool, HA, restore or automatic-start parameter is added.
This source review does not establish compatibility with a deployed server.

## Verification

Local validation uses Flutter **3.44.4**, its Dart **3.12.2**, the committed
dependency lockfile and synthetic credential-free fixtures:

- Documentation, premium-catalog and source smoke checks: **pass**.
- Python delivery/hardening regressions: **14 pass**.
- Dart format verification and `flutter analyze --fatal-infos`: **pass**.
- Complete `flutter test --coverage --concurrency=1`: **258 pass**, including TLS.
  There are **229 test declarations**; parameterized loops account for the
  higher execution count. The create controller has **86/86 executable lines**
  covered; line coverage is not exhaustive behavioral or live-server proof.
- Generated Android runner hardening checks: **pass**.
- Local debug APK compilation: pending at the time of this record's preparation.

CI must also pass on the final follow-up commit before merge. No live PVE
mutation or physical-device run is claimed.

## Remaining release gates

- Disposable PVE **8.4/9.2** create/clone, least-privilege/API-token ACL, quorum,
  ACL-filtered inventory, cross-client collision and transport/task fault tests.
- Physical Android TLS, lifecycle/network changes, TalkBack, font scaling and
  performance validation. Widget layout tests are not physical accessibility proof.
- Disk/storage/NIC/media/cloud-init/pool/HA/start provisioning, LXC creation,
  migration, configuration editing and other documented deferred capabilities.
- Production security/signing/device certification. Existing CI prerelease
  publication is not certification.

The audit fix advances semver to **0.1.37+1**; CI's independent monotonic
Android version-code computation is unchanged. No credentials, dependency
versions, signing configuration or planned premium-catalog claims are changed.
