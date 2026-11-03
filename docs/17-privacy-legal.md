# Privacy, Licensing, Naming and Distribution

## Data minimization
- No cloud account, analytics SDK, advertising or third-party tracking in MVP.
- Connect directly from device to user's configured server. Local profiles contain server URL/alias and encrypted access token reference. Secret does not leave phone except to authenticated PVE endpoint.
- Optional non-sensitive local cache stores authorized infrastructure metadata; storage encryption policy and auto-backup scope must be documented and tested. Let user delete profile/cache easily.
- Logs exclude server URL/IP, guest names, usernames, tasks and secrets by default. User chooses explicit redacted diagnostics export. Session tickets and VNC tickets must never be shared.

## Permissions
Only request Android permissions necessary for network access and optional biometrics. No SMS, contacts, storage-wide, phone call or location permission. Avoid hidden background processing. Background notifications, if ever added, require separate privacy and Android platform review.

## Trademark and affiliation
VirtHelm is an **unofficial**, independently developed client. Product naming, Play Store description and icon must not imply endorsement by Proxmox Server Solutions GmbH. Review Proxmox trademark guidelines and third-party SDK/plugin licenses before publishing. Avoid redistributing Proxmox logos or proprietary assets without permission; reference Proxmox brand nominatively in plain text where appropriate.

## Security disclosure / legal compliance
Use `SECURITY.md` for responsible security reports; keep private issue access restricted to collaborators. Release public privacy policy if distributing via Play; comply with store data safety form based on actual implementation, not this design-only plan. Review local/regional requirements if any analytics, cloud sync or payment is added later.
