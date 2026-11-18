import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/incident_center.dart';
import 'package:virthelm/core/models.dart';

void main() {
  test(
    'incident builder is conservative and does not treat unknown as healthy',
    () {
      final observedAt = DateTime.utc(2026, 11, 6, 9);
      final inventory = Inventory.fromResources([
        {'type': 'node', 'node': 'pve1', 'status': 'offline'},
        {'type': 'node', 'node': 'pve2', 'status': 'unknown'},
        {'type': 'node', 'node': 'pve3', 'status': 'online'},
      ], fetchedAt: observedAt);
      final incidents = buildCockpitIncidents(
        inventory: inventory,
        serverTasks: [
          RecentServerTask(
            upid: 'UPID:pve1:1:2:3:qmstart:101:user@pve:',
            node: 'pve1',
            operation: 'qmstart',
            resourceId: '101',
            status: 'stopped',
            exitStatus: 'ERROR',
            endedAt: observedAt.add(const Duration(minutes: 3)),
          ),
          const RecentServerTask(
            upid: 'UPID:pve1:1:2:3:qmstop:102:user@pve:',
            node: 'pve1',
            operation: 'qmstop',
            resourceId: '102',
            status: 'stopped',
            exitStatus: 'OK',
          ),
          const RecentServerTask(
            upid: 'UPID:pve1:1:2:3:qmstop:103:user@pve:',
            node: 'pve1',
            operation: 'qmstop',
            resourceId: '103',
            status: 'stopped',
          ),
        ],
        sessionTasks: [
          TrackedTask(
            upid: 'UPID:pve2:1:2:3:qmreboot:201:user@pve:',
            node: 'pve2',
            title: 'Reboot App (201)',
            startedAt: observedAt.add(const Duration(minutes: 2)),
            outcome: OperationOutcome.unknown,
          ),
        ],
      );

      expect(incidents, hasLength(4));
      expect(
        incidents.take(2).map((incident) => incident.severity),
        everyElement(CockpitIncidentSeverity.critical),
      );
      expect(
        incidents.map((incident) => incident.title),
        containsAll([
          'Node pve1 is offline',
          'Node pve2 state is unknown',
          'Task failed: Start VM • 101',
          'Task outcome unknown: Reboot App (201)',
        ]),
      );
      expect(
        incidents.map((incident) => incident.title),
        isNot(contains('Force stop VM • 102')),
      );
      expect(
        incidents.map((incident) => incident.title),
        isNot(contains('Force stop VM • 103')),
      );
      expect(
        incidents.every(
          (incident) =>
              !incident.detail.contains('UPID:') &&
              !incident.title.contains('user@pve'),
        ),
        isTrue,
      );
    },
  );

  test('same-node context correlates cross-source current signals only', () {
    final observedAt = DateTime.utc(2026, 11, 19, 1);
    final incidents = <CockpitIncident>[
      CockpitIncident(
        key: 'node:pve1',
        severity: CockpitIncidentSeverity.critical,
        source: CockpitIncidentSource.node,
        title: 'Node pve1 is offline',
        detail: 'offline',
        observedAt: observedAt,
        node: 'pve1',
      ),
      CockpitIncident(
        key: 'task:one',
        severity: CockpitIncidentSeverity.critical,
        source: CockpitIncidentSource.task,
        title: 'Task failed',
        detail: 'failed',
        observedAt: observedAt,
        node: 'pve1',
      ),
      CockpitIncident(
        key: 'rule:cpu',
        severity: CockpitIncidentSeverity.warning,
        source: CockpitIncidentSource.rule,
        title: 'CPU high',
        detail: 'threshold',
        observedAt: observedAt,
        node: 'pve1',
      ),
      CockpitIncident(
        key: 'task:two',
        severity: CockpitIncidentSeverity.critical,
        source: CockpitIncidentSource.task,
        title: 'Task failed 2',
        detail: 'failed',
        observedAt: observedAt,
        node: 'pve2',
      ),
      CockpitIncident(
        key: 'task:three',
        severity: CockpitIncidentSeverity.warning,
        source: CockpitIncidentSource.task,
        title: 'Task unknown 3',
        detail: 'unknown',
        observedAt: observedAt,
        node: 'pve2',
      ),
      CockpitIncident(
        key: 'task:no-node',
        severity: CockpitIncidentSeverity.warning,
        source: CockpitIncidentSource.task,
        title: 'Task without node',
        detail: 'unknown',
        observedAt: observedAt,
      ),
    ];
    final contexts = buildCurrentIncidentNodeContexts(incidents);
    expect(
      contexts.keys,
      unorderedEquals(<String>['node:pve1', 'task:one', 'rule:cpu']),
    );
    expect(contexts['node:pve1']!.relatedCount, 2);
    expect(contexts['node:pve1']!.relatedSources, <CockpitIncidentSource>[
      CockpitIncidentSource.task,
      CockpitIncidentSource.rule,
    ]);
    expect(
      contexts['task:one']!.sourceSummary,
      'Node inventory + Foreground rule',
    );
    expect(contexts.containsKey('task:two'), isFalse);
    expect(contexts.containsKey('task:no-node'), isFalse);
  });

  test('same-node context bounds candidate processing', () {
    final observedAt = DateTime.utc(2026, 11, 19, 2);
    final incidents = <CockpitIncident>[
      CockpitIncident(
        key: 'node:pve1',
        severity: CockpitIncidentSeverity.critical,
        source: CockpitIncidentSource.node,
        title: 'Node pve1 is offline',
        detail: 'offline',
        observedAt: observedAt,
        node: 'pve1',
      ),
      for (var i = 0; i < maxCurrentIncidentCorrelationCandidates + 10; i++)
        CockpitIncident(
          key: 'task:$i',
          severity: CockpitIncidentSeverity.critical,
          source: CockpitIncidentSource.task,
          title: 'Task failed $i',
          detail: 'failed',
          observedAt: observedAt,
          node: 'pve1',
        ),
    ];
    final contexts = buildCurrentIncidentNodeContexts(incidents);
    expect(contexts, hasLength(maxCurrentIncidentCorrelationCandidates));
    expect(contexts.containsKey('task:126'), isTrue);
    expect(contexts.containsKey('task:127'), isFalse);
  });
}
