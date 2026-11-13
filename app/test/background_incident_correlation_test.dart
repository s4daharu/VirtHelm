import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/background_checks.dart';
import 'package:virthelm/core/incident_center.dart';
import 'package:virthelm/core/incident_history.dart';
import 'package:virthelm/core/incident_triage.dart';

CockpitIncident _node(String name, DateTime observedAt) => CockpitIncident(
  key: 'node:$name',
  severity: CockpitIncidentSeverity.critical,
  source: CockpitIncidentSource.node,
  title: 'Node $name is offline',
  detail: 'Offline',
  observedAt: observedAt,
  node: name,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.s4daharu.virthelm/background_checks');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android correlation sends exact live identities only in memory', () async {
    MethodCall? observed;
    final scheduledAt = DateTime.utc(2026, 11, 14, 8, 30);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          observed = call;
          return <String, Object?>{
            'node:pve-a': scheduledAt.millisecondsSinceEpoch,
            'not-requested': scheduledAt.millisecondsSinceEpoch,
          };
        });

    final matches = await const AndroidBackgroundCheckScheduler()
        .correlateIncidents('profile-alpha', <CockpitIncident>[
          _node('pve-a', DateTime.utc(2026, 11, 14, 9)),
          CockpitIncident(
            key: 'task:upid-current',
            severity: CockpitIncidentSeverity.critical,
            source: CockpitIncidentSource.task,
            title: 'Task failed',
            detail: 'Failure',
            observedAt: DateTime.utc(2026, 11, 14, 9),
            taskUpid: 'UPID:pve-a:0001',
            taskTitle: 'Start VM',
          ),
          CockpitIncident(
            key: 'rule:rule-1',
            severity: CockpitIncidentSeverity.warning,
            source: CockpitIncidentSource.rule,
            title: 'CPU threshold',
            detail: 'Active',
            observedAt: DateTime.utc(2026, 11, 14, 9),
            ruleId: 'rule-1',
          ),
          CockpitIncident(
            key: 'task:unidentified',
            severity: CockpitIncidentSeverity.warning,
            source: CockpitIncidentSource.task,
            title: 'Unknown task',
            detail: 'No exact task identity',
            observedAt: DateTime.utc(2026, 11, 14, 9),
          ),
        ]);

    expect(observed?.method, 'correlateIncidents');
    final args = Map<String, Object?>.from(observed?.arguments as Map);
    expect(args['profileId'], 'profile-alpha');
    final candidates = List<Object?>.from(args['incidents'] as List<Object?>);
    expect(candidates, hasLength(3));
    expect(
      candidates
          .map((value) => Map<Object?, Object?>.from(value as Map))
          .toList(growable: false),
      <Map<Object?, Object?>>[
        <Object?, Object?>{
          'key': 'node:pve-a',
          'source': 'node',
          'identity': 'pve-a',
        },
        <Object?, Object?>{
          'key': 'task:upid-current',
          'source': 'task',
          'identity': 'UPID:pve-a:0001',
        },
        <Object?, Object?>{
          'key': 'rule:rule-1',
          'source': 'rule',
          'identity': 'rule-1',
        },
      ],
    );
    expect(matches, <String, DateTime>{'node:pve-a': scheduledAt});
  });

  test('correlation bridge bounds candidates before native handoff', () async {
    MethodCall? observed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          observed = call;
          return <String, Object?>{};
        });

    await const AndroidBackgroundCheckScheduler().correlateIncidents(
      'profile-alpha',
      List<CockpitIncident>.generate(
        maxScheduledIncidentCorrelationCandidates + 20,
        (index) => _node('pve-$index', DateTime.utc(2026, 11, 14, 9)),
      ),
    );

    final args = Map<String, Object?>.from(observed?.arguments as Map);
    expect(
      List<Object?>.from(args['incidents'] as List<Object?>),
      hasLength(maxScheduledIncidentCorrelationCandidates),
    );
  });

  test(
    'durable history records scheduled evidence without storing task UPIDs',
    () {
      final foregroundAt = DateTime.utc(2026, 11, 14, 10);
      final scheduledAt = DateTime.utc(2026, 11, 14, 9, 45);
      const upid = 'UPID:pve-a:00000001:secret-task-identity';
      final incident = CockpitIncident(
        key: 'task:$upid',
        severity: CockpitIncidentSeverity.critical,
        source: CockpitIncidentSource.task,
        title: 'Task failed: Start VM',
        detail: 'pve-a • Exit failure',
        observedAt: foregroundAt,
        node: 'pve-a',
        taskUpid: upid,
        taskTitle: 'Start VM',
      );
      final record = IncidentTriageRecord(
        incident: incident,
        firstSeen: foregroundAt,
        lastSeen: foregroundAt,
      );

      final first = reconcileIncidentHistory(
        const <IncidentHistoryEntry>[],
        <IncidentTriageRecord>[record],
        complete: false,
        scheduledObservations: <String, DateTime>{
          incident.key: scheduledAt,
        },
      );
      expect(first.single.scheduledObservedAt, scheduledAt);
      expect(jsonEncode(first.single.toJson()), isNot(contains(upid)));

      final roundTrip = IncidentHistoryEntry.fromJson(first.single.toJson());
      expect(roundTrip.scheduledObservedAt, scheduledAt);

      final laterForeground = DateTime.utc(2026, 11, 14, 10, 30);
      final laterRecord = IncidentTriageRecord(
        incident: incident,
        firstSeen: foregroundAt,
        lastSeen: laterForeground,
      );
      final preserved = reconcileIncidentHistory(
        first,
        <IncidentTriageRecord>[laterRecord],
        complete: false,
      );
      expect(preserved.single.scheduledObservedAt, scheduledAt);

      final newerScheduled = DateTime.utc(2026, 11, 14, 10, 20);
      final refreshed = reconcileIncidentHistory(
        preserved,
        <IncidentTriageRecord>[laterRecord],
        complete: false,
        scheduledObservations: <String, DateTime>{
          incident.key: newerScheduled,
        },
      );
      expect(refreshed.single.scheduledObservedAt, newerScheduled);

      final closed = reconcileIncidentHistory(
        refreshed,
        const <IncidentTriageRecord>[],
        complete: true,
        now: DateTime.utc(2026, 11, 14, 11),
      );
      expect(closed.single.isOpen, isFalse);
      expect(closed.single.scheduledObservedAt, newerScheduled);
    },
  );
}
