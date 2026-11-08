# Accessibility and theme completion

This milestone completes the next source-level UI/accessibility block after
dedicated connection management. It changes local presentation only; live PVE
and physical Android validation remain separate release gates.

## Scope

- Appearance now supports **Device theme**, **Light**, **Dark**, and
  **AMOLED black**. AMOLED uses a true-black scaffold/navigation surface with
  near-black containers while preserving the existing Material 3 semantic
  color model.
- A persisted **High contrast** preference strengthens card/input/navigation
  boundaries and semantic status tones. Flutter's platform high-contrast
  themes are also supplied so Android accessibility contrast requests are
  respected independently of the app preference.
- A persisted **Reduce motion** preference removes theme-transition animation
  and sets the inherited MediaQuery animation-disable flag. Existing Android
  remove-animation accessibility state is preserved and ORed with the local
  preference rather than overridden.
- Shared text buttons now retain a 48dp minimum interactive target.
- Guest, node and storage RRD cards retain their textual latest/range summaries
  and now add:
  - visible 0/50/100% vertical-axis labels;
  - explicit usage-unit and time-range labels;
  - an on-demand read-only sample table with UTC timestamps and percentages.
- The sample table is built only from the already-loaded in-memory RRD response.
  It performs no network request and is not persisted.

## Local preference and security boundaries

The new high-contrast and reduced-motion flags use SharedPreferences alongside
the existing theme/refresh/display preferences. They are non-secret,
device-local settings and do not touch the encrypted credential vault.

There is no change to HTTPS/TLS policy, connection generations, API endpoints,
permissions, retry behavior, task polling, guest-write freshness checks,
single-flight mutation rules, unknown-outcome lockout or offline-count safety.

## Automated coverage

The Flutter suite adds coverage for:

- AMOLED true-black and high-contrast theme construction;
- chart axes and timestamped data-table presentation;
- persisted high-contrast and reduced-motion preferences without vault writes;
- AMOLED/high-contrast/reduced-motion application before onboarding;
- Settings layout at 360dp, 393dp and 412dp widths, in light and dark themes,
  at 200% text scaling.

Existing status-chip semantics continue to require text plus icon rather than
color-only meaning. Existing narrow-phone and staged-connection regressions
remain in the full suite.

## Deferred and device-only gates

- Android wallpaper-derived dynamic color remains optional and deferred. The
  stable VirtHelm seed avoids introducing a new platform/dependency path in
  this milestone.
- Physical TalkBack navigation, switch/accessibility announcements, color and
  contrast inspection, touch-target measurement, remove-animation behavior and
  device screenshots/goldens still require real Android verification.
- Live PVE 9.2/8.4 fixtures are unaffected by this presentation-only change and
  remain required for release compatibility claims.
- Native biometrics/app lock, notifications, widgets and shortcuts remain later
  milestones.
