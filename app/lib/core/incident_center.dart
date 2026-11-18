import 'alert_rules.dart';
import 'models.dart';

enum CockpitIncidentSeverity { critical, warning }

enum CockpitIncidentSource { node, task, rule }

String cockpitIncidentSourceLabel(CockpitIncidentSource source) =>
    switch (source) {
      CockpitIncidentSource.node => 'Node inventory',
      CockpitIncidentSource.task => 'Task history',
      CockpitIncidentSource.rule => 'Foreground rule',
    };

const int maxCurrentIncidentCorrelationCandidates = 128;

/// Bounded, current-session relationship context for incidents sharing one
/// exact node identity across different signal sources.
///
/// This is presentation context only. It does not establish causality, alter
/// health, persist a relationship graph or authorize resource access.
class IncidentNodeContext {
  const IncidentNodeContext({
    required this.node,
    required this.relatedCount,
    required this.relatedSources,
  });

  final String node;
  final int relatedCount;
  final List<CockpitIncidentSource> relatedSources;

  String get sourceSummary =>
      relatedSources.map(cockpitIncidentSourceLabel).join(' + ');
}

/// Correlates only the first bounded set of unique current incident keys.
///
/// A context is emitted only when one exact node currently has at least two
/// incidents spanning at least two source types. Same-source-only clusters are
/// deliberately omitted so this cannot imply richer correlation than exists.
Map<String, IncidentNodeContext> buildCurrentIncidentNodeContexts(
  Iterable<CockpitIncident> incidents,
) {
  final unique = <String, CockpitIncident>{};
  for (final incident in incidents) {
    if (unique.length >= maxCurrentIncidentCorrelationCandidates) break;
    if (incident.key.isEmpty || unique.containsKey(incident.key)) continue;
    unique[incident.key] = incident;
  }

  final byNode = <String, List<CockpitIncident>>{};
  for (final incident in unique.values) {
    final node = incident.node;
    if (node == null || node.isEmpty) continue;
    (byNode[node] ??= <CockpitIncident>[]).add(incident);
  }

  final contexts = <String, IncidentNodeContext>{};
  for (final entry in byNode.entries) {
    final group = entry.value;
    if (group.length < 2 ||
        group.map((item) => item.source).toSet().length < 2) {
      continue;
    }
    for (final incident in group) {
      final related = group
          .where((item) => item.key != incident.key)
          .toList(growable: false);
      final relatedSources = related.map((item) => item.source).toSet().toList()
        ..sort((left, right) => left.index.compareTo(right.index));
      if (!relatedSources.any((source) => source != incident.source)) continue;
      contexts[incident.key] = IncidentNodeContext(
        node: entry.key,
        relatedCount: related.length,
        relatedSources: List<CockpitIncidentSource>.unmodifiable(
          relatedSources,
        ),
      );
    }
  }
  return Map<String, IncidentNodeContext>.unmodifiable(contexts);
}

class CockpitIncident {
  const CockpitIncident({
    required this.key,
    required this.severity,
    required this.source,
    required this.title,
    required this.detail,
    required this.observedAt,
    this.node,
    this.taskUpid,
    this.taskTitle,
    this.guestKind,
    this.guestVmid,
    this.storageId,
    this.ruleId,
  });

  final String key;
  final CockpitIncidentSeverity severity;
  final CockpitIncidentSource source;
  final String title;
  final String detail;
  final DateTime observedAt;
  final String? node;
  final String? taskUpid;
  final String? taskTitle;
  final String? guestKind;
  final int? guestVmid;
  final String? storageId;
  final String? ruleId;

  String get severityLabel => switch (severity) {
    CockpitIncidentSeverity.critical => 'critical',
    CockpitIncidentSeverity.warning => 'warning',
  };

  String get sourceLabel => cockpitIncidentSourceLabel(source);
}

class ForegroundThresholdAlertEngine {
  final Map<String, CockpitIncident> _active = {};
  final Map<String, _PendingThresholdConfirmation> _pending = {};

  List<CockpitIncident> get incidents {
    final values = _active.values.toList(growable: false)
      ..sort((left, right) {
        final severity = left.severity.index.compareTo(right.severity.index);
        if (severity != 0) return severity;
        final time = right.observedAt.compareTo(left.observedAt);
        if (time != 0) return time;
        return left.key.compareTo(right.key);
      });
    return List<CockpitIncident>.unmodifiable(values);
  }

  void clear() {
    _active.clear();
    _pending.clear();
  }

  void reconcileRules(Iterable<ForegroundThresholdAlertRule> rules) {
    final enabledIds = <String>{
      for (final rule in rules)
        if (rule.enabled) rule.id,
    };
    _active.removeWhere((id, _) => !enabledIds.contains(id));
    _pending.removeWhere((id, _) => !enabledIds.contains(id));
  }

  void evaluate({
    required Inventory inventory,
    required Iterable<StoragePool> storages,
    required Iterable<ForegroundThresholdAlertRule> rules,
    required bool storageDataCurrent,
  }) {
    final enabled = <String, ForegroundThresholdAlertRule>{
      for (final rule in rules)
        if (rule.enabled) rule.id: rule,
    };
    reconcileRules(enabled.values);
    final storageList = storages.toList(growable: false);
    final observedAtMs = inventory.fetchedAt.millisecondsSinceEpoch;

    for (final rule in enabled.values) {
      final sample = _sample(
        rule,
        inventory,
        storageList,
        storageDataCurrent: storageDataCurrent,
      );
      if (sample == null) {
        _pending.remove(rule.id);
        final previous = _active[rule.id];
        if (previous != null) {
          _active[rule.id] = CockpitIncident(
            key: previous.key,
            severity: _severity(rule.severity),
            source: CockpitIncidentSource.rule,
            title: previous.title,
            detail:
                'Previous threshold breach remains unresolved because the '
                'current foreground snapshot has no usable '
                '${rule.metric.label.toLowerCase()} sample for this target.',
            observedAt: previous.observedAt,
            node: previous.node,
            guestKind: previous.guestKind,
            guestVmid: previous.guestVmid,
            storageId: previous.storageId,
            ruleId: rule.id,
          );
        }
        continue;
      }

      final previous = _active[rule.id];
      if (previous != null) {
        final shouldResolve = rule.hysteresisPercent == 0
            ? sample.fraction < rule.thresholdFraction
            : sample.fraction <= rule.clearThresholdFraction;
        if (shouldResolve) {
          _active.remove(rule.id);
          _pending.remove(rule.id);
          continue;
        }
        final clearDetail = rule.hysteresisPercent == 0
            ? 'It clears only below ${rule.thresholdPercent}%.'
            : 'It clears only at or below '
                  '${rule.thresholdPercent - rule.hysteresisPercent}% after '
                  '${rule.hysteresisPercent}% hysteresis.';
        _active[rule.id] = CockpitIncident(
          key: previous.key,
          severity: _severity(rule.severity),
          source: CockpitIncidentSource.rule,
          title: sample.title,
          detail: 'Foreground rule remains active. $clearDetail',
          observedAt: previous.observedAt,
          node: sample.node,
          guestKind: sample.guestKind,
          guestVmid: sample.guestVmid,
          storageId: sample.storageId,
          ruleId: rule.id,
        );
        continue;
      }

      if (sample.fraction < rule.thresholdFraction) {
        _pending.remove(rule.id);
        continue;
      }

      // Confirmation accumulates only from strictly newer foreground
      // snapshots. A repeated `fetchedAt` (the same read evaluated twice) must
      // not double-count a sample or stretch the wall-clock window.
      final pending = _pending[rule.id];
      final _PendingThresholdConfirmation confirmation;
      if (pending == null) {
        confirmation = _PendingThresholdConfirmation(
          samples: 1,
          sinceMs: observedAtMs,
          lastSampleMs: observedAtMs,
        );
        _pending[rule.id] = confirmation;
      } else if (observedAtMs > pending.lastSampleMs) {
        confirmation = _PendingThresholdConfirmation(
          samples: pending.samples + 1,
          sinceMs: pending.sinceMs,
          lastSampleMs: observedAtMs,
        );
        _pending[rule.id] = confirmation;
      } else {
        confirmation = pending;
      }

      if (confirmation.samples < rule.consecutiveSamples) continue;
      final elapsedMs = confirmation.lastSampleMs - confirmation.sinceMs;
      if (elapsedMs < rule.minimumDurationSeconds * 1000) continue;

      _pending.remove(rule.id);
      final clearDetail = rule.hysteresisPercent == 0
          ? 'It clears below ${rule.thresholdPercent}%.'
          : 'It clears at or below '
                '${rule.thresholdPercent - rule.hysteresisPercent}%.';
      final durationDetail = rule.minimumDurationSeconds == 0
          ? ''
          : ' over at least ${rule.minimumDurationSeconds} second(s)';
      _active[rule.id] = CockpitIncident(
        key: 'rule:${rule.id}',
        severity: _severity(rule.severity),
        source: CockpitIncidentSource.rule,
        title: sample.title,
        detail:
            'Foreground rule threshold ${rule.thresholdPercent}% was met for '
            '${rule.consecutiveSamples} consecutive usable sample(s)'
            '$durationDetail. $clearDetail',
        observedAt: inventory.fetchedAt,
        node: sample.node,
        guestKind: sample.guestKind,
        guestVmid: sample.guestVmid,
        storageId: sample.storageId,
        ruleId: rule.id,
      );
    }
  }

  CockpitIncidentSeverity _severity(ForegroundAlertSeverity severity) {
    return switch (severity) {
      ForegroundAlertSeverity.warning => CockpitIncidentSeverity.warning,
      ForegroundAlertSeverity.critical => CockpitIncidentSeverity.critical,
    };
  }

  _ThresholdSample? _sample(
    ForegroundThresholdAlertRule rule,
    Inventory inventory,
    List<StoragePool> storages, {
    required bool storageDataCurrent,
  }) {
    switch (rule.metric) {
      case ForegroundThresholdMetric.nodeCpu:
        final matches = inventory.nodes.where((node) => node.name == rule.node);
        if (matches.length != 1) return null;
        final cpu = matches.single.cpu;
        if (cpu == null || cpu < 0 || cpu > 1) return null;
        return _ThresholdSample(
          fraction: cpu,
          title:
              'Node ${matches.single.name} CPU is '
              '${(cpu * 100).toStringAsFixed(1)}%',
          node: matches.single.name,
        );
      case ForegroundThresholdMetric.guestCpu:
        final matches = inventory.guests.where(
          (guest) =>
              guest.node == rule.node &&
              guest.kind == rule.guestKind &&
              guest.vmid == rule.guestVmid,
        );
        if (matches.length != 1) return null;
        final guest = matches.single;
        final cpu = guest.cpu;
        if (cpu == null || cpu < 0 || cpu > 1) return null;
        return _ThresholdSample(
          fraction: cpu,
          title:
              '${guest.name} (${guest.vmid}) CPU is '
              '${(cpu * 100).toStringAsFixed(1)}%',
          node: guest.node,
          guestKind: guest.kind,
          guestVmid: guest.vmid,
        );
      case ForegroundThresholdMetric.storageUsage:
        if (!storageDataCurrent) return null;
        final matches = storages.where(
          (storage) =>
              storage.node == rule.node && storage.id == rule.storageId,
        );
        if (matches.length != 1) return null;
        final storage = matches.single;
        final usage = storage.usageFraction;
        if (usage == null || usage < 0 || usage > 1) return null;
        return _ThresholdSample(
          fraction: usage,
          title:
              '${storage.id} on ${storage.node} is '
              '${(usage * 100).toStringAsFixed(1)}% full',
          node: storage.node,
          storageId: storage.id,
        );
    }
  }
}

class _PendingThresholdConfirmation {
  const _PendingThresholdConfirmation({
    required this.samples,
    required this.sinceMs,
    required this.lastSampleMs,
  });

  final int samples;
  final int sinceMs;
  final int lastSampleMs;
}

class _ThresholdSample {
  const _ThresholdSample({
    required this.fraction,
    required this.title,
    this.node,
    this.guestKind,
    this.guestVmid,
    this.storageId,
  });

  final double fraction;
  final String title;
  final String? node;
  final String? guestKind;
  final int? guestVmid;
  final String? storageId;
}

List<CockpitIncident> failedServerTaskIncidents(
  Iterable<RecentServerTask> tasks,
) {
  final incidents = <CockpitIncident>[];
  for (final task in tasks) {
    if (task.stateLabel != 'failed') continue;
    final resource = task.resourceId == null || task.resourceId!.isEmpty
        ? ''
        : ' • ${task.resourceId}';
    incidents.add(
      CockpitIncident(
        key: 'task:${task.upid}',
        severity: CockpitIncidentSeverity.critical,
        source: CockpitIncidentSource.task,
        title: 'Task failed: ${task.operationLabel}$resource',
        detail: '${task.node} • Exit ${task.exitStatus ?? 'failure reported'}',
        observedAt:
            task.endedAt ??
            task.startedAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        node: task.node,
        taskUpid: task.upid,
        taskTitle: '${task.operationLabel}$resource',
      ),
    );
  }
  return List<CockpitIncident>.unmodifiable(incidents);
}

List<CockpitIncident> buildCockpitIncidents({
  required Inventory? inventory,
  required Iterable<RecentServerTask> serverTasks,
  required Iterable<TrackedTask> sessionTasks,
  Iterable<CockpitIncident> retainedTaskIncidents = const <CockpitIncident>[],
  Iterable<CockpitIncident> foregroundRuleIncidents = const <CockpitIncident>[],
}) {
  final byKey = <String, CockpitIncident>{};

  for (final incident in retainedTaskIncidents) {
    if (incident.source == CockpitIncidentSource.task) {
      byKey[incident.key] = incident;
    }
  }
  for (final incident in foregroundRuleIncidents) {
    if (incident.source == CockpitIncidentSource.rule) {
      byKey[incident.key] = incident;
    }
  }

  final snapshot = inventory;
  if (snapshot != null) {
    for (final node in snapshot.nodes) {
      final status = node.status.trim().toLowerCase();
      if (status == 'online') continue;
      final offline = status == 'offline';
      byKey['node:${node.name}'] = CockpitIncident(
        key: 'node:${node.name}',
        severity: offline
            ? CockpitIncidentSeverity.critical
            : CockpitIncidentSeverity.warning,
        source: CockpitIncidentSource.node,
        title: offline
            ? 'Node ${node.name} is offline'
            : 'Node ${node.name} state is unknown',
        detail: offline
            ? 'The current Proxmox inventory explicitly reports this node as offline.'
            : 'The current Proxmox inventory does not report this node as online or offline.',
        observedAt: snapshot.fetchedAt,
        node: node.name,
      );
    }
  }

  for (final incident in failedServerTaskIncidents(serverTasks)) {
    byKey[incident.key] = incident;
  }

  for (final task in sessionTasks) {
    if (task.outcome != OperationOutcome.failed &&
        task.outcome != OperationOutcome.unknown) {
      continue;
    }
    final failed = task.outcome == OperationOutcome.failed;
    byKey['task:${task.upid}'] = CockpitIncident(
      key: 'task:${task.upid}',
      severity: failed
          ? CockpitIncidentSeverity.critical
          : CockpitIncidentSeverity.warning,
      source: CockpitIncidentSource.task,
      title: failed
          ? 'Task failed: ${task.title}'
          : 'Task outcome unknown: ${task.title}',
      detail:
          task.detail ??
          (failed
              ? 'The tracked operation finished with a failure.'
              : 'Verify server task history and resource state before retrying.'),
      observedAt: task.startedAt,
      node: task.node,
      taskUpid: task.upid,
      taskTitle: task.title,
    );
  }

  final incidents = byKey.values.toList(growable: false)
    ..sort((left, right) {
      final severity = left.severity.index.compareTo(right.severity.index);
      if (severity != 0) return severity;
      final time = right.observedAt.compareTo(left.observedAt);
      if (time != 0) return time;
      return left.key.compareTo(right.key);
    });
  return List<CockpitIncident>.unmodifiable(incidents);
}
