# Template discovery foundation — 2026-11-09

This increment implements **GUEST-014 template browsing** as a read-only M4 provisioning foundation. It deliberately stops before clone/create execution: VirtHelm can now distinguish PVE templates from ordinary stopped workloads, browse them explicitly, and carry that distinction through the existing write-safety boundary.

## Data contract

No new PVE request is introduced. Template classification is derived from the existing authenticated cluster inventory response and its `template` field for QEMU/LXC resources. The parser accepts the same reviewed boolean-like representations used elsewhere in the model and treats absent, malformed, or false values as a normal guest rather than guessing that a workload is a template.

Because this remains based on the existing cluster inventory, profile isolation, HTTPS/TLS policy, bounded GET behavior and authenticated-read recovery are unchanged.

## Product behavior

- QEMU/LXC templates are labelled explicitly in the Guests list and guest detail identity.
- The Guests page adds a **Templates** quick filter. The filter is compatible with the existing search, type, node, tag, pool and sort controls.
- Template criteria can be stored in the existing profile-scoped named saved views without introducing a new persistence store.
- Running/stopped filters and Home/offline workload counts exclude templates, so a stopped template is not presented as a stopped runnable workload. The aggregate offline-count record advances to schema v2 so pre-upgrade v1 caches with template-inclusive totals are discarded instead of mislabelled.
- Template detail remains useful for existing read-only configuration, permission and related inspection surfaces where the server permits those reads.

## Mutation safety

Templates can never authorize the existing start/shutdown/reboot/force-stop path:

1. the model-level `GuestAction.allowedFor` policy rejects every template;
2. the controller independently rejects a template before guest-status preflight or any POST;
3. the guest action bar is disabled and explains that clone/create workflows remain gated.

This is defense in depth. UI state is not treated as authorization, and no template flag can bypass the existing exact profile/node/type/VMID, clean-live-inventory, single-flight or no-write-retry controls.

No clone, create, conversion-to-template, snapshot mutation, migration or backup mutation endpoint is added by this increment.

## Automated coverage

Five regression layers are added:

1. model parsing verifies true/false template markers and denies every power action;
2. pure guest filtering verifies templates are distinct from stopped workloads;
3. saved-view serialization round-trips the template status filter;
4. controller coverage proves a template reaches zero mutation submissions;
5. widget coverage verifies the Templates browse flow, explicit template identity and disabled primary action.

Repository source-smoke checks also require the template parser, filter, UI affordance and controller guard. The app version advances to **0.1.34**.

## Remaining gates and next dependency

Live PVE 9.2 and 8.4 fixtures still need to confirm template-marker behavior for both QEMU and LXC resources, including restricted-token inventories. Physical Android accessibility and large-inventory validation also remain release gates.

The next provisioning work must not infer clone/create safety from template discovery alone. A future create/clone wizard still needs versioned endpoint/parameter evidence, storage and VMID preflight, companion privilege checks, deliberate R3 review, exactly-once submission semantics, UPID tracking and post-task reconciliation as required by the M4 plan.
