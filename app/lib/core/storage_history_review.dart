import 'models.dart';

/// A retrospective comparison of RRD averages, not a forecast or alert.
class StorageHistoryReview {
  const StorageHistoryReview._({
    required this.first,
    required this.last,
    required this.sampleCount,
  });

  static const int maxSamples = 1500;

  final StorageMetricPoint first;
  final StorageMetricPoint last;
  final int sampleCount;

  int get usedByteChange => last.usedBytes! - first.usedBytes!;
  double get percentagePointChange =>
      (last.usageFraction! - first.usageFraction!) * 100;

  /// Reject incomplete, stale, sparse, inconsistent or resized series.
  /// These coverage bounds are local heuristics, not PVE bucket guarantees.
  static StorageHistoryReview? evaluate({
    required StorageMetricSeries series,
    required StorageMetricTimeframe timeframe,
    required DateTime now,
  }) {
    final points = series.points;
    if (series.truncated ||
        series.malformedRecords != 0 ||
        points.length < 3 ||
        points.length > maxSamples) {
      return null;
    }

    final window = switch (timeframe) {
      StorageMetricTimeframe.hour => const Duration(hours: 1),
      StorageMetricTimeframe.day => const Duration(days: 1),
      StorageMetricTimeframe.week => const Duration(days: 7),
    };
    final maxGap = window ~/ 6;
    final first = points.first;
    final last = points.last;
    if (first.timestamp.isBefore(now.subtract(window + maxGap)) ||
        last.timestamp.isAfter(now) ||
        now.difference(last.timestamp) > maxGap ||
        last.timestamp.difference(first.timestamp) < window ~/ 2) {
      return null;
    }

    DateTime? previous;
    for (final point in points) {
      if (point.usageFraction == null || point.totalBytes != first.totalBytes) {
        return null;
      }
      if (previous != null &&
          (!point.timestamp.isAfter(previous) ||
              point.timestamp.difference(previous) > maxGap)) {
        return null;
      }
      previous = point.timestamp;
    }
    return StorageHistoryReview._(
      first: first,
      last: last,
      sampleCount: points.length,
    );
  }
}
