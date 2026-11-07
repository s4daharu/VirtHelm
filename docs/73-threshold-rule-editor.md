# Threshold-rule editor and searchable target picker

This note records the alert-rule editing overhaul. It is source-level synthetic coverage only; it is not physical Android, TalkBack, performance, live PVE or release evidence.

## Structure

- Creating or editing a foreground threshold rule now opens a full-screen editor instead of a cramped dialog.
- The editor contains:
  - Target selector with a searchable, grouped picker for **Nodes / Guests / Storage**.
  - Threshold slider and current percentage.
  - Consecutive usable-sample selector (1–10).
  - Clear-hysteresis slider with the resulting clear threshold.
  - Warning/Critical severity choice.
  - A plain-language rule summary.
  - Bottom Cancel / Add rule or Save changes actions.
- Rule cards remain switchable and deletable, and tapping a rule opens the same editor prefilled.
- If an existing rule’s target is no longer visible in live inventory, the editor keeps the saved target available for review or replacement instead of dropping it.

## Safety boundaries

- Rules remain profile-scoped non-secret local metadata. No background worker, WorkManager job, Android notification or relay/webhook delivery is added.
- Evaluation remains foreground-only and derived from existing live inventory/storage reads.
- The rule list still refuses edits after a connection/profile change; a returned editor result is discarded unless the original profile and connection generation are still current.
- No API endpoint, credential, persistence or mutation behavior changes.

## Verification

- `flutter analyze --fatal-infos` passes.
- The full Flutter suite passes locally: 162 tests.
- Added a regression for editing an existing rule through the searchable grouped target picker and changing severity.
- The original add-rule regression still verifies the threshold/sample/hysteresis controls and saved 80% rule.
- Physical Android TalkBack, large-text editor layout, touch-target and 360/393/412dp review remain open.

## Remaining work

Dedicated connection management, AMOLED/high-contrast themes, app lock/biometrics, notification surfaces and golden/device screenshots remain future work.
