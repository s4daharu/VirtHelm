import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/incident_center.dart';
import 'package:virthelm/core/incident_triage.dart';

CockpitIncident signal(
  String key, {
  CockpitIncidentSource source = CockpitIncidentSource.node,
}) => CockpitIncident(
  key: key,
  severity: CockpitIncidentSeverity.critical,
  source: source,
  title: 'Attention',
  detail: 'Check source data',
  observedAt: DateTime.utc(2026, 11, 11),
);

void main() {
  test('acknowledgment cannot change a signal or its server severity', () {
    final ledger = IncidentTriageLedger();
    final now = DateTime.utc(2026, 11, 11, 10);
    ledger.observe([signal('node:pve1')], now: now);
    expect(ledger.setAcknowledged('node:pve1', true, now: now), isTrue);
    expect(ledger.current.single.isAcknowledged, isTrue);
    expect(
      ledger.current.single.incident.severity,
      CockpitIncidentSeverity.critical,
    );
    expect(ledger.setAcknowledged('node:pve1', true), isFalse);
    ledger.observe([
      signal('node:pve1'),
    ], now: now.add(const Duration(minutes: 1)));
    expect(ledger.current.single.isAcknowledged, isTrue);
    expect(ledger.setAcknowledged('node:pve1', false), isTrue);
    expect(ledger.current.single.isAcknowledged, isFalse);
  });

  test('partial evidence never marks missing signals as departed', () {
    final ledger = IncidentTriageLedger();
    ledger.observe([signal('node:pve1')]);
    ledger.observe([], complete: false);
    expect(ledger.current, hasLength(1));
    expect(ledger.earlier, isEmpty);
    ledger.observe([], complete: true);
    expect(ledger.current, isEmpty);
    expect(ledger.earlier, hasLength(1));
    expect(ledger.earlier.single.departureLabel, contains('not'));
  });

  test('reappearance creates a new unacknowledged occurrence', () {
    final ledger = IncidentTriageLedger();
    final t0 = DateTime.utc(2026, 11, 11, 10);
    ledger.observe([signal('rule:cpu')], now: t0);
    ledger.setAcknowledged('rule:cpu', true, now: t0);
    ledger.observe([], complete: true, now: t0.add(const Duration(minutes: 1)));
    ledger.observe([
      signal('rule:cpu'),
    ], now: t0.add(const Duration(minutes: 2)));
    expect(ledger.current.single.isAcknowledged, isFalse);
    expect(ledger.current.single.firstSeen, t0.add(const Duration(minutes: 2)));
    expect(ledger.earlier, isEmpty);
  });

  test('task departures are not described as successfully recovered', () {
    final ledger = IncidentTriageLedger();
    ledger.observe([signal('task:1', source: CockpitIncidentSource.task)]);
    ledger.observe([], complete: true);
    expect(
      ledger.earlier.single.departureLabel,
      contains('outcome is not changed'),
    );
  });

  test(
    'earlier signal history is bounded, immutable, and cleared on reconnect',
    () {
      final ledger = IncidentTriageLedger();
      final t0 = DateTime.utc(2026, 11, 11);
      for (var i = 0; i < 60; i++) {
        ledger.observe(
          [signal('node:$i')],
          complete: true,
          now: t0.add(Duration(minutes: i)),
        );
      }
      ledger.observe([], complete: true, now: t0.add(const Duration(hours: 2)));
      expect(ledger.earlier, hasLength(IncidentTriageLedger.maxEarlierSignals));
      expect(() => ledger.earlier.clear(), throwsUnsupportedError);
      ledger.clear();
      expect(ledger.current, isEmpty);
      expect(ledger.earlier, isEmpty);
    },
  );

  test('cannot acknowledge an absent or departed signal', () {
    final ledger = IncidentTriageLedger();
    expect(ledger.setAcknowledged('unknown', true), isFalse);
    ledger.observe([signal('node:pve1')]);
    ledger.observe([], complete: true);
    expect(ledger.setAcknowledged('node:pve1', true), isFalse);
  });
  test('bulk acknowledgement changes only active selected unique signals', () {
    final ledger = IncidentTriageLedger();
    final now = DateTime.utc(2026, 11, 11, 12);
    ledger.observe([
      signal('node:one'),
      signal('node:two'),
      signal('task:old', source: CockpitIncidentSource.task),
    ], now: now);
    ledger.observe([
      signal('node:one'),
      signal('node:two'),
    ], complete: true, now: now.add(const Duration(minutes: 1)));
    expect(
      ledger.acknowledgeCurrentKeys(
        ['node:one', 'node:one', 'task:old', 'missing'],
        now: now,
      ),
      1,
    );
    expect(
      ledger.current
          .singleWhere((record) => record.incident.key == 'node:one')
          .isAcknowledged,
      isTrue,
    );
    expect(
      ledger.current
          .singleWhere((record) => record.incident.key == 'node:two')
          .isAcknowledged,
      isFalse,
    );
    expect(ledger.earlier.single.isAcknowledged, isFalse);
    expect(ledger.acknowledgeCurrentKeys(['node:one']), 0);
  });

}
