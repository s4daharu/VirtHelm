import 'models.dart';

enum CockpitIncidentSeverity { critical, warning }

enum CockpitIncidentSource { node, task }

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

  String get severityLabel => switch (severity) {
    CockpitIncidentSeverity.critical => 'critical',
    CockpitIncidentSeverity.warning => 'warning',
  };

  String get sourceLabel => switch (source) {
    CockpitIncidentSource.node => 'Node inventory',
    CockpitIncidentSource.task => 'Task history',
  };
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
}) {
  final byKey = <String, CockpitIncident>{};

  for (final incident in retainedTaskIncidents) {
    if (incident.source == CockpitIncidentSource.task) {
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
