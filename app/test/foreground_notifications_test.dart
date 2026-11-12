import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/foreground_notifications.dart';

void main() {
  test('quiet hours support overnight and same-day ranges', () {
    const overnight = ForegroundNotificationPolicy(
      enabled: true,
      quietHoursEnabled: true,
      quietStartMinute: 22 * 60,
      quietEndMinute: 7 * 60,
    );
    expect(overnight.isQuietAt(DateTime(2026, 11, 12, 23)), isTrue);
    expect(overnight.isQuietAt(DateTime(2026, 11, 13, 6, 59)), isTrue);
    expect(overnight.isQuietAt(DateTime(2026, 11, 13, 7)), isFalse);
    expect(overnight.isQuietAt(DateTime(2026, 11, 12, 15)), isFalse);

    const daytime = ForegroundNotificationPolicy(
      enabled: true,
      quietHoursEnabled: true,
      quietStartMinute: 12 * 60,
      quietEndMinute: 13 * 60,
    );
    expect(daytime.isQuietAt(DateTime(2026, 11, 12, 12, 30)), isTrue);
    expect(daytime.isQuietAt(DateTime(2026, 11, 12, 13)), isFalse);
  });

  test('cooldown suppresses repeat delivery without changing policy state', () {
    const policy = ForegroundNotificationPolicy(
      enabled: true,
      cooldownMinutes: 30,
    );
    final previous = DateTime.utc(2026, 11, 12, 8);
    expect(
      policy.canDeliverAt(
        DateTime.utc(2026, 11, 12, 8, 29),
        lastDeliveredAt: previous,
      ),
      isFalse,
    );
    expect(
      policy.canDeliverAt(
        DateTime.utc(2026, 11, 12, 8, 30),
        lastDeliveredAt: previous,
      ),
      isTrue,
    );
  });

  test('disabled or quiet policy never authorizes delivery', () {
    const disabled = ForegroundNotificationPolicy();
    expect(disabled.canDeliverAt(DateTime(2026, 11, 12, 12)), isFalse);

    const quiet = ForegroundNotificationPolicy(
      enabled: true,
      quietHoursEnabled: true,
      quietStartMinute: 8 * 60,
      quietEndMinute: 18 * 60,
      cooldownMinutes: 0,
    );
    expect(quiet.canDeliverAt(DateTime(2026, 11, 12, 10)), isFalse);
    expect(quiet.canDeliverAt(DateTime(2026, 11, 12, 19)), isTrue);
  });

  test('serialized policy is validated and rejects malformed bounds', () {
    const policy = ForegroundNotificationPolicy(
      enabled: true,
      quietHoursEnabled: true,
      quietStartMinute: 23 * 60,
      quietEndMinute: 6 * 60,
      cooldownMinutes: 60,
    );
    final decoded = ForegroundNotificationPolicy.fromJson(policy.toJson());
    expect(decoded.enabled, isTrue);
    expect(decoded.quietStartMinute, 23 * 60);
    expect(decoded.quietEndMinute, 6 * 60);
    expect(decoded.cooldownMinutes, 60);

    expect(
      () => ForegroundNotificationPolicy.fromJson({
        'enabled': true,
        'quiet_hours_enabled': true,
        'quiet_start_minute': 60,
        'quiet_end_minute': 60,
        'cooldown_minutes': 30,
      }),
      throwsFormatException,
    );
    expect(
      () => ForegroundNotificationPolicy.fromJson({
        'enabled': true,
        'quiet_hours_enabled': false,
        'quiet_start_minute': 0,
        'quiet_end_minute': 1,
        'cooldown_minutes': 1441,
      }),
      throwsFormatException,
    );
  });
}
