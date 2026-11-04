// Non-secret, device-local UI preferences. No server data or credentials.
enum AppThemePreference { system, light, dark }

enum AutoRefreshPreference { off, every30Seconds, every60Seconds, every120Seconds }

extension AutoRefreshInterval on AutoRefreshPreference {
  Duration? get interval => switch (this) {
    AutoRefreshPreference.off => null,
    AutoRefreshPreference.every30Seconds => const Duration(seconds: 30),
    AutoRefreshPreference.every60Seconds => const Duration(minutes: 1),
    AutoRefreshPreference.every120Seconds => const Duration(minutes: 2),
  };
}
