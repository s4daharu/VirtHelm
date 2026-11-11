import 'incident_center.dart';

/// Session-only operator annotations. These are not server health or task state.
class IncidentTriageRecord {
  const IncidentTriageRecord({
    required this.incident,
    required this.firstSeen,
    required this.lastSeen,
    this.acknowledgedAt,
    this.noLongerObservedAt,
  });

  final CockpitIncident incident;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final DateTime? acknowledgedAt;
  final DateTime? noLongerObservedAt;

  bool get isAcknowledged => acknowledgedAt != null;
  bool get isCurrent => noLongerObservedAt == null;

  String get departureLabel => incident.source == CockpitIncidentSource.task
      ? 'Left the bounded task view; the outcome is not changed.'
      : 'Signal not observed in a complete refresh; recovery not verified.';
}

/// Keeps acknowledgements and a bounded history in RAM for one connection
/// generation. Missing or partial reads may never clear an observation.
class IncidentTriageLedger {
  static const int maxEarlierSignals = 40;
  final Map<String, IncidentTriageRecord> _records = {};

  List<IncidentTriageRecord> get current {
    final results = _records.values.where((record) => record.isCurrent).toList()
      ..sort((a, b) {
        final severity = a.incident.severity.index.compareTo(
          b.incident.severity.index,
        );
        if (severity != 0) return severity;
        return b.lastSeen.compareTo(a.lastSeen);
      });
    return List<IncidentTriageRecord>.unmodifiable(results);
  }

  List<IncidentTriageRecord> get earlier {
    final results =
        _records.values.where((record) => !record.isCurrent).toList()..sort(
          (a, b) => b.noLongerObservedAt!.compareTo(a.noLongerObservedAt!),
        );
    return List<IncidentTriageRecord>.unmodifiable(results);
  }

  void clear() => _records.clear();

  void observe(
    Iterable<CockpitIncident> incidents, {
    bool complete = false,
    DateTime? now,
  }) {
    final time = (now ?? DateTime.now()).toUtc();
    final seen = <String>{};
    for (final incident in incidents) {
      if (incident.key.isEmpty || !seen.add(incident.key)) continue;
      final previous = _records[incident.key];
      if (previous == null || !previous.isCurrent) {
        _records[incident.key] = IncidentTriageRecord(
          incident: incident,
          firstSeen: time,
          lastSeen: time,
        );
      } else {
        _records[incident.key] = IncidentTriageRecord(
          incident: incident,
          firstSeen: previous.firstSeen,
          lastSeen: time,
          acknowledgedAt: previous.acknowledgedAt,
        );
      }
    }

    if (complete) {
      for (final key in _records.keys.toList(growable: false)) {
        final previous = _records[key]!;
        if (seen.contains(key) || !previous.isCurrent) continue;
        _records[key] = IncidentTriageRecord(
          incident: previous.incident,
          firstSeen: previous.firstSeen,
          lastSeen: previous.lastSeen,
          acknowledgedAt: previous.acknowledgedAt,
          noLongerObservedAt: time,
        );
      }
    }

    // Keep current signals, but bound older observations to avoid unbounded
    // RAM growth and accidental retention of stale task identifiers.
    final old = earlier;
    for (final record in old.skip(maxEarlierSignals)) {
      _records.remove(record.incident.key);
    }
  }

  /// Review only the explicitly selected, still-current session observations.
  int acknowledgeCurrentKeys(Iterable<String> keys, {DateTime? now}) {
    var changed = 0;
    for (final key in keys.toSet()) {
      if (setAcknowledged(key, true, now: now)) changed++;
    }
    return changed;
  }

  bool setAcknowledged(String key, bool value, {DateTime? now}) {
    final previous = _records[key];
    if (previous == null || !previous.isCurrent) return false;
    if (previous.isAcknowledged == value) return false;
    _records[key] = IncidentTriageRecord(
      incident: previous.incident,
      firstSeen: previous.firstSeen,
      lastSeen: previous.lastSeen,
      acknowledgedAt: value ? (now ?? DateTime.now()).toUtc() : null,
    );
    return true;
  }
}
