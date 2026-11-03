# Premium Architecture Decisions and Risk Register — v2
This document is normative for future RFCs unless superseded by a reviewed ADR. Proposed decisions are not evidence of an implemented app.

## Decisions
**ADR-P01** Android phones only; Flutter/Dart, no other platform runners. Rationale: focus polish and test budget. Review on distribution demand.
**ADR-P02** Direct PVE API by default and local-first data. Rationale: no cloud trust requirement. Consequence: background and cross-site reliability limited by phone connectivity.
**ADR-P03** Optional self-hosted relay (future) only for reliable remote alerts. No required vendor backend. Must separately authenticate and be auditable/revocable.
**ADR-P04** Separate backend adapters and auth secrets for PVE, PBS and PDM. No endpoint/password interchangeability.
**ADR-P05** No unattended high-risk writes or hidden server-side scripts. Human confirmation for R2+, elevated preflight for R3/R4.
**ADR-P06** API token first, PVE ticket/MFA later, interactive console only after security RFC. No console with API token alone.
**ADR-P07** Every metric and UI status has source and age. Unknown/permission denied never reported “healthy.”
**ADR-P08** Fail closed on cert change, redirect origin change, missing permission evidence, stale target or unknown side effect.
**ADR-P09** AI is explanatory and opt-in only; never act autonomously on infrastructure.
**ADR-P10** Premium UX must be accessible and secure regardless of eventual price/plan.

## Risk register
| ID | Risk | Severity | Response |
|---|---|---|---|
| K01 | accidental wrong-cluster destructive mutation | Critical | immutable profile identity, origin-bound session, preflight generation, second confirmation |
| K02 | TLS misconfiguration/token exposure | Critical | no bypass, secure storage, MITM tests, secrets scan |
| K03 | unaudited HA/quorum/SDN actions cause outage | Critical | read-only first, multi-node lab and operator runbook |
| K04 | backup assumed restorable | Critical | recovery confidence stages and tested restore procedure |
| K05 | failed/ambiguous writes retried automatically | Critical | single submit, UPID correlation and unknown outcome UX |
| K06 | Android background checks mistaken for 24/7 paging | High | limitations copy, optional self-hosted relay |
| K07 | console auth flow fails for MFA realm | High | gated RFC, auth matrix, no premature feature claim |
| K08 | inconsistent RRD units/time zone imply false capacity data | High | typed metrics/quality and unit golden tests |
| K09 | PDM/PBS API versions diverge from PVE | High | independent feature adapters/version manifest |
| K10 | third-party packages/JS licenses or vulnerabilities | High | SBOM, pins, CVE/licensing review |
| K11 | app name/trademark conflicts | Medium | legal clearance and independent disclaimer |
| K12 | feature overload delays reliable release | High | tiered ship gates and scope cap |
| K13 | local cache leaks site names on stolen phone | High | encryption/minimization, retention and lock-screen defaults |
| K14 | user pays for feature not functional on version/ACL | High | pre-purchase compatibility disclosures and graceful fallback |

## Open decisions
Exact min SDK/target SDK based on current Flutter/dependency/Play constraints; chosen chart and VNC libraries; optional relay architecture; premium pricing/licensing; SQLite encryption or ephemeral cache; 9.2-specific capability detection; official supported distribution channel. Resolve with evidence and ADR rather than assuming “latest” package versions remain correct.

## Change control
Every rejected/accepted proposal captures owner, date, alternatives, security trade-offs, source/evidence link, breaking API impacts and rollback. This prevents generated plans from being mistaken for approved production behavior.
