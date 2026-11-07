import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/alert_rules.dart';
import 'package:virthelm/core/incident_center.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';

class _MemoryVault implements CredentialVault {
  final Map<String, ApiCredentials> values = {};

  @override
  Future<void> remove(String id) async {
    values.remove(id);
  }

  @override
  Future<ApiCredentials?> retrieve(String id) async => values[id];

  @override
  Future<void> store(String id, ApiCredentials credentials) async {
    values[id] = credentials;
  }
}

void main() {
  test('foreground threshold rule JSON round-trips and validates targets', () {
    const rule = ForegroundThresholdAlertRule(
      id: 'guest-cpu',
      metric: ForegroundThresholdMetric.guestCpu,
      node: 'pve1',
      displayName: 'Web (101)',
      thresholdPercent: 85,
      severity: ForegroundAlertSeverity.critical,
      guestKind: 'qemu',
      guestVmid: 101,
      consecutiveSamples: 3,
      hysteresisPercent: 5,
    );

    final decoded = ForegroundThresholdAlertRule.fromJson(rule.toJson());
    expect(decoded.resourceKey, 'guest:qemu:pve1:101');
    expect(decoded.thresholdFraction, 0.85);
    expect(decoded.clearThresholdFraction, 0.80);
    expect(decoded.consecutiveSamples, 3);
    expect(decoded.hysteresisPercent, 5);
    final legacy = Map<String, dynamic>.from(rule.toJson())
      ..remove('consecutive_samples')
      ..remove('hysteresis_percent');
    final legacyDecoded = ForegroundThresholdAlertRule.fromJson(legacy);
    expect(legacyDecoded.consecutiveSamples, 1);
    expect(legacyDecoded.hysteresisPercent, 0);
    expect(
      () => ForegroundThresholdAlertRule.fromJson({
        ...rule.toJson(),
        'threshold_percent': 101,
      }),
      throwsFormatException,
    );
  });

  test('duration requires consecutive usable samples and resets on gaps', () {
    const rule = ForegroundThresholdAlertRule(
      id: 'node-duration',
      metric: ForegroundThresholdMetric.nodeCpu,
      node: 'pve1',
      displayName: 'pve1',
      thresholdPercent: 80,
      severity: ForegroundAlertSeverity.warning,
      consecutiveSamples: 2,
      hysteresisPercent: 5,
    );
    final engine = ForegroundThresholdAlertEngine();
    Inventory high() => Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'online', 'cpu': 0.9},
    ]);

    engine.evaluate(
      inventory: high(),
      storages: const [],
      rules: const [rule],
      storageDataCurrent: true,
    );
    expect(engine.incidents, isEmpty);

    engine.evaluate(
      inventory: Inventory.fromResources([]),
      storages: const [],
      rules: const [rule],
      storageDataCurrent: true,
    );
    expect(engine.incidents, isEmpty);

    engine.evaluate(
      inventory: high(),
      storages: const [],
      rules: const [rule],
      storageDataCurrent: true,
    );
    expect(engine.incidents, isEmpty);

    engine.evaluate(
      inventory: high(),
      storages: const [],
      rules: const [rule],
      storageDataCurrent: true,
    );
    expect(engine.incidents, hasLength(1));
  });

  test('hysteresis keeps an active rule firing until its clear threshold', () {
    const rule = ForegroundThresholdAlertRule(
      id: 'node-hysteresis',
      metric: ForegroundThresholdMetric.nodeCpu,
      node: 'pve1',
      displayName: 'pve1',
      thresholdPercent: 80,
      severity: ForegroundAlertSeverity.critical,
      hysteresisPercent: 5,
    );
    final engine = ForegroundThresholdAlertEngine();
    Inventory sample(double cpu) => Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'online', 'cpu': cpu},
    ]);

    engine.evaluate(
      inventory: sample(0.85),
      storages: const [],
      rules: const [rule],
      storageDataCurrent: true,
    );
    expect(engine.incidents, hasLength(1));

    engine.evaluate(
      inventory: sample(0.78),
      storages: const [],
      rules: const [rule],
      storageDataCurrent: true,
    );
    expect(engine.incidents, hasLength(1));
    expect(engine.incidents.single.detail, contains('hysteresis'));

    engine.evaluate(
      inventory: sample(0.75),
      storages: const [],
      rules: const [rule],
      storageDataCurrent: true,
    );
    expect(engine.incidents, isEmpty);
  });

  test('engine fires node, guest and storage threshold incidents', () {
    final inventory = Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'online', 'cpu': 0.91},
      {
        'type': 'qemu',
        'node': 'pve1',
        'vmid': 101,
        'name': 'Web',
        'status': 'running',
        'cpu': 0.86,
      },
    ], fetchedAt: DateTime.utc(2026, 11, 6, 12));
    final engine = ForegroundThresholdAlertEngine();

    engine.evaluate(
      inventory: inventory,
      storages: const [
        StoragePool(
          node: 'pve1',
          id: 'local-lvm',
          type: 'lvmthin',
          used: 91,
          total: 100,
        ),
      ],
      rules: const [
        ForegroundThresholdAlertRule(
          id: 'node',
          metric: ForegroundThresholdMetric.nodeCpu,
          node: 'pve1',
          displayName: 'pve1',
          thresholdPercent: 80,
          severity: ForegroundAlertSeverity.critical,
        ),
        ForegroundThresholdAlertRule(
          id: 'guest',
          metric: ForegroundThresholdMetric.guestCpu,
          node: 'pve1',
          displayName: 'Web (101)',
          thresholdPercent: 80,
          severity: ForegroundAlertSeverity.warning,
          guestKind: 'qemu',
          guestVmid: 101,
        ),
        ForegroundThresholdAlertRule(
          id: 'storage',
          metric: ForegroundThresholdMetric.storageUsage,
          node: 'pve1',
          displayName: 'local-lvm on pve1',
          thresholdPercent: 90,
          severity: ForegroundAlertSeverity.critical,
          storageId: 'local-lvm',
        ),
      ],
      storageDataCurrent: true,
    );

    expect(engine.incidents, hasLength(3));
    expect(engine.incidents.map((incident) => incident.source).toSet(), {
      CockpitIncidentSource.rule,
    });
    expect(
      engine.incidents.map((incident) => incident.title),
      containsAll([
        'Node pve1 CPU is 91.0%',
        'Web (101) CPU is 86.0%',
        'local-lvm on pve1 is 91.0% full',
      ]),
    );
  });

  test('active thresholds stay unresolved across missing or stale samples', () {
    const guestRule = ForegroundThresholdAlertRule(
      id: 'guest',
      metric: ForegroundThresholdMetric.guestCpu,
      node: 'pve1',
      displayName: 'Web (101)',
      thresholdPercent: 80,
      severity: ForegroundAlertSeverity.warning,
      guestKind: 'qemu',
      guestVmid: 101,
    );
    final engine = ForegroundThresholdAlertEngine();
    engine.evaluate(
      inventory: Inventory.fromResources([
        {
          'type': 'qemu',
          'node': 'pve1',
          'vmid': 101,
          'name': 'Web',
          'status': 'running',
          'cpu': 0.9,
        },
      ]),
      storages: const [],
      rules: const [guestRule],
      storageDataCurrent: true,
    );
    expect(engine.incidents, hasLength(1));

    engine.evaluate(
      inventory: Inventory.fromResources([]),
      storages: const [],
      rules: const [guestRule],
      storageDataCurrent: false,
    );
    expect(engine.incidents, hasLength(1));
    expect(engine.incidents.single.detail, contains('remains unresolved'));

    engine.evaluate(
      inventory: Inventory.fromResources([
        {
          'type': 'qemu',
          'node': 'pve1',
          'vmid': 101,
          'name': 'Web',
          'status': 'running',
          'cpu': 0.8,
        },
      ]),
      storages: const [],
      rules: const [guestRule],
      storageDataCurrent: true,
    );
    expect(engine.incidents, hasLength(1));

    engine.evaluate(
      inventory: Inventory.fromResources([
        {
          'type': 'qemu',
          'node': 'pve1',
          'vmid': 101,
          'name': 'Web',
          'status': 'running',
          'cpu': 0.3,
        },
      ]),
      storages: const [],
      rules: const [guestRule],
      storageDataCurrent: true,
    );
    expect(engine.incidents, isEmpty);
  });

  test(
    'repository isolates threshold rules by profile and purges on delete',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final vault = _MemoryVault();
      final repository = ProfileRepository(prefs, vault);
      const first = ConnectionProfile(
        id: 'one',
        name: 'One',
        endpoint: 'https://one.local:8006',
      );
      const second = ConnectionProfile(
        id: 'two',
        name: 'Two',
        endpoint: 'https://two.local:8006',
      );
      const credentials = ApiCredentials(
        tokenId: 'user@pve!mobile',
        secret: 'secret',
      );
      await repository.save(first, credentials);
      await repository.save(second, credentials);

      const rule = ForegroundThresholdAlertRule(
        id: 'node',
        metric: ForegroundThresholdMetric.nodeCpu,
        node: 'pve1',
        displayName: 'pve1',
        thresholdPercent: 80,
        severity: ForegroundAlertSeverity.warning,
      );
      await repository.saveThresholdAlertRule('one', rule);

      expect(repository.readThresholdAlertRules('one'), hasLength(1));
      expect(repository.readThresholdAlertRules('two'), isEmpty);
      await repository.delete('one');
      expect(repository.readThresholdAlertRules('one'), isEmpty);
    },
  );
}
