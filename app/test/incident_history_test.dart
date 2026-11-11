import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/incident_center.dart';
import 'package:virthelm/core/incident_history.dart';
import 'package:virthelm/core/incident_triage.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';

class _EmptyVault implements CredentialVault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {}

  @override
  Future<ApiCredentials?> retrieve(String id) async => null;

  @override
  Future<void> remove(String id) async {}
}

IncidentTriageRecord _record(
  CockpitIncident incident,
  DateTime firstSeen, {
  DateTime? reviewedAt,
  DateTime? departedAt,
}) => IncidentTriageRecord(
  incident: incident,
  firstSeen: firstSeen,
  lastSeen: departedAt ?? firstSeen,
  acknowledgedAt: reviewedAt,
  noLongerObservedAt: departedAt,
);

CockpitIncident _nodeIncident(String node, DateTime observedAt) =>
    CockpitIncident(
      key: 'node:$node',
      severity: CockpitIncidentSeverity.critical,
      source: CockpitIncidentSource.node,
      title: 'Node $node is offline',
      detail: 'The current inventory reports this node as offline.',
      observedAt: observedAt,
      node: node,
    );

void main() {
  test('durable task history excludes task UPIDs', () {
    final now = DateTime.utc(2026, 11, 12, 1);
    final incident = CockpitIncident(
      key: 'task:UPID:pve1:secret-task-id',
      severity: CockpitIncidentSeverity.critical,
      source: CockpitIncidentSource.task,
      title: 'Task failed: Backup VM 101',
      detail: 'pve1 • Exit ERROR',
      observedAt: now,
      node: 'pve1',
      taskUpid: 'UPID:pve1:secret-task-id',
      taskTitle: 'Backup VM 101',
      guestKind: 'qemu',
      guestVmid: 101,
    );

    final history = reconcileIncidentHistory(
      const <IncidentHistoryEntry>[],
      [_record(incident, now, reviewedAt: now)],
      complete: false,
      now: now,
    );

    expect(history, hasLength(1));
    final encoded = jsonEncode(history.single.toJson());
    expect(encoded, isNot(contains('UPID:')));
    expect(encoded, isNot(contains('secret-task-id')));
    expect(history.single.taskTitle, 'Backup VM 101');
    expect(history.single.wasReviewed, isTrue);
  });

  test('partial evidence cannot close history and reappearance is new', () {
    final t0 = DateTime.utc(2026, 11, 12, 1);
    var history = reconcileIncidentHistory(
      const <IncidentHistoryEntry>[],
      [_record(_nodeIncident('pve1', t0), t0)],
      complete: false,
      now: t0,
    );
    final firstId = history.single.occurrenceId;

    history = reconcileIncidentHistory(
      history,
      const <IncidentTriageRecord>[],
      complete: false,
      now: t0.add(const Duration(minutes: 1)),
    );
    expect(history.single.isOpen, isTrue);

    history = reconcileIncidentHistory(
      history,
      const <IncidentTriageRecord>[],
      complete: true,
      now: t0.add(const Duration(minutes: 2)),
    );
    expect(history.single.isOpen, isFalse);
    expect(
      history.single.lifecycleLabel,
      contains('recovery was not verified'),
    );

    final t1 = t0.add(const Duration(minutes: 3));
    history = reconcileIncidentHistory(
      history,
      [_record(_nodeIncident('pve1', t1), t1)],
      complete: true,
      now: t1,
    );
    expect(history, hasLength(2));
    expect(history.first.isOpen, isTrue);
    expect(history.first.occurrenceId, isNot(firstId));
  });

  test('durable history remains bounded newest first', () {
    final t0 = DateTime.utc(2026, 11, 12);
    final records = <IncidentTriageRecord>[
      for (var i = 0; i < maxPersistedIncidentHistory + 20; i++)
        _record(
          _nodeIncident('pve$i', t0.add(Duration(minutes: i))),
          t0.add(Duration(minutes: i)),
        ),
    ];

    final history = reconcileIncidentHistory(
      const <IncidentHistoryEntry>[],
      records,
      complete: false,
      now: t0.add(const Duration(hours: 3)),
    );

    expect(history, hasLength(maxPersistedIncidentHistory));
    expect(history.first.node, 'pve99');
    expect(history.last.node, 'pve20');
  });

  test(
    'repository isolates history by profile and purges it on deletion',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = ProfileRepository(prefs, _EmptyVault());
      const credentials = ApiCredentials(
        tokenId: 'root@pam!mobile',
        secret: 'secret',
      );
      const one = ConnectionProfile(
        id: 'one',
        name: 'One',
        endpoint: 'https://one.invalid',
      );
      const two = ConnectionProfile(
        id: 'two',
        name: 'Two',
        endpoint: 'https://two.invalid',
      );
      await repository.save(one, credentials);
      await repository.save(two, credentials);

      final now = DateTime.utc(2026, 11, 12, 2);
      final history = reconcileIncidentHistory(
        const <IncidentHistoryEntry>[],
        [_record(_nodeIncident('pve1', now), now)],
        complete: false,
        now: now,
      );
      await repository.saveIncidentHistory(one.id, history);

      expect(repository.readIncidentHistory(one.id), hasLength(1));
      expect(repository.readIncidentHistory(two.id), isEmpty);

      await repository.delete(one.id);
      expect(repository.readIncidentHistory(one.id), isEmpty);
      expect(repository.readIncidentHistory(two.id), isEmpty);
    },
  );
}
