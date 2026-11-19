import 'models.dart';

/// Local, snapshot-only usage observations. No forecasts or write authority.
enum CapacityMetric {
  nodeMemory('Node memory'),
  guestMemory('Guest memory'),
  storageUsage('Storage usage');

  const CapacityMetric(this.label);
  final String label;
}

class CapacitySignal {
  const CapacitySignal({
    required this.metric,
    required this.resource,
    required this.fraction,
  });

  final CapacityMetric metric;
  final String resource;
  final double fraction;

  String get percentage => (fraction * 100).toStringAsFixed(1) + '%';
}

/// A bounded, deterministic review of already-loaded foreground metrics.
///
/// This is not an alert state machine or a capacity forecast. Missing values
/// are not healthy values; shared storage is reviewed per node, never summed.
class CapacityReview {
  const CapacityReview({
    required this.signals,
    required this.usableMeasurements,
    required this.missingMeasurements,
    required this.truncated,
  });

  static const double elevatedUsageFraction = 0.85;
  static const int maxNodeCandidates = 128;
  static const int maxGuestCandidates = 512;
  static const int maxStorageCandidates = 256;
  static const int maxSignals = 5;

  final List<CapacitySignal> signals;
  final int usableMeasurements;
  final int missingMeasurements;
  final bool truncated;

  static double? _fraction(int? used, int? total) {
    if (used == null ||
        total == null ||
        used < 0 ||
        total <= 0 ||
        used > total) {
      return null;
    }
    return used / total;
  }

  static CapacityReview evaluate({
    required Inventory inventory,
    required List<StoragePool> storages,
  }) {
    final signals = <CapacitySignal>[];
    var usable = 0;
    var missing = 0;
    final truncated =
        inventory.nodes.length > maxNodeCandidates ||
        inventory.guests.length > maxGuestCandidates ||
        storages.length > maxStorageCandidates;

    void measure(CapacityMetric metric, String resource, double? fraction) {
      if (fraction == null || !fraction.isFinite) {
        missing++;
        return;
      }
      usable++;
      if (fraction >= elevatedUsageFraction) {
        signals.add(
          CapacitySignal(
            metric: metric,
            resource: resource,
            fraction: fraction,
          ),
        );
      }
    }

    // Never infer guest health from an unknown/offline/ambiguous node.
    final onlineNodes = <String>{};
    final nodeCounts = <String, int>{};
    for (final node in inventory.nodes.take(maxNodeCandidates)) {
      nodeCounts.update(node.name, (count) => count + 1, ifAbsent: () => 1);
      if (node.status == 'online' && node.name.trim().isNotEmpty) {
        onlineNodes.add(node.name);
        measure(
          CapacityMetric.nodeMemory,
          node.name,
          _fraction(node.mem, node.maxMem),
        );
      }
    }
    for (final guest in inventory.guests.take(maxGuestCandidates)) {
      if (guest.isTemplate || !guest.isRunning) continue;
      if (!onlineNodes.contains(guest.node) || nodeCounts[guest.node] != 1) {
        missing++;
        continue;
      }
      measure(
        CapacityMetric.guestMemory,
        guest.kind.toUpperCase() +
            ' ' +
            guest.vmid.toString() +
            ' on ' +
            guest.node,
        _fraction(guest.mem, guest.maxMem),
      );
    }

    // Storage capacity may be shared, mirrored or backend-dependent: no totals
    // or percentages are combined across nodes, even for the same storage ID.
    final seenStorage = <String>{};
    for (final storage in storages.take(maxStorageCandidates)) {
      if (storage.enabled == false || storage.active != true) continue;
      final identity = storage.node + '\u0000' + storage.id;
      if (!seenStorage.add(identity)) {
        missing++;
        continue;
      }
      if (!onlineNodes.contains(storage.node) ||
          nodeCounts[storage.node] != 1) {
        missing++;
        continue;
      }
      measure(
        CapacityMetric.storageUsage,
        storage.id + ' on ' + storage.node,
        _fraction(storage.used, storage.total),
      );
    }

    signals.sort((a, b) {
      final byUsage = b.fraction.compareTo(a.fraction);
      if (byUsage != 0) return byUsage;
      final byType = a.metric.index.compareTo(b.metric.index);
      return byType != 0 ? byType : a.resource.compareTo(b.resource);
    });
    return CapacityReview(
      signals: List<CapacitySignal>.unmodifiable(signals.take(maxSignals)),
      usableMeasurements: usable,
      missingMeasurements: missing,
      truncated: truncated,
    );
  }
}
