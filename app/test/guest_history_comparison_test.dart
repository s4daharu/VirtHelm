import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/guest_history_comparison.dart';
import 'package:virthelm/core/models.dart';

void main() {
  final now = DateTime.utc(2026, 11, 24, 12);
  const primary = Guest(
    node: 'pve1',
    vmid: 101,
    kind: 'qemu',
    name: 'Primary',
    status: 'running',
  );
  Guest guest(
    int vmid, {
    String node = 'pve1',
    String kind = 'qemu',
    String status = 'running',
    bool template = false,
  }) => Guest(
    node: node,
    vmid: vmid,
    kind: kind,
    name: 'Guest $vmid',
    status: status,
    isTemplate: template,
  );

  Inventory inventory(
    List<Guest> guests, {
    List<Node> nodes = const [Node(name: 'pve1', status: 'online')],
    int malformed = 0,
  }) => Inventory(
    nodes: nodes,
    guests: guests,
    fetchedAt: now,
    malformedGuestRecords: malformed,
  );

  GuestMetricSeries series({
    int step = 10,
    int offset = 0,
    double? cpu = 0.2,
    double? memory = 0.4,
    bool truncated = false,
    int malformed = 0,
    int count = 7,
  }) => GuestMetricSeries(
    points: List.generate(
      count,
      (i) => GuestMetricPoint(
        timestamp: now.subtract(
          Duration(minutes: (count - 1 - i) * step + offset),
        ),
        cpuFraction: cpu,
        memoryFraction: memory,
      ),
    ),
    truncated: truncated,
    malformedRecords: malformed,
  );

  test('guest adapter preserves separate means and matched sample count', () {
    final result = GuestHistoryComparison.evaluate(
      primary: series(),
      peer: series(cpu: 0.8, memory: 0.6),
      timeframe: GuestMetricTimeframe.hour,
      now: now,
    )!;
    expect(result.sampleCount, 7);
    expect(result.first, now.subtract(const Duration(hours: 1)));
    expect(result.last, now);
    expect(result.primaryCpu, closeTo(0.2, 0.00001));
    expect(result.peerCpu, closeTo(0.8, 0.00001));
    expect(result.primaryMemory, closeTo(0.4, 0.00001));
    expect(result.peerMemory, closeTo(0.6, 0.00001));
  });

  test('all guest windows map to their corresponding coverage rules', () {
    for (final entry in {
      GuestMetricTimeframe.hour: 10,
      GuestMetricTimeframe.day: 240,
      GuestMetricTimeframe.week: 1680,
    }.entries) {
      expect(
        GuestHistoryComparison.evaluate(
          primary: series(step: entry.value),
          peer: series(step: entry.value),
          timeframe: entry.key,
          now: now,
        )?.sampleCount,
        7,
      );
    }
  });

  test('rejects missing, truncated, malformed and oversized series', () {
    for (final bad in [
      series(cpu: null),
      series(memory: double.nan),
      series(truncated: true),
      series(malformed: 1),
      series(count: 1501),
      series(offset: 11),
    ]) {
      expect(
        GuestHistoryComparison.accepts(
          series: bad,
          timeframe: GuestMetricTimeframe.hour,
          now: now,
        ),
        isFalse,
      );
      expect(
        GuestHistoryComparison.evaluate(
          primary: series(),
          peer: bad,
          timeframe: GuestMetricTimeframe.hour,
          now: now,
        ),
        isNull,
      );
    }
  });

  test('rejects misaligned timestamps without interpolation', () {
    expect(
      GuestHistoryComparison.evaluate(
        primary: series(),
        peer: series(offset: 1),
        timeframe: GuestMetricTimeframe.hour,
        now: now,
      ),
      isNull,
    );
  });

  test('only running non-template same-node same-kind peers qualify', () {
    final peers = GuestHistoryComparison.eligiblePeers(
      inventory([
        primary,
        guest(102),
        guest(103, node: 'pve2'),
        guest(104, kind: 'lxc'),
        guest(105, status: 'stopped'),
        guest(106, template: true),
      ]),
      primary,
    );
    expect(peers.map((guest) => guest.vmid), [102]);
  });

  test('duplicate VMIDs anywhere cannot qualify even across kinds', () {
    expect(
      GuestHistoryComparison.eligiblePeers(
        inventory([primary, guest(102), guest(102, node: 'pve2')]),
        primary,
      ),
      isEmpty,
    );
    expect(
      GuestHistoryComparison.eligiblePeers(
        inventory([primary, guest(101, kind: 'lxc'), guest(102)]),
        primary,
      ),
      isEmpty,
    );
  });

  test('missing primary, partial inventory and ambiguous node fail closed', () {
    for (final bad in [
      inventory([guest(102)]),
      inventory([guest(101, status: 'stopped'), guest(102)]),
      inventory([primary, guest(102)], malformed: 1),
      inventory([primary, guest(102)], nodes: const []),
      inventory(
        [primary, guest(102)],
        nodes: const [
          Node(name: 'pve1', status: 'online'),
          Node(name: ' pve1 ', status: 'online'),
        ],
      ),
      inventory(
        [primary, guest(102)],
        nodes: const [Node(name: 'pve1', status: 'offline')],
      ),
      inventory([primary, for (var i = 0; i < 200; i++) guest(200 + i)]),
    ]) {
      expect(GuestHistoryComparison.eligiblePeers(bad, primary), isEmpty);
    }
  });

  test('cross-node peers require explicit scope and exact online nodes', () {
    final data = inventory(
      [
        primary,
        guest(102),
        guest(103, node: 'pve2'),
        guest(104, node: 'pve3'),
        guest(105, node: 'pve4'),
        guest(106, node: 'pve2', kind: 'lxc'),
        guest(107, node: 'pve2', status: 'stopped'),
        guest(108, node: 'pve2', template: true),
      ],
      nodes: const [
        Node(name: 'pve1', status: 'online'),
        Node(name: 'pve2', status: 'online'),
        Node(name: 'pve3', status: 'offline'),
      ],
    );
    expect(
      GuestHistoryComparison.eligiblePeers(data, primary).map((g) => g.vmid),
      [102],
    );
    expect(
      GuestHistoryComparison.eligiblePeers(
        data,
        primary,
        includeOtherNodes: true,
      ).map((g) => g.vmid),
      [102, 103],
    );
  });

  test('ambiguous remote nodes and VMIDs cannot be selected', () {
    final data = inventory(
      [
        primary,
        guest(102, node: 'pve2'),
        guest(103, node: 'pve3'),
        guest(103, node: 'pve4'),
      ],
      nodes: const [
        Node(name: 'pve1', status: 'online'),
        Node(name: 'pve2', status: 'online'),
        Node(name: ' pve2 ', status: 'online'),
        Node(name: 'pve3', status: 'online'),
        Node(name: 'pve4', status: 'online'),
      ],
    );
    expect(
      GuestHistoryComparison.eligiblePeers(
        data,
        primary,
        includeOtherNodes: true,
      ),
      isEmpty,
    );
  });

  test('cross-node scope rejects moved primary and oversized inventory', () {
    for (final data in [
      inventory(
        [guest(101, node: 'pve2'), guest(102)],
        nodes: const [
          Node(name: 'pve1', status: 'online'),
          Node(name: 'pve2', status: 'online'),
        ],
      ),
      inventory(
        [primary, guest(102)],
        nodes: [
          const Node(name: 'pve1', status: 'online'),
          for (var i = 0; i < GuestHistoryComparison.maxNodes; i++)
            Node(name: 'other$i', status: 'online'),
        ],
      ),
    ]) {
      expect(
        GuestHistoryComparison.eligiblePeers(
          data,
          primary,
          includeOtherNodes: true,
        ),
        isEmpty,
      );
    }
  });
}
