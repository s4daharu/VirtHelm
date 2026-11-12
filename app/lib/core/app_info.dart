/// Display-only application identity.
///
/// `app/pubspec.yaml` remains the version source of truth. `check_source.py`
/// enforces that this display constant matches its `MAJOR.MINOR.PATCH` value so
/// screens never show a stale hand-maintained version again.
const String virthelmDisplayName = 'VirtHelm';
const String virthelmDisplayVersion = '0.1.53';
