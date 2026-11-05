# Guest tag browsing — local inventory search and filter

**Increment:** 2026-11-05. Source-level, read-only follow-up to the existing guest discovery cockpit. This does **not** establish live PVE 9.2/8.4 compatibility, physical Android validation, or completion of the broader HOME-007 tag-and-pool roadmap item.

## Scope

- Decode the optional `tags` value already returned with QEMU/LXC records in the existing `GET /cluster/resources` inventory response. No new API endpoint, permission, background request, or mutation is introduced.
- Interpret the inventory value as a semicolon-separated list for presentation/search. Empty values are ignored, duplicate tags are de-duplicated case-insensitively while preserving the first display spelling, and malformed/oversized values become unavailable rather than invalidating the guest record.
- Bound untrusted input before UI/search use: at most 2,048 source characters, 32 tags, and 64 characters per tag.
- Include tags in the existing local guest search and add an exact, case-insensitive tag filter that composes with status, QEMU/LXC type, node, favorites, and sorting.
- Show current tags on guest cards and guest detail. Guest detail still resolves the current inventory inside the captured profile ID and connection generation, so a switched/reconnected session cannot reuse previous tag data.
- Allow an optional selected tag to be stored in an existing profile-scoped saved guest view. Older saved-view JSON without a `tag` field remains valid.

## Privacy and safety

Guest tags come from the current in-memory inventory and are not written to a new cache, exported, logged, uploaded, or sent to telemetry. Saving a view may persist the selected tag in the same SharedPreferences metadata already used for saved searches, node names, filter state, and sort criteria; Android app backup remains disabled.

Filtering is presentation-only. It cannot authorize guest actions, relax fresh-inventory requirements, replay writes, or affect the controller's exact profile/node/type/VMID mutation guards. The existing HTTPS, TLS exception scope, redirect blocking, bounded GET retry, single-flight POST, ambiguous-outcome lockout, and task reconciliation rules are unchanged.

## Verification boundary

Synthetic parser tests cover trimming, duplicate handling, malformed and oversized values. Pure filter tests cover tag search plus exact tag filtering composed with node/type/status. Saved-view tests cover round-trip persistence, validation, and backward compatibility. A widget regression covers browsing by tag and rendering tags on the current guest detail.

Final exact-head CI must still pass the pinned formatter, analyzer, Flutter tests, source/docs checks, and Android debug APK build. Live PVE 9.2/8.4 tag field semantics, case behavior, large-inventory performance, TalkBack/font-scale behavior, and physical-device session/privacy checks remain open.

## Explicitly still deferred

This increment does **not** implement resource-pool browsing, tag creation/editing, pool membership workflows, cross-profile tagging, server-side tag queries, or the full premium HOME-007 feature. The premium catalog entry therefore remains `planned_unimplemented`.
