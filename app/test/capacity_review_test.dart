import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/capacity_review.dart';
import 'package:virthelm/core/models.dart';

void main() {
  Inventory snapshot({
    List<Node> nodes = const [],
    List<Guest> guests = const [],
  }) => Inventory(
    nodes: nodes,
    guests: guests,
    fetchedAt: DateTime.utc(2026, 11, 19),
  );

  const online = Node(name: 'pve1', status: 'online', mem: 90, maxMem: 100);

  test('reviews node, running guest and active storage without summing', () {
    final report = CapacityReview.evaluate(
      inventory: snapshot(
        nodes: [online],
        guests: const [
          Guest(
            node: 'pve1',
            vmid: 101,
            kind: 'qemu',
            name: 'vm',
            status: 'running',
            mem: 95,
            maxMem: 100,
          ),
        ],
      ),
      storages: const [
        StoragePool(
          node: 'pve1',
          id: 'local',
          type: 'dir',
          active: true,
          used: 99,
          total: 100,
        ),
      ],
    );
    expect(report.usableMeasurements, 3);
    expect(report.missingMeasurements, 0);
    expect(
      report.signals.map((signal) => signal.metric),
      [
        CapacityMetric.storageUsage,
        CapacityMetric.guestMemory,
        CapacityMetric.nodeMemory,
      ],
    );
    expect(report.signals.first.percentage, '99.0%');
  });

  test('invalid or missing numerator and denominator are unknown', () {
    final report = CapacityReview.evaluate(
      inventory: snapshot(
        nodes: const [
          Node(name: 'a', status: 'online', mem: 101, maxMem: 100),
          Node(name: 'b', status: 'online', mem: -1, maxMem: 100),
          Node(name: 'c', status: 'online', mem: 0, maxMem: 0),
          Node(name: 'd', status: 'online'),
        ],
      ),
      storages: const [],
    );
    expect(report.usableMeasurements, 0);
    expect(report.missingMeasurements, 4);
    expect(report.signals, isEmpty);
  });

  test('offline or ambiguous nodes cannot establish guest pressure', () {
    final report = CapacityReview.evaluate(
      inventory: snapshot(
        nodes: const [
          Node(name: 'pve1', status: 'offline', mem: 99, maxMem: 100),
          Node(name: 'pve2', status: 'online', mem: 30, maxMem: 100),
          Node(name: 'pve2', status: 'online', mem: 99, maxMem: 100),
        ],
        guests: const [
          Guest(
            node: 'pve1',
            vmid: 1,
            kind: 'qemu',
            name: 'a',
            status: 'running',
            mem: 99,
            maxMem: 100,
          ),
          Guest(
            node: 'pve2',
            vmid: 2,
            kind: 'lxc',
            name: 'b',
            status: 'running',
            mem: 99,
            maxMem: 100,
          ),
          Guest(
            node: 'pve1',
            vmid: 3,
            kind: 'qemu',
            name: 'stopped',
            status: 'stopped',
            mem: 99,
            maxMem: 100,
          ),
        ],
      ),
      storages: const [],
    );
    expect(report.signals, hasLength(1));
    expect(report.signals.single.metric, CapacityMetric.nodeMemory);
    expect(report.missingMeasurements, 2);
  });

  test('templates and stopped guests never generate capacity findings', () {
    final report = CapacityReview.evaluate(
      inventory: snapshot(
        nodes: [online],
        guests: const [
          Guest(
            node: 'pve1',
            vmid: 1,
            kind: 'qemu',
            name: 'template',
            status: 'running',
            isTemplate: true,
            mem: 99,
            maxMem: 100,
          ),
          Guest(
            node: 'pve1',
            vmid: 2,
            kind: 'lxc',
            name: 'stopped',
            status: 'stopped',
            mem: 99,
            maxMem: 100,
          ),
        ],
      ),
      storages: const [],
    );
    expect(report.usableMeasurements, 1);
    expect(report.signals, hasLength(1));
  });

  test('disabled and inactive storage cannot be called current capacity', () {
    final report = CapacityReview.evaluate(
      inventory: snapshot(nodes: [online]),
      storages: const [
        StoragePool(
          node: 'pve1',
          id: 'a',
          type: 'dir',
          active: false,
          used: 100,
          total: 100,
        ),
        StoragePool(
          node: 'pve1',
          id: 'b',
          type: 'dir',
          enabled: false,
          active: true,
          used: 100,
          total: 100,
        ),
        StoragePool(
          node: 'pve1',
          id: 'c',
          type: 'dir',
          active: true,
          used: 200,
          total: 100,
        ),
      ],
    );
    expect(report.usableMeasurements, 1);
    expect(report.missingMeasurements, 1);
    expect(report.signals.single.metric, CapacityMetric.nodeMemory);
  });

  test('shared storage is per-node and exact duplicate records ignored', () {
    final report = CapacityReview.evaluate(
      inventory: snapshot(
        nodes: const [
          Node(name: 'a', status: 'online', mem: 10, maxMem: 100),
          Node(name: 'b', status: 'online', mem: 10, maxMem: 100),
        ],
      ),
      storages: const [
        StoragePool(
          node: 'a',
          id: 'shared',
          type: 'rbd',
          shared: true,
          active: true,
          used: 90,
          total: 100,
        ),
        StoragePool(
          node: 'a',
          id: 'shared',
          type: 'rbd',
          shared: true,
          active: true,
          used: 90,
          total: 100,
        ),
        StoragePool(
          node: 'b',
          id: 'shared',
          type: 'rbd',
          shared: true,
          active: true,
          used: 90,
          total: 100,
        ),
      ],
    );
    expect(report.usableMeasurements, 4);
    expect(report.missingMeasurements, 1);
    expect(report.signals, hasLength(2));
    expect(report.signals[0].resource, 'shared on a');
    expect(report.signals[1].resource, 'shared on b');
  });

  test('threshold includes 85%, excludes lower readings', () {
    final report = CapacityReview.evaluate(
      inventory: snapshot(
        nodes: const [
          Node(name: 'a', status: 'online', mem: 85, maxMem: 100),
          Node(name: 'b', status: 'online', mem: 84, maxMem: 100),
        ],
      ),
      storages: const [],
    );
    expect(report.usableMeasurements, 2);
    expect(report.signals.map((signal) => signal.resource), ['a']);
  });

  test('findings are deterministically sorted and capped at five', () {
    final report = CapacityReview.evaluate(
      inventory: snapshot(
        nodes: List.generate(
          9,
          (i) => Node(
            name: 'pve' + i.toString(),
            status: 'online',
            mem: 90 + i,
            maxMem: 100,
          ),
        ),
      ),
      storages: const [],
    );
    expect(report.signals, hasLength(CapacityReview.maxSignals));
    expect(report.signals.first.resource, 'pve8');
    expect(report.signals.last.resource, 'pve4');
    expect(report.usableMeasurements, 9);
  });

  test('bounded input scan advertises truncation, not global safety', () {
    final report = CapacityReview.evaluate(
      inventory: snapshot(
        nodes: List.generate(
          CapacityReview.maxNodeCandidates + 1,
          (i) => Node(
            name: 'n' + i.toString(),
            status: 'online',
            mem: 1,
            maxMem: 100,
          ),
        ),
      ),
      storages: const [],
    );
    expect(report.truncated, isTrue);
    expect(report.usableMeasurements, CapacityReview.maxNodeCandidates);
    expect(report.signals, isEmpty);
  });
}
