import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/incident_center.dart';
import 'package:virthelm/core/models.dart';

void main() {
  test('incident builder is conservative and does not treat unknown as healthy', () {
    final observedAt = DateTime.utc(2026, 11, 6, 9);
    final inventory = Inventory.fromResources(
      [
        {'type': 'node', 'node': 'pve1', 'status': 'offline'},
        {'type': 'node', 'node': 'pve2', 'status': 'unknown'},
        {'type': 'node', 'node': 'pve3', 'status': 'online'},
      ],
      fetchedAt: observedAt,
    );
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
  });
}
