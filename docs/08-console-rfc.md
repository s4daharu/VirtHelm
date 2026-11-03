# RFC: Mobile Console Access — NOT IMPLEMENTED IN MVP

## Why this is a dedicated RFC
The official PVE permissions guide explicitly excludes virtual-machine/system-console endpoints from API-token access. Flutter Android noVNC/terminal implementations additionally have WebSocket, authentication-cookie, keyboard, clipboard, rotation and TLS trust challenges. Promising a token-only console is incorrect.

## User need
View and interact with QEMU graphical console or LXC terminal from an Android phone with accessible keyboard/control UI, resize, reconnect, clipboard policy and very short-lived authentication artifacts.

## Candidate technical pathways — verification required
1. User ticket auth session (`PVEAuthCookie` plus CSRF for HTTP mutations). Handle MFA/realm and expiry correctly.
2. PVE console proxy endpoints such as QEMU `vncproxy` and `vncwebsocket`, and LXC `vncproxy` or terminal endpoints where supported. Method, privilege, path, parameter types and returned ticket must be looked up in **both** supported PVE API viewers.
3. A hardened Android `WebView` hosting a vetted noVNC client vs native Dart VNC framebuffer/WebSocket integration. Evaluate origin policy, secure cookie injection, WebSocket headers, VNC ticket exposure, certificate chain validation, JS bridge attack surface and third-party license maintenance.
4. Avoid leaking `vncticket` in diagnostic URLs and redirects. Ensure VNC/session ticket lifetime and cleanup. No guaranteed console support through API-token-only mode.

## Research tasks
- Capture and redact actual 9.2 responses: `vncproxy`, `vncwebsocket`, LXC alternative; exercise permission denied and expired tickets.
- Investigate 2FA login and ticket renewal via official PVE docs and local API viewer.
- Verify Android WebView trust chain, HTTPOnly cookie, cross-origin handling, hybrid WebSocket authentication, keyboard input (Ctrl/Alt/Esc/F-keys) and mouse gestures.
- Confirm how reconnection works on app background/foreground and node failover.
- Decide dependency license/third-party script safety, CSP, bundle update strategy and offline assets.
- Test on actual VM boot firmware screen, Linux/Windows login, mobile IME and different DPI/rotation.

## Exit criteria to promote to P1/P2
All required authentication flows are documented with official versioned schema, console works with real-device secured WebSocket, no token leakage, TLS validation passes, permissions enforced, and the fallback clearly states console is unavailable without a user session. Until then, leave console control out of the feature list for released versions.
