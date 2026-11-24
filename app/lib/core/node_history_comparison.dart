import 'models.dart';

/// Paired RRD sample means, not time-weighted utilization or a forecast.
class NodeHistoryComparison {
  const NodeHistoryComparison._({
    required this.first,
    required this.last,
    required this.sampleCount,
    required this.primaryCpu,
    required this.peerCpu,
    required this.primaryMemory,
    required this.peerMemory,
  });

  static const int maxSamples = 1500;
  final DateTime first;
  final DateTime last;
  final int sampleCount;
  final double primaryCpu;
  final double peerCpu;
  final double primaryMemory;
  final double peerMemory;

  static Duration _window(NodeMetricTimeframe timeframe) => switch (timeframe) {
    NodeMetricTimeframe.hour => const Duration(hours: 1),
    NodeMetricTimeframe.day => const Duration(days: 1),
    NodeMetricTimeframe.week => const Duration(days: 7),
  };

  static bool _valid(double? value) =>
      value != null && value.isFinite && value >= 0 && value <= 1;

  static bool accepts({
    required NodeMetricSeries series,
    required NodeMetricTimeframe timeframe,
    required DateTime now,
  }) {
    final points = series.points;
    if (series.truncated ||
        series.malformedRecords != 0 ||
        points.length < 3 ||
        points.length > maxSamples) {
      return false;
    }
    final window = _window(timeframe);
    final maxGap = window ~/ 6;
    final first = points.first.timestamp;
    final last = points.last.timestamp;
    if (first.isBefore(now.subtract(window + maxGap)) ||
        last.isAfter(now) ||
        now.difference(last) > maxGap ||
        last.difference(first) < window ~/ 2) {
      return false;
    }
    DateTime? previous;
    for (final point in points) {
      if (!_valid(point.cpuFraction) || !_valid(point.memoryFraction)) {
        return false;
      }
      if (previous != null &&
          (!point.timestamp.isAfter(previous) ||
              point.timestamp.difference(previous) > maxGap)) {
        return false;
      }
      previous = point.timestamp;
    }
    return true;
  }

  static NodeHistoryComparison? evaluate({
    required NodeMetricSeries primary,
    required NodeMetricSeries peer,
    required NodeMetricTimeframe timeframe,
    required DateTime now,
  }) {
    if (!accepts(series: primary, timeframe: timeframe, now: now) ||
        !accepts(series: peer, timeframe: timeframe, now: now)) {
      return null;
    }
    final window = _window(timeframe);
    final maxGap = window ~/ 6;
    final byTimestamp = {
      for (final point in peer.points)
        point.timestamp.microsecondsSinceEpoch: point,
    };
    DateTime? first;
    DateTime? last;
    var count = 0;
    var primaryCpu = 0.0;
    var peerCpu = 0.0;
    var primaryMemory = 0.0;
    var peerMemory = 0.0;
    for (final point in primary.points) {
      final match = byTimestamp[point.timestamp.microsecondsSinceEpoch];
      if (match == null) continue;
      if (last != null && point.timestamp.difference(last) > maxGap) {
        return null;
      }
      first ??= point.timestamp;
      last = point.timestamp;
      count++;
      primaryCpu += point.cpuFraction!;
      peerCpu += match.cpuFraction!;
      primaryMemory += point.memoryFraction!;
      peerMemory += match.memoryFraction!;
    }
    // At least 80% of each series must match, including recent evidence.
    if (first == null ||
        last == null ||
        count < 3 ||
        count * 5 < primary.points.length * 4 ||
        count * 5 < peer.points.length * 4 ||
        now.difference(last) > maxGap ||
        last.difference(first) < window ~/ 2) {
      return null;
    }
    return NodeHistoryComparison._(
      first: first,
      last: last,
      sampleCount: count,
      primaryCpu: primaryCpu / count,
      peerCpu: peerCpu / count,
      primaryMemory: primaryMemory / count,
      peerMemory: peerMemory / count,
    );
  }
}
