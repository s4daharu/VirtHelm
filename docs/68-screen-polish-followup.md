# Screen polish follow-up — recovery actions, incident summary and about surface

This note records the second UI-foundation slice. It is source-level synthetic coverage only; it is not physical Android, TalkBack, performance, live PVE or release evidence.

## Scope

- Home metric cards now use tinted icon containers, a clearer value hierarchy and tabular figures.
- The Incidents tab shows a critical/warning severity summary above the filters and offers safe recovery actions:
  - “Show all incidents” for an empty severity filter;
  - “Refresh” when live health cannot be confirmed.
- Guest and task screens expose a local “Clear filters” action when search, status, type, node, tag or pool criteria hide the list. Task search text is now cleared with the other criteria.
- Empty guest and task states offer an explicit foreground refresh action instead of relying only on pull-to-refresh.
- Task details adds an app-bar refresh action while preserving the existing text button and bounded page navigation.
- Connect adds URL/username/password autofill hints and submits from the token-secret keyboard action.
- Settings adds an About card with the enforced display version and an open-source license page.
- Sparklines gain subtle grid lines and a soft area fill while keeping the existing latest/range/sample text alternative.

## Safety boundaries

- Presentation-only: no API endpoint, credential, persistence, TLS, POST retry, freshness guard or mutation behavior changed.
- Filter clearing is local widget state and does not trigger a network read.
- Incident and task refresh actions call the existing foreground refresh path; they do not queue offline commands or replay writes.
- Task logs remain on-demand, bounded and non-persistent; the About licenses page is local Flutter metadata.

## Verification

- `flutter analyze --fatal-infos` passes.
- The full Flutter suite passes locally: 160 tests.
- `dart format --output=none --set-exit-if-changed` reports no changes.
- Documentation/source/premium checks and delivery unit tests pass.
- Physical Android TalkBack, 200% text, contrast, 360/393/412dp screenshots and performance benchmarks remain open.
- Live PVE 9.2/8.4 fixtures are unaffected by this presentation-only slice.

## Remaining screen work

Dedicated connection management, AMOLED/high-contrast themes, app lock/biometrics, notification surfaces, golden/device screenshots and physical Android validation remain future work.
