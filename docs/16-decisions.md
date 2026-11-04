# Architecture Decision Records (ADRs)

## ADR-001: Android phone only
**Status:** Accepted for scope. **Decision:** generate only Android runner under `app/`; no iOS, desktop or web target. **Rationale:** smaller QA surface, native Android secure storage/toolchain. **Consequences:** mobile-specific UX design, Android release policy responsibilities.

## ADR-002: Flutter + Dart layered MVVM
**Status:** Accepted. **Decision:** separate UI/viewmodels, domain contracts and data repositories/services, with Riverpod as a candidate project state mechanism. **Rationale:** testability and evolving PVE API. **Alternatives:** BLoC, raw ChangeNotifier; do not mix multiple app-wide state owners without need.

## ADR-003: Direct PVE connection, no cloud backend
**Status:** Accepted. **Decision:** on-device HTTPS client through LAN/VPN; multiple local profiles. **Consequences:** mobile device must reach server, PVE security boundary is critical; push notifications deferred.

## ADR-004: API-token MVP, ticket auth later
**Status:** Accepted with official restriction. **Decision:** least-privilege token first; no console; ticket+2FA separate track. **Rationale:** token lifecycle, stateless access and scope. **Risk:** lack of console until supported session auth built.

## ADR-005: Strict TLS by default; explicit profile-local exception
**Status:** Revised by user request. **Decision:** default to fail-closed certificate chain/hostname validation. Permit a saved per-connection insecure opt-in for any HTTPS host, confirmed before onboarding requests with exact origin and risk disclosure. Keep HTTPS, redirect rejection, client/profile isolation and persistent warnings. **Rejected alternatives:** global bypass and silent fallback. **Risk:** opting in allows MITM, credential theft and command tampering, even on LAN/VPN. Trusted certificates remain recommended. See [TLS option](40-profile-tls-option.md); this revision supersedes earlier blanket no-bypass statements in planning documents.

## ADR-006: No automatic write retries
**Status:** Accepted. **Decision:** retry only idempotent reads; timeouts after POST produce unknown result and user reconciliation. **Rationale:** eliminate duplicate guest lifecycle requests.

## ADR-007: Console as separate RFC
**Status:** Accepted. **Decision:** no promised token-only noVNC. **Prerequisite:** PVE console auth / WebSocket verification and Android UX/security spike.

## ADR-008: PVE 9.2 primary, 8.4 regression
**Status:** Proposed until tests pass. **Rationale:** official release listing and older installed base; exact API compatibility unproven. **Consequence:** maintain version fixture matrix and fallbacks.
