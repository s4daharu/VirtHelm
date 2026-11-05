import 'models.dart';

/// Only aggregate counts; never persist guest/node identity or API responses.
class OfflineOverview {
  const OfflineOverview({
    required this.fetchedAt,
    required this.totalNodes,
    required this.onlineNodes,
    required this.totalGuests,
    required this.runningGuests,
    required this.stoppedGuests,
  });

  static const maxAge = Duration(days: 7);
  final DateTime fetchedAt;
  final int totalNodes;
  final int onlineNodes;
  final int totalGuests;
  final int runningGuests;
  final int stoppedGuests;

  factory OfflineOverview.fromInventory(Inventory inventory) => OfflineOverview(
    fetchedAt: inventory.fetchedAt,
    totalNodes: inventory.nodes.length,
    onlineNodes: inventory.nodes
        .where((node) => node.status == 'online')
        .length,
    totalGuests: inventory.guests.length,
    runningGuests: inventory.guests.where((guest) => guest.isRunning).length,
    stoppedGuests: inventory.guests.where((guest) => guest.isStopped).length,
  );

  Map<String, int> toJson() => {
    'v': 1,
    'timestampMs': fetchedAt.millisecondsSinceEpoch,
    'totalNodes': totalNodes,
    'onlineNodes': onlineNodes,
    'totalGuests': totalGuests,
    'runningGuests': runningGuests,
    'stoppedGuests': stoppedGuests,
  };

  static OfflineOverview? fromJson(Object? raw, {DateTime? now}) {
    if (raw is! Map<String, dynamic> || raw.length != 7 || raw['v'] != 1) {
      return null;
    }
    final timestamp = raw['timestampMs'];
    final totalNodes = raw['totalNodes'];
    final onlineNodes = raw['onlineNodes'];
    final totalGuests = raw['totalGuests'];
    final runningGuests = raw['runningGuests'];
    final stoppedGuests = raw['stoppedGuests'];
    if (timestamp is! int ||
        totalNodes is! int ||
        onlineNodes is! int ||
        totalGuests is! int ||
        runningGuests is! int ||
        stoppedGuests is! int ||
        timestamp < 0 ||
        totalNodes < 0 ||
        totalNodes > 2048 ||
        onlineNodes < 0 ||
        onlineNodes > totalNodes ||
        totalGuests < 0 ||
        totalGuests > 100000 ||
        runningGuests < 0 ||
        stoppedGuests < 0 ||
        runningGuests + stoppedGuests > totalGuests) {
      return null;
    }
    try {
      final fetchedAt = DateTime.fromMillisecondsSinceEpoch(
        timestamp,
        isUtc: true,
      );
      final age = (now ?? DateTime.now()).difference(fetchedAt);
      if (age.isNegative || age > maxAge) return null;
      return OfflineOverview(
        fetchedAt: fetchedAt,
        totalNodes: totalNodes,
        onlineNodes: onlineNodes,
        totalGuests: totalGuests,
        runningGuests: runningGuests,
        stoppedGuests: stoppedGuests,
      );
    } catch (_) {
      return null;
    }
  }
}
