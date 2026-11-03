# Delivery Roadmap and Engineering Backlog

No timelines are guaranteed until the team sizes stories, gains a PVE test lab and confirms auth/TLS approach. “Done” means tests and documented evidence, not code compiled once.

## Milestone 0 — Foundations
- **E00-01:** create private GitHub repo; restrict access; branch protection, CODEOWNERS/issue templates; audit dependency licenses.
- **E00-02:** generate Android-only Flutter app with stable pinned SDK/toolchain; lints, formatter, test infra and CI.
- **E00-03:** investigate versioned PVE 9.2 & 8.4 API viewer, capture read/write fixtures and ACL requirements, confirm URL-encoding semantics.
- **E00-04:** decide secure per-profile TLS/trust for internal CA and reverse proxy; obtain security review.

## Milestone 1 — Secure connection and read-only MVP
- **E01-01:** onboarding/connection profile CRUD, URL and port parser, encrypted token store.
- **E01-02:** scoped HTTP API client with correct token header, standard envelope/error mapping, redact logs.
- **E01-03:** version/cluster/node discovery and read-only state; connection health and access diagnostics.
- **E01-04:** VM/LXC list and typed detail, missing fields, metrics formatting, refresh/stale status.
- **E01-05:** storage overview, guests filters/search, favorites, Android UI accessibility.
- **E01-06:** unit/widget/integration/security tests with PVE 9.2 & 8.4 evidence.

## Milestone 2 — Guest actions + task tracking
- **E02-01:** QEMU start/shutdown/reboot/stop API + preflight confirmation + UPID state machine.
- **E02-02:** LXC action implementations with separate supported parameters and guarded UI.
- **E02-03:** task list/detail and terminal success/failure, retries on reads only, unknown write outcomes.
- **E02-04:** permission/revocation/timeout test suite; failure recovery and cluster-switch races.
- **E02-05:** signed internal Android release, manual exploratory test, PRD acceptance review.

## Milestone 3 — Advanced read-only and administration (P1)
- **E03-01:** graphs/metrics, additional node storage/task details.
- **E03-02:** ticket/password + TFA research/design/implementation with CSRF.
- **E03-03:** snapshots/backup operations separately reviewed for data loss potential.

## Milestone 4 — High-risk follow-ups (P2)
- **E04-01:** prototype noVNC/xterm.js only after console RFC acceptance.
- **E04-02:** creation/cloning/migration, bulk actions and host changes behind explicit high-risk authorization UX.

## Prioritization and dependencies
`E00-04 -> E01-01/E01-02 -> E01-03 -> E01-04/E01-05 -> E02-01/E02-02 -> E02-03 -> E02-05`. P1 2FA ticket is a prerequisite for console, not required to ship API-token-only MVP. Each issue should contain: story, versioned endpoint, test cases, roll-back/abort, security review and accepted evidence.

## Issue creation template
```markdown
### Outcome
What user can safely accomplish
### Scope and PVE compatibility
Version(s), methods, params, permission scope
### Acceptance criteria
- [ ] Happy path with fixture
- [ ] 401/403, timeout and malformed API handling
- [ ] Security: no sensitive logs and TLS verified
- [ ] Android unit/widget/integration checks
- [ ] Change log, UX accessibility, rollback note
### Evidence
Links to PR, fixture and test run
```
