# Premium Branding, Pricing Options, Privacy and Licensing
“Premium” describes **product quality and richness**, not a decision that payment is required. This plan does not set prices, create subscriptions or assert trademark clearance.

## Naming and positioning
App: **VirtHelm**. Suggested explanatory subtitle: “Mobile control for Proxmox VE” with clear **unofficial, independent** disclosure. Do not imply endorsement or use Proxmox logo/marks as app icon without permission. Verify name/app ID/domain/social and trademarks before launch.

## Possible business models (decision pending)
1. **One-time paid Android app:** simplest consumer entitlement if sustainable support costs.
2. **Free core + Pro purchase:** monitoring/control basics free; advanced conveniences paid. Security, privacy, accessibility, backup warnings and user data export must never be locked behind payment.
3. **Pro subscription:** only if recurring **real** service costs justify (e.g. optional managed alert delivery); avoid subscription for features that are fully local and do not incur ongoing infrastructure costs.
4. **Enterprise license / managed deployment:** operational teams may need device fleet policy, custom branding and compliance support; evaluate separately from consumer UX.
5. **Open core + paid convenience:** requires explicit OSS license and third-party package compliance review, not assumed.

If distributed on Google Play and selling digital features, follow current Google Play billing and consumer disclosure rules as applicable. No invented 2026 fixed pricing/target SDK. Check policies and tax obligations before publication.

## Premium packaging proposal
Core: secure unlimited local profile *viewing* and essential guest controls, depending on final pricing tests. Pro: dashboards, advanced analytics, configurable alert rules, saved views, bulk planner, guided operations, backup confidence indicators, advanced charts, personalized widgets. Enterprise optional: self-hosted relay support, policy presets, cross-site operations, group provisioning once backed by actual services. **Never** market console or alert SLA until verified and delivered.

## Privacy model
By default the app communicates **only** with user-configured Proxmox endpoints and OS platform services necessary for functionality. No VirtHelm account or cloud required. Do not collect production guest names, tokens, network topology or task logs for product analytics by default. Opt-in crash diagnostics must redact and expose a user-visible preview. Provide per-profile cache clearing and export/delete options. For optional relay, write explicit data processing inventory, event payload and retention policy before enabling.

## Security/legal gates
- Review Proxmox trademark guidelines and user-facing legal disclaimer.
- Audit external console/JS assets and dependencies under relevant licenses; a private repository does not remove license obligations.
- Security and privacy policies before beta, vulnerability disclosure and contact path, release notes and support matrix.
- Payments and licensing must not affect server ACL checks or cause a credential transfer to payment provider.
- Accurate marketing claims: distinguish “PVE” from “PBS” and “PDM”; clearly label required server versions and optional relay.

## UX quality and retention
Use voluntary satisfaction survey after stable action success, no intrusive nagging when an incident is active. Offer non-tracking onboarding checklist and tutorial fixtures (synthetic demo data only). Let users inspect all security controls before an optional Pro purchase. All paid features must gracefully degrade on offline entitlement checks without blocking essential emergency visibility during subscription outages; entitlement architecture research required.
