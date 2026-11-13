import 'package:flutter/services.dart';

const int _minutesPerDay = 24 * 60;

enum IncidentNotificationLockScreenPrivacy { hidden, generic }

IncidentNotificationLockScreenPrivacy
incidentNotificationLockScreenPrivacyFromStorage(Object? value) {
  if (value == IncidentNotificationLockScreenPrivacy.generic.name) {
    return IncidentNotificationLockScreenPrivacy.generic;
  }
  return IncidentNotificationLockScreenPrivacy.hidden;
}

class ForegroundNotificationPolicy {
  const ForegroundNotificationPolicy({
    this.enabled = false,
    this.quietHoursEnabled = false,
    this.quietStartMinute = 22 * 60,
    this.quietEndMinute = 7 * 60,
    this.cooldownMinutes = 30,
  });

  final bool enabled;
  final bool quietHoursEnabled;
  final int quietStartMinute;
  final int quietEndMinute;
  final int cooldownMinutes;

  bool isQuietAt(DateTime localTime) {
    if (!quietHoursEnabled) return false;
    final minute = localTime.hour * 60 + localTime.minute;
    if (quietStartMinute < quietEndMinute) {
      return minute >= quietStartMinute && minute < quietEndMinute;
    }
    return minute >= quietStartMinute || minute < quietEndMinute;
  }

  bool canDeliverAt(DateTime localTime, {DateTime? lastDeliveredAt}) {
    if (!enabled || isQuietAt(localTime)) return false;
    final previous = lastDeliveredAt;
    if (previous == null || cooldownMinutes == 0) return true;
    return localTime.toUtc().difference(previous.toUtc()) >=
        Duration(minutes: cooldownMinutes);
  }

  ForegroundNotificationPolicy copyWith({
    bool? enabled,
    bool? quietHoursEnabled,
    int? quietStartMinute,
    int? quietEndMinute,
    int? cooldownMinutes,
  }) => ForegroundNotificationPolicy(
    enabled: enabled ?? this.enabled,
    quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
    quietStartMinute: quietStartMinute ?? this.quietStartMinute,
    quietEndMinute: quietEndMinute ?? this.quietEndMinute,
    cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'quiet_hours_enabled': quietHoursEnabled,
    'quiet_start_minute': quietStartMinute,
    'quiet_end_minute': quietEndMinute,
    'cooldown_minutes': cooldownMinutes,
  };

  factory ForegroundNotificationPolicy.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'] ?? false;
    final quietHoursEnabled = json['quiet_hours_enabled'] ?? false;
    final quietStartMinute = json['quiet_start_minute'] ?? 22 * 60;
    final quietEndMinute = json['quiet_end_minute'] ?? 7 * 60;
    final cooldownMinutes = json['cooldown_minutes'] ?? 30;
    if (enabled is! bool ||
        quietHoursEnabled is! bool ||
        quietStartMinute is! int ||
        quietStartMinute < 0 ||
        quietStartMinute >= _minutesPerDay ||
        quietEndMinute is! int ||
        quietEndMinute < 0 ||
        quietEndMinute >= _minutesPerDay ||
        quietStartMinute == quietEndMinute ||
        cooldownMinutes is! int ||
        cooldownMinutes < 0 ||
        cooldownMinutes > _minutesPerDay) {
      throw const FormatException('Invalid foreground notification policy.');
    }
    return ForegroundNotificationPolicy(
      enabled: enabled,
      quietHoursEnabled: quietHoursEnabled,
      quietStartMinute: quietStartMinute,
      quietEndMinute: quietEndMinute,
      cooldownMinutes: cooldownMinutes,
    );
  }
}

abstract class ForegroundIncidentNotifier {
  Future<bool> requestPermission();
  Future<bool> setLockScreenPrivacy(
    IncidentNotificationLockScreenPrivacy privacy,
  );
  Future<bool> showIncidentSummary({
    required bool critical,
    required String profileId,
    required int cooldownMinutes,
    String? incidentKey,
  });
}

class AndroidForegroundIncidentNotifier implements ForegroundIncidentNotifier {
  const AndroidForegroundIncidentNotifier();

  static const MethodChannel _channel = MethodChannel(
    'com.s4daharu.virthelm/incident_notifications',
  );

  @override
  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> setLockScreenPrivacy(
    IncidentNotificationLockScreenPrivacy privacy,
  ) async {
    try {
      return await _channel.invokeMethod<bool>('setLockScreenPrivacy', {
            'privacy': privacy.name,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> showIncidentSummary({
    required bool critical,
    required String profileId,
    required int cooldownMinutes,
    String? incidentKey,
  }) async {
    final target = incidentKey?.trim();
    if (profileId.trim().isEmpty ||
        profileId.length > 256 ||
        cooldownMinutes < 0 ||
        cooldownMinutes > _minutesPerDay ||
        target != null &&
            (target.isEmpty ||
                target.length > 1200 ||
                target.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f))) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('showIncidentSummary', {
            'critical': critical,
            'profileId': profileId,
            'cooldownMinutes': cooldownMinutes,
            'incidentKey': ?target,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
