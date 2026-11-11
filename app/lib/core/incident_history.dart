import 'incident_center.dart';
import 'incident_triage.dart';

const int maxPersistedIncidentHistory = 80;

const int _maxOccurrenceIdLength = 96;
const int _maxFingerprintLength = 320;
const int _maxTitleLength = 180;
const int _maxDetailLength = 420;
const int _maxIdentityLength = 160;

/// A bounded, local-only incident occurrence summary.
///
/// Deliberately excludes task UPIDs and task-log content. Live health remains
/// authoritative; these records are historical operator context only.
class IncidentHistoryEntry {
  const IncidentHistoryEntry({
    required this.occurrenceId,
    required this.fingerprint,
    required this.severity,
    required this.source,
    required this.title,
    required this.detail,
    required this.firstSeen,
    required this.lastSeen,
    this.reviewedAt,
    this.noLongerObservedAt,
    this.node,
    this.taskTitle,
    this.guestKind,
    this.guestVmid,
    this.storageId,
    this.ruleId,
  });

  final String occurrenceId;
  final String fingerprint;
  final CockpitIncidentSeverity severity;
  final CockpitIncidentSource source;
  final String title;
  final String detail;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final DateTime? reviewedAt;
  final DateTime? noLongerObservedAt;
  final String? node;
  final String? taskTitle;
  final String? guestKind;
  final int? guestVmid;
  final String? storageId;
  final String? ruleId;

  bool get isOpen => noLongerObservedAt == null;
  bool get wasReviewed => reviewedAt != null;

  CockpitIncident get incident => CockpitIncident(
    key: 'history:${occurrenceId}',
    severity: severity,
    source: source,
    title: title,
    detail: detail,
    observedAt: lastSeen,
    node: node,
    taskTitle: taskTitle,
    guestKind: guestKind,
    guestVmid: guestVmid,
    storageId: storageId,
    ruleId: ruleId,
  );

  String get lifecycleLabel => isOpen
      ? 'Last saved while still observed. Use the live views to verify current state.'
      : source == CockpitIncidentSource.task
      ? 'Left the bounded task view after a complete foreground refresh; task outcome was not changed.'
      : 'No longer observed after a complete foreground refresh; recovery was not verified.';

  Map<String, dynamic> toJson() => {
    'occurrence_id': occurrenceId,
    'fingerprint': fingerprint,
    'severity': severity.name,
    'source': source.name,
    'title': title,
    'detail': detail,
    'first_seen': firstSeen.toUtc().toIso8601String(),
    'last_seen': lastSeen.toUtc().toIso8601String(),
    if (reviewedAt != null)
      'reviewed_at': reviewedAt!.toUtc().toIso8601String(),
    if (noLongerObservedAt != null)
      'no_longer_observed_at': noLongerObservedAt!.toUtc().toIso8601String(),
    if (node != null) 'node': node,
    if (taskTitle != null) 'task_title': taskTitle,
    if (guestKind != null) 'guest_kind': guestKind,
    if (guestVmid != null) 'guest_vmid': guestVmid,
    if (storageId != null) 'storage_id': storageId,
    if (ruleId != null) 'rule_id': ruleId,
  };

  factory IncidentHistoryEntry.fromJson(Map<String, dynamic> json) {
    final occurrenceId = _requiredText(
      json['occurrence_id'],
      _maxOccurrenceIdLength,
      'occurrence_id',
    );
    final fingerprint = _requiredText(
      json['fingerprint'],
      _maxFingerprintLength,
      'fingerprint',
    );
    final severity = _severity(json['severity']);
    final source = _source(json['source']);
    final title = _requiredText(json['title'], _maxTitleLength, 'title');
    final detail = _requiredText(json['detail'], _maxDetailLength, 'detail');
    final firstSeen = _requiredDate(json['first_seen'], 'first_seen');
    final lastSeen = _requiredDate(json['last_seen'], 'last_seen');
    if (lastSeen.isBefore(firstSeen)) {
      throw const FormatException('Incident history timestamps are invalid.');
    }
    final reviewedAt = _optionalDate(json['reviewed_at'], 'reviewed_at');
    final departed = _optionalDate(
      json['no_longer_observed_at'],
      'no_longer_observed_at',
    );
    if (departed != null && departed.isBefore(firstSeen)) {
      throw const FormatException('Incident history departure is invalid.');
    }
    final guestVmid = json['guest_vmid'];
    if (guestVmid != null && (guestVmid is! int || guestVmid <= 0)) {
      throw const FormatException('Incident history VMID is invalid.');
    }
    return IncidentHistoryEntry(
      occurrenceId: occurrenceId,
      fingerprint: fingerprint,
      severity: severity,
      source: source,
      title: title,
      detail: detail,
      firstSeen: firstSeen,
      lastSeen: lastSeen,
      reviewedAt: reviewedAt,
      noLongerObservedAt: departed,
      node: _optionalText(json['node'], _maxIdentityLength, 'node'),
      taskTitle: _optionalText(
        json['task_title'],
        _maxTitleLength,
        'task_title',
      ),
      guestKind: _optionalText(json['guest_kind'], 24, 'guest_kind'),
      guestVmid: guestVmid as int?,
      storageId: _optionalText(
        json['storage_id'],
        _maxIdentityLength,
        'storage_id',
      ),
      ruleId: _optionalText(json['rule_id'], _maxIdentityLength, 'rule_id'),
    );
  }

  IncidentHistoryEntry updatedFrom(IncidentTriageRecord record) {
    final incident = record.incident;
    return IncidentHistoryEntry(
      occurrenceId: occurrenceId,
      fingerprint: fingerprint,
      severity: incident.severity,
      source: incident.source,
      title: _historyText(incident, incident.title, _maxTitleLength),
      detail: _historyText(incident, incident.detail, _maxDetailLength),
      firstSeen: firstSeen,
      lastSeen: record.lastSeen.toUtc(),
      reviewedAt: record.acknowledgedAt?.toUtc() ?? reviewedAt,
      noLongerObservedAt: record.noLongerObservedAt?.toUtc(),
      node: _boundedOptional(incident.node, _maxIdentityLength),
      taskTitle: _historyOptionalText(
        incident,
        incident.taskTitle,
        _maxTitleLength,
      ),
      guestKind: _boundedOptional(incident.guestKind, 24),
      guestVmid: incident.guestVmid,
      storageId: _boundedOptional(incident.storageId, _maxIdentityLength),
      ruleId: _boundedOptional(incident.ruleId, _maxIdentityLength),
    );
  }

  IncidentHistoryEntry markNoLongerObserved(DateTime time) =>
      IncidentHistoryEntry(
        occurrenceId: occurrenceId,
        fingerprint: fingerprint,
        severity: severity,
        source: source,
        title: title,
        detail: detail,
        firstSeen: firstSeen,
        lastSeen: lastSeen,
        reviewedAt: reviewedAt,
        noLongerObservedAt: time.toUtc(),
        node: node,
        taskTitle: taskTitle,
        guestKind: guestKind,
        guestVmid: guestVmid,
        storageId: storageId,
        ruleId: ruleId,
      );

  static IncidentHistoryEntry fromRecord(
    IncidentTriageRecord record,
    String occurrenceId,
  ) {
    final incident = record.incident;
    return IncidentHistoryEntry(
      occurrenceId: occurrenceId,
      fingerprint: incidentHistoryFingerprint(incident),
      severity: incident.severity,
      source: incident.source,
      title: _historyText(incident, incident.title, _maxTitleLength),
      detail: _historyText(incident, incident.detail, _maxDetailLength),
      firstSeen: record.firstSeen.toUtc(),
      lastSeen: record.lastSeen.toUtc(),
      reviewedAt: record.acknowledgedAt?.toUtc(),
      noLongerObservedAt: record.noLongerObservedAt?.toUtc(),
      node: _boundedOptional(incident.node, _maxIdentityLength),
      taskTitle: _historyOptionalText(
        incident,
        incident.taskTitle,
        _maxTitleLength,
      ),
      guestKind: _boundedOptional(incident.guestKind, 24),
      guestVmid: incident.guestVmid,
      storageId: _boundedOptional(incident.storageId, _maxIdentityLength),
      ruleId: _boundedOptional(incident.ruleId, _maxIdentityLength),
    );
  }
}

/// Stable enough for local reconciliation without persisting a task UPID.
String incidentHistoryFingerprint(CockpitIncident incident) {
  final safeTitle = _historyText(incident, incident.title, _maxTitleLength);
  final safeTaskTitle =
      _historyOptionalText(incident, incident.taskTitle, _maxTitleLength) ??
      safeTitle;
  final value = switch (incident.source) {
    CockpitIncidentSource.node => 'node|${incident.node ?? safeTitle}',
    CockpitIncidentSource.task =>
      'task|${incident.node ?? ''}|$safeTaskTitle|'
          '${incident.observedAt.toUtc().millisecondsSinceEpoch}',
    CockpitIncidentSource.rule =>
      'rule|${incident.ruleId ?? ''}|${incident.node ?? ''}|'
          '${incident.guestKind ?? ''}|${incident.guestVmid ?? ''}|'
          '${incident.storageId ?? ''}|$safeTitle',
  };
  return _bounded(value, _maxFingerprintLength);
}

String _historyText(
  CockpitIncident incident,
  String value,
  int maxLength,
) {
  final taskUpid = incident.taskUpid;
  final redacted = taskUpid == null || taskUpid.isEmpty
      ? value
      : value.replaceAll(taskUpid, '[task id omitted]');
  return _bounded(redacted, maxLength);
}

String? _historyOptionalText(
  CockpitIncident incident,
  String? value,
  int maxLength,
) {
  if (value == null) return null;
  final redacted = _historyText(incident, value, maxLength);
  return redacted.isEmpty ? null : redacted;
}

/// Merge one connection session into the bounded durable history.
///
/// A complete authenticated foreground refresh is the only event allowed to
/// close an occurrence that is no longer observed. Reappearance after closure
/// creates a new occurrence ID.
List<IncidentHistoryEntry> reconcileIncidentHistory(
  Iterable<IncidentHistoryEntry> previous,
  Iterable<IncidentTriageRecord> sessionRecords, {
  required bool complete,
  DateTime? now,
}) {
  final time = (now ?? DateTime.now()).toUtc();
  final result = previous
      .map((entry) => IncidentHistoryEntry.fromJson(entry.toJson()))
      .toList();
  final records = sessionRecords.toList(growable: false);
  final currentFingerprints = <String>{};

  for (final record in records) {
    final fingerprint = incidentHistoryFingerprint(record.incident);
    if (record.isCurrent) currentFingerprints.add(fingerprint);
    var match = -1;
    for (var i = result.length - 1; i >= 0; i--) {
      if (result[i].fingerprint == fingerprint && result[i].isOpen) {
        match = i;
        break;
      }
    }
    if (match >= 0) {
      result[match] = result[match].updatedFrom(record);
      continue;
    }
    final occurrenceId = _newOccurrenceId(
      record.firstSeen.toUtc(),
      record.incident.source,
      result,
    );
    result.add(IncidentHistoryEntry.fromRecord(record, occurrenceId));
  }

  if (complete) {
    for (var i = 0; i < result.length; i++) {
      final entry = result[i];
      if (entry.isOpen && !currentFingerprints.contains(entry.fingerprint)) {
        result[i] = entry.markNoLongerObserved(time);
      }
    }
  }

  result.sort((a, b) {
    final seen = b.lastSeen.compareTo(a.lastSeen);
    if (seen != 0) return seen;
    return b.firstSeen.compareTo(a.firstSeen);
  });
  return List<IncidentHistoryEntry>.unmodifiable(
    result.take(maxPersistedIncidentHistory),
  );
}

String _newOccurrenceId(
  DateTime firstSeen,
  CockpitIncidentSource source,
  List<IncidentHistoryEntry> existing,
) {
  final base = 'occ-${firstSeen.microsecondsSinceEpoch}-${source.name}';
  var candidate = base;
  var suffix = 1;
  final ids = existing.map((entry) => entry.occurrenceId).toSet();
  while (ids.contains(candidate)) {
    candidate = '$base-$suffix';
    suffix++;
  }
  return candidate;
}

CockpitIncidentSeverity _severity(Object? value) {
  if (value is String) {
    for (final item in CockpitIncidentSeverity.values) {
      if (item.name == value) return item;
    }
  }
  throw const FormatException('Incident history severity is invalid.');
}

CockpitIncidentSource _source(Object? value) {
  if (value is String) {
    for (final item in CockpitIncidentSource.values) {
      if (item.name == value) return item;
    }
  }
  throw const FormatException('Incident history source is invalid.');
}

DateTime _requiredDate(Object? value, String field) {
  if (value is! String) {
    throw FormatException('Incident history $field is invalid.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Incident history $field is invalid.');
  }
  return parsed.toUtc();
}

DateTime? _optionalDate(Object? value, String field) {
  if (value == null) return null;
  return _requiredDate(value, field);
}

String _requiredText(Object? value, int maxLength, String field) {
  if (value is! String) {
    throw FormatException('Incident history $field is invalid.');
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > maxLength) {
    throw FormatException('Incident history $field is invalid.');
  }
  return trimmed;
}

String? _optionalText(Object? value, int maxLength, String field) {
  if (value == null) return null;
  return _requiredText(value, maxLength, field);
}

String _bounded(String value, int maxLength) {
  final trimmed = value.trim();
  if (trimmed.length <= maxLength) return trimmed;
  return trimmed.substring(0, maxLength);
}

String? _boundedOptional(String? value, int maxLength) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return _bounded(trimmed, maxLength);
}
