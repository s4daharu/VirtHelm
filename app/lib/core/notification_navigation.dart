import 'package:flutter/services.dart';

const int maxIncidentNavigationCandidates = 128;
final RegExp _targetHashPattern = RegExp(r'^[0-9a-f]{64}$');

class IncidentNavigationRequest {
  const IncidentNavigationRequest({this.targetHash});

  final String? targetHash;

  static IncidentNavigationRequest? fromChannel(Object? value) {
    if (value is! Map) return null;
    final map = Map<Object?, Object?>.from(value);
    if (map['open'] != true) return null;
    final rawTarget = map['targetHash'];
    final target = rawTarget is String && _targetHashPattern.hasMatch(rawTarget)
        ? rawTarget
        : null;
    return IncidentNavigationRequest(targetHash: target);
  }
}

typedef IncidentNavigationHandler = void Function(IncidentNavigationRequest);

abstract interface class IncidentNavigationTargetResolver {
  Future<String?> resolveIncidentTarget({
    required String profileId,
    required String targetHash,
    required Iterable<String> incidentKeys,
  });
}

abstract class IncidentNotificationNavigation
    implements IncidentNavigationTargetResolver {
  Future<IncidentNavigationRequest?> takePendingIncidentIntent();
  void listen(IncidentNavigationHandler handler);
  void dispose();
}

class AndroidIncidentNotificationNavigation
    implements IncidentNotificationNavigation {
  const AndroidIncidentNotificationNavigation();

  static const MethodChannel _channel = MethodChannel(
    'com.s4daharu.virthelm/incident_navigation',
  );

  @override
  Future<IncidentNavigationRequest?> takePendingIncidentIntent() async {
    try {
      return IncidentNavigationRequest.fromChannel(
        await _channel.invokeMethod<Object?>('takePendingIncidentIntent'),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  void listen(IncidentNavigationHandler handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openIncidents') {
        final request =
            IncidentNavigationRequest.fromChannel(call.arguments) ??
            const IncidentNavigationRequest();
        handler(request);
        return true;
      }
      return null;
    });
  }

  @override
  Future<String?> resolveIncidentTarget({
    required String profileId,
    required String targetHash,
    required Iterable<String> incidentKeys,
  }) async {
    final profile = profileId.trim();
    if (profile.isEmpty ||
        profile.length > 256 ||
        !_targetHashPattern.hasMatch(targetHash)) {
      return null;
    }
    final candidates = <String>[];
    for (final raw in incidentKeys) {
      if (candidates.length >= maxIncidentNavigationCandidates) break;
      final key = raw.trim();
      if (key.isEmpty ||
          key.length > 1200 ||
          key.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
        continue;
      }
      candidates.add(key);
    }
    if (candidates.isEmpty) return null;
    try {
      final matched = await _channel.invokeMethod<String>(
        'resolveIncidentTarget',
        <String, Object?>{
          'profileId': profile,
          'targetHash': targetHash,
          'incidentKeys': candidates,
        },
      );
      return matched != null && candidates.contains(matched) ? matched : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
