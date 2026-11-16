import 'package:flutter/services.dart';

const int maxIncidentNavigationCandidates = 128;
final RegExp _targetHashPattern = RegExp(r'^[0-9a-f]{64}$');
const Set<String> _scheduledIncidentSources = <String>{'node', 'task', 'rule'};

class IncidentNavigationCandidate {
  const IncidentNavigationCandidate({
    required this.key,
    required this.source,
    required this.identity,
  });

  final String key;
  final String source;
  final String identity;
}

bool _hasControlCharacters(String value) =>
    value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

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
    required Iterable<IncidentNavigationCandidate> candidates,
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
    required Iterable<IncidentNavigationCandidate> candidates,
  }) async {
    final profile = profileId.trim();
    if (profile.isEmpty ||
        profile.length > 256 ||
        !_targetHashPattern.hasMatch(targetHash)) {
      return null;
    }
    final payload = <Map<String, Object?>>[];
    for (final candidate in candidates) {
      if (payload.length >= maxIncidentNavigationCandidates) break;
      final key = candidate.key.trim();
      final source = candidate.source.trim();
      final identity = candidate.identity.trim();
      if (key.isEmpty ||
          key.length > 1200 ||
          _hasControlCharacters(key) ||
          !_scheduledIncidentSources.contains(source) ||
          identity.isEmpty ||
          identity.length > 1024 ||
          _hasControlCharacters(identity)) {
        continue;
      }
      payload.add(<String, Object?>{
        'key': key,
        'source': source,
        'identity': identity,
      });
    }
    if (payload.isEmpty) return null;
    try {
      final matched = await _channel.invokeMethod<String>(
        'resolveIncidentTarget',
        <String, Object?>{
          'profileId': profile,
          'targetHash': targetHash,
          'candidates': payload,
        },
      );
      return matched != null &&
              payload.any((candidate) => candidate['key'] == matched)
          ? matched
          : null;
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
