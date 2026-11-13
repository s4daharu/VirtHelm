import 'package:flutter/services.dart';

import 'alert_rules.dart';
import 'models.dart';

const int _minutesPerDay = 24 * 60;
const int minimumBackgroundCheckIntervalMinutes = 15;
const int maximumBackgroundCheckIntervalMinutes = 24 * 60;

class BackgroundCheckException implements Exception {
  const BackgroundCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackgroundCheckPolicy {
  const BackgroundCheckPolicy({
    this.enabled = false,
    this.intervalMinutes = 30,
    this.quietHoursEnabled = false,
    this.quietStartMinute = 22 * 60,
    this.quietEndMinute = 7 * 60,
    this.cooldownMinutes = 30,
    this.failedTaskChecksEnabled = false,
    this.nodeCpuThresholdChecksEnabled = false,
    this.guestCpuThresholdChecksEnabled = false,
    this.storageUsageThresholdChecksEnabled = false,
  });

  final bool enabled;
  final int intervalMinutes;
  final bool quietHoursEnabled;
  final int quietStartMinute;
  final int quietEndMinute;
  final int cooldownMinutes;
  final bool failedTaskChecksEnabled;
  final bool nodeCpuThresholdChecksEnabled;
  final bool guestCpuThresholdChecksEnabled;
  final bool storageUsageThresholdChecksEnabled;

  BackgroundCheckPolicy validated() {
    if (intervalMinutes < minimumBackgroundCheckIntervalMinutes ||
        intervalMinutes > maximumBackgroundCheckIntervalMinutes ||
        quietStartMinute < 0 ||
        quietStartMinute >= _minutesPerDay ||
        quietEndMinute < 0 ||
        quietEndMinute >= _minutesPerDay ||
        quietStartMinute == quietEndMinute ||
        cooldownMinutes < 0 ||
        cooldownMinutes > _minutesPerDay) {
      throw const FormatException('Invalid scheduled-check policy.');
    }
    return this;
  }

  BackgroundCheckPolicy copyWith({
    bool? enabled,
    int? intervalMinutes,
    bool? quietHoursEnabled,
    int? quietStartMinute,
    int? quietEndMinute,
    int? cooldownMinutes,
    bool? failedTaskChecksEnabled,
    bool? nodeCpuThresholdChecksEnabled,
    bool? guestCpuThresholdChecksEnabled,
    bool? storageUsageThresholdChecksEnabled,
  }) => BackgroundCheckPolicy(
    enabled: enabled ?? this.enabled,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
    quietStartMinute: quietStartMinute ?? this.quietStartMinute,
    quietEndMinute: quietEndMinute ?? this.quietEndMinute,
    cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
    failedTaskChecksEnabled:
        failedTaskChecksEnabled ?? this.failedTaskChecksEnabled,
    nodeCpuThresholdChecksEnabled:
        nodeCpuThresholdChecksEnabled ?? this.nodeCpuThresholdChecksEnabled,
    guestCpuThresholdChecksEnabled:
        guestCpuThresholdChecksEnabled ?? this.guestCpuThresholdChecksEnabled,
    storageUsageThresholdChecksEnabled:
        storageUsageThresholdChecksEnabled ?? this.storageUsageThresholdChecksEnabled,
  );

  factory BackgroundCheckPolicy.fromChannel(Map<Object?, Object?> map) =>
      BackgroundCheckPolicy(
        enabled: map['enabled'] == true,
        intervalMinutes: _channelInt(map['intervalMinutes']) ?? 30,
        quietHoursEnabled: map['quietHoursEnabled'] == true,
        quietStartMinute: _channelInt(map['quietStartMinute']) ?? 22 * 60,
        quietEndMinute: _channelInt(map['quietEndMinute']) ?? 7 * 60,
        cooldownMinutes: _channelInt(map['cooldownMinutes']) ?? 30,
        failedTaskChecksEnabled: map['failedTaskChecksEnabled'] == true,
        nodeCpuThresholdChecksEnabled:
            map['nodeCpuThresholdChecksEnabled'] == true,
        guestCpuThresholdChecksEnabled:
            map['guestCpuThresholdChecksEnabled'] == true,
        storageUsageThresholdChecksEnabled:
            map['storageUsageThresholdChecksEnabled'] == true,
      ).validated();
}

class BackgroundCheckStatus {
  const BackgroundCheckStatus({
    this.policy = const BackgroundCheckPolicy(),
    this.lastAttemptAt,
    this.lastSuccessfulAt,
    this.lastNotificationAt,
    this.lastOutcome,
  });

  final BackgroundCheckPolicy policy;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessfulAt;
  final DateTime? lastNotificationAt;
  final String? lastOutcome;

  bool get enabled => policy.enabled;

  factory BackgroundCheckStatus.fromChannel(Object? value) {
    if (value is! Map) return const BackgroundCheckStatus();
    final map = Map<Object?, Object?>.from(value);
    return BackgroundCheckStatus(
      policy: BackgroundCheckPolicy.fromChannel(map),
      lastAttemptAt: _channelDate(map['lastAttemptMs']),
      lastSuccessfulAt: _channelDate(map['lastSuccessMs']),
      lastNotificationAt: _channelDate(map['lastNotificationMs']),
      lastOutcome: map['lastOutcome'] is String
          ? map['lastOutcome'] as String
          : null,
    );
  }
}

abstract class BackgroundCheckScheduler {
  Future<BackgroundCheckStatus> status(String profileId);

  Future<void> configure(
    ConnectionProfile profile,
    ApiCredentials credentials,
    BackgroundCheckPolicy policy,
  );

  Future<void> disable(String profileId, {bool clearPolicy = false});
}

abstract interface class ThresholdAwareBackgroundCheckScheduler {
  Future<void> configureWithThresholdRules(
    ConnectionProfile profile,
    ApiCredentials credentials,
    BackgroundCheckPolicy policy,
    Iterable<ForegroundThresholdAlertRule> rules,
  );

  Future<void> syncThresholdRules(
    String profileId,
    Iterable<ForegroundThresholdAlertRule> rules,
  );
}

class AndroidBackgroundCheckScheduler
    implements
        BackgroundCheckScheduler,
        ThresholdAwareBackgroundCheckScheduler {
  const AndroidBackgroundCheckScheduler();

  static const MethodChannel _channel = MethodChannel(
    'com.s4daharu.virthelm/background_checks',
  );

  @override
  Future<BackgroundCheckStatus> status(String profileId) async {
    try {
      return BackgroundCheckStatus.fromChannel(
        await _channel.invokeMethod<Object?>('status', {
          'profileId': profileId,
        }),
      );
    } on MissingPluginException {
      return const BackgroundCheckStatus();
    } on PlatformException catch (error) {
      throw BackgroundCheckException(
        error.message ?? 'Could not read scheduled-check status.',
      );
    }
  }

  @override
  Future<void> configure(
    ConnectionProfile profile,
    ApiCredentials credentials,
    BackgroundCheckPolicy policy,
  ) => _configure(profile, credentials, policy, const []);

  @override
  Future<void> configureWithThresholdRules(
    ConnectionProfile profile,
    ApiCredentials credentials,
    BackgroundCheckPolicy policy,
    Iterable<ForegroundThresholdAlertRule> rules,
  ) => _configure(profile, credentials, policy, rules);

  Future<void> _configure(
    ConnectionProfile profile,
    ApiCredentials credentials,
    BackgroundCheckPolicy policy,
    Iterable<ForegroundThresholdAlertRule> rules,
  ) async {
    final validated = policy.validated();
    if (!validated.enabled) {
      throw const FormatException('Scheduled checks must be enabled first.');
    }
    if (profile.allowInvalidCertificates) {
      throw const FormatException(
        'Scheduled checks require certificate and hostname verification.',
      );
    }
    if (!credentials.isValid) {
      throw const BackgroundCheckException(
        'Saved API token is unavailable or invalid.',
      );
    }
    try {
      final configured =
          await _channel.invokeMethod<bool>('configure', {
            'profileId': profile.id,
            'endpoint': profile.endpoint,
            'authorization': credentials.header,
            'intervalMinutes': validated.intervalMinutes,
            'quietHoursEnabled': validated.quietHoursEnabled,
            'quietStartMinute': validated.quietStartMinute,
            'quietEndMinute': validated.quietEndMinute,
            'cooldownMinutes': validated.cooldownMinutes,
            'failedTaskChecksEnabled': validated.failedTaskChecksEnabled,
            'nodeCpuThresholdChecksEnabled':
                validated.nodeCpuThresholdChecksEnabled,
            'guestCpuThresholdChecksEnabled':
                validated.guestCpuThresholdChecksEnabled,
            'storageUsageThresholdChecksEnabled':
                validated.storageUsageThresholdChecksEnabled,
            'nodeCpuThresholdRules': validated.nodeCpuThresholdChecksEnabled
                ? _nodeCpuRuleChannelPayload(rules)
                : const <Map<String, Object?>>[],
            'guestCpuThresholdRules': validated.guestCpuThresholdChecksEnabled
                ? _guestCpuRuleChannelPayload(rules)
                : const <Map<String, Object?>>[],
            'storageUsageThresholdRules': validated.storageUsageThresholdChecksEnabled
                ? _storageUsageRuleChannelPayload(rules)
                : const <Map<String, Object?>>[],
          }) ??
          false;
      if (!configured) {
        throw const BackgroundCheckException(
          'Android could not schedule periodic checks.',
        );
      }
    } on MissingPluginException {
      throw const BackgroundCheckException(
        'Scheduled Android checks are unavailable in this build.',
      );
    } on PlatformException catch (error) {
      throw BackgroundCheckException(
        error.message ?? 'Android could not schedule periodic checks.',
      );
    }
  }

  @override
  Future<void> syncThresholdRules(
    String profileId,
    Iterable<ForegroundThresholdAlertRule> rules,
  ) async {
    try {
      final synced =
          await _channel.invokeMethod<bool>('syncThresholdRules', {
            'profileId': profileId,
            'nodeCpuThresholdRules': _nodeCpuRuleChannelPayload(rules),
            'guestCpuThresholdRules': _guestCpuRuleChannelPayload(rules),
            'storageUsageThresholdRules': _storageUsageRuleChannelPayload(rules),
          }) ??
          false;
      if (!synced) {
        throw const BackgroundCheckException(
          'Android could not update scheduled threshold rules.',
        );
      }
    } on MissingPluginException {
      // Unit/widget hosts have no native worker state to synchronize.
    } on PlatformException catch (error) {
      throw BackgroundCheckException(
        error.message ?? 'Android could not update scheduled threshold rules.',
      );
    }
  }

  @override
  Future<void> disable(String profileId, {bool clearPolicy = false}) async {
    try {
      await _channel.invokeMethod<void>('disable', {
        'profileId': profileId,
        'clearPolicy': clearPolicy,
      });
    } on MissingPluginException {
      // Unit/widget hosts do not install the Android bridge. There is no
      // native credential copy to clear on those hosts.
    } on PlatformException catch (error) {
      throw BackgroundCheckException(
        error.message ?? 'Could not disable scheduled checks.',
      );
    }
  }
}

int? _channelInt(Object? value) => value is int ? value : null;

DateTime? _channelDate(Object? value) {
  final milliseconds = _channelInt(value);
  if (milliseconds == null || milliseconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

List<Map<String, Object?>> _nodeCpuRuleChannelPayload(
  Iterable<ForegroundThresholdAlertRule> rules,
) => rules
    .where(
      (rule) =>
          rule.enabled && rule.metric == ForegroundThresholdMetric.nodeCpu,
    )
    .take(maxForegroundThresholdRules)
    .map(
      (rule) => <String, Object?>{
        'id': rule.id,
        'node': rule.node,
        'thresholdPercent': rule.thresholdPercent,
        'consecutiveSamples': rule.consecutiveSamples,
        'hysteresisPercent': rule.hysteresisPercent,
      },
    )
    .toList(growable: false);

List<Map<String, Object?>> _guestCpuRuleChannelPayload(
  Iterable<ForegroundThresholdAlertRule> rules,
) => rules
    .where(
      (rule) =>
          rule.enabled && rule.metric == ForegroundThresholdMetric.guestCpu,
    )
    .take(maxForegroundThresholdRules)
    .map(
      (rule) => <String, Object?>{
        'id': rule.id,
        'node': rule.node,
        'guestKind': rule.guestKind,
        'vmid': rule.guestVmid,
        'thresholdPercent': rule.thresholdPercent,
        'consecutiveSamples': rule.consecutiveSamples,
        'hysteresisPercent': rule.hysteresisPercent,
      },
    )
    .toList(growable: false);

List<Map<String, Object?>> _storageUsageRuleChannelPayload(
  Iterable<ForegroundThresholdAlertRule> rules,
) => rules
    .where(
      (rule) =>
          rule.enabled && rule.metric == ForegroundThresholdMetric.storageUsage,
    )
    .take(maxForegroundThresholdRules)
    .map(
      (rule) => <String, Object?>{
        'id': rule.id,
        'node': rule.node,
        'storageId': rule.storageId,
        'thresholdPercent': rule.thresholdPercent,
        'consecutiveSamples': rule.consecutiveSamples,
        'hysteresisPercent': rule.hysteresisPercent,
      },
    )
    .toList(growable: false);
