import 'models.dart';
import 'storage_history_review.dart';

/// Conditional linear scenarios, not predictions or statistical intervals.
class StorageRunway {
  const StorageRunway._({
    required this.asOf,
    required this.lowerHours,
    required this.upperHours,
    required this.firstRatePerHour,
    required this.secondRatePerHour,
  });

  final DateTime asOf;
  final int lowerHours;
  final int upperHours;
  final double firstRatePerHour;
  final double secondRatePerHour;

  static const int minimumSamples = 6;
  static const int maximumHours = 90 * 24;

  static StorageRunway? evaluate({
    required StorageMetricSeries series,
    required StorageMetricTimeframe timeframe,
    required DateTime now,
    required StoragePool storage,
  }) {
    if (timeframe == StorageMetricTimeframe.hour ||
        storage.active != true ||
        storage.enabled == false) {
      return null;
    }
    final review = StorageHistoryReview.evaluate(
      series: series,
      timeframe: timeframe,
      now: now,
    );
    if (review == null || review.sampleCount < minimumSamples) return null;

    final points = series.points;
    final first = review.first;
    final last = review.last;
    final total = last.totalBytes!;
    final used = last.usedBytes!;
    final current = storage.used;
    if (storage.total != total ||
        current == null ||
        current < 0 ||
        current >= total ||
        used >= total ||
        (current - used).abs() / total > 0.01 ||
        review.usedByteChange / total < 0.01) {
      return null;
    }

    // Even one decreasing interval invalidates this intentionally narrow
    // growth scenario. This does not imply other series are healthy.
    for (var i = 1; i < points.length; i++) {
      if (points[i].usedBytes! < points[i - 1].usedBytes!) return null;
    }
    final window = timeframe == StorageMetricTimeframe.day
        ? const Duration(days: 1)
        : const Duration(days: 7);
    final middle = points[points.length ~/ 2];
    final firstSpan = middle.timestamp.difference(first.timestamp);
    final secondSpan = last.timestamp.difference(middle.timestamp);
    if (firstSpan + secondSpan < window * 0.75 ||
        firstSpan < window ~/ 4 ||
        secondSpan < window ~/ 4) {
      return null;
    }

    double rate(int bytes, Duration span) =>
        bytes / (span.inMicroseconds / Duration.microsecondsPerHour);
    final firstRate = rate(middle.usedBytes! - first.usedBytes!, firstSpan);
    final secondRate = rate(last.usedBytes! - middle.usedBytes!, secondSpan);
    final slow = firstRate < secondRate ? firstRate : secondRate;
    final fast = firstRate > secondRate ? firstRate : secondRate;
    if (slow <= 0 || !fast.isFinite || fast / slow > 2) return null;

    // Anchor the scenario to the last average, not the current wall clock.
    final remaining = total - used;
    final lower = remaining / fast;
    final upper = remaining / slow;
    if (!lower.isFinite ||
        !upper.isFinite ||
        lower < 1 ||
        upper > maximumHours) {
      return null;
    }
    return StorageRunway._(
      asOf: last.timestamp,
      lowerHours: lower.floor(),
      upperHours: upper.ceil(),
      firstRatePerHour: firstRate,
      secondRatePerHour: secondRate,
    );
  }
}
