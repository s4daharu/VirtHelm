import 'models.dart';
import 'node_history_comparison.dart';

/// Guest adapter for the same bounded paired-sample algorithm as nodes.
class GuestHistoryComparison {
  static const int maxGuests = 200;
  static const int maxNodes = 64;

  static NodeMetricTimeframe _timeframe(GuestMetricTimeframe timeframe) =>
      switch (timeframe) {
        GuestMetricTimeframe.hour => NodeMetricTimeframe.hour,
        GuestMetricTimeframe.day => NodeMetricTimeframe.day,
        GuestMetricTimeframe.week => NodeMetricTimeframe.week,
      };

  static NodeMetricSeries? _adapt(GuestMetricSeries series) {
    if (series.points.length > NodeHistoryComparison.maxSamples ||
        series.truncated ||
        series.malformedRecords != 0) {
      return null;
    }
    return NodeMetricSeries(
      points: [
        for (final point in series.points)
          NodeMetricPoint(
            timestamp: point.timestamp,
            cpuFraction: point.cpuFraction,
            memoryFraction: point.memoryFraction,
          ),
      ],
    );
  }

  static bool accepts({
    required GuestMetricSeries series,
    required GuestMetricTimeframe timeframe,
    required DateTime now,
  }) {
    final adapted = _adapt(series);
    return adapted != null &&
        NodeHistoryComparison.accepts(
          series: adapted,
          timeframe: _timeframe(timeframe),
          now: now,
        );
  }

  static NodeHistoryComparison? evaluate({
    required GuestMetricSeries primary,
    required GuestMetricSeries peer,
    required GuestMetricTimeframe timeframe,
    required DateTime now,
  }) {
    final a = _adapt(primary);
    final b = _adapt(peer);
    if (a == null || b == null) return null;
    return NodeHistoryComparison.evaluate(
      primary: a,
      peer: b,
      timeframe: _timeframe(timeframe),
      now: now,
    );
  }

  /// Exact current same-kind identities; never infer hidden guests.
  static List<Guest> eligiblePeers(
    Inventory inventory,
    Guest primary, {
    bool includeOtherNodes = false,
  }) {
    if (inventory.malformedGuestRecords != 0 ||
        inventory.guests.length > maxGuests ||
        inventory.nodes.length > maxNodes ||
        primary.node.isEmpty ||
        primary.node != primary.node.trim() ||
        primary.node.length > 200 ||
        (primary.kind != 'qemu' && primary.kind != 'lxc')) {
      return const [];
    }
    final nodeCounts = <String, int>{};
    for (final node in inventory.nodes) {
      nodeCounts.update(
        node.name.trim(),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final onlineNodes = <String>{
      for (final node in inventory.nodes)
        if (node.name.isNotEmpty &&
            node.name == node.name.trim() &&
            node.name.length <= 200 &&
            node.status == 'online' &&
            nodeCounts[node.name] == 1)
          node.name,
    };
    if (!onlineNodes.contains(primary.node)) {
      return const [];
    }
    final counts = <int, int>{};
    for (final guest in inventory.guests) {
      counts.update(guest.vmid, (count) => count + 1, ifAbsent: () => 1);
    }
    bool eligible(Guest guest) =>
        (includeOtherNodes || guest.node == primary.node) &&
        onlineNodes.contains(guest.node) &&
        guest.kind == primary.kind &&
        guest.vmid > 0 &&
        counts[guest.vmid] == 1 &&
        guest.isRunning &&
        !guest.isTemplate;
    if (!inventory.guests.any(
      (guest) =>
          guest.node == primary.node &&
          guest.vmid == primary.vmid &&
          eligible(guest),
    )) {
      return const [];
    }
    return inventory.guests
        .where((guest) => guest.vmid != primary.vmid && eligible(guest))
        .toList(growable: false);
  }
}
