import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/storage_history_review.dart';
import '../core/storage_runway.dart';

class StorageHistoryReviewCard extends StatelessWidget {
  const StorageHistoryReviewCard({
    super.key,
    required this.series,
    required this.timeframe,
    required this.now,
    required this.isTrusted,
    this.currentStorage,
  });

  final StorageMetricSeries series;
  final StorageMetricTimeframe timeframe;
  final DateTime now;
  final bool isTrusted;
  final StoragePool? currentStorage;

  @override
  Widget build(BuildContext context) {
    final review = isTrusted
        ? StorageHistoryReview.evaluate(
            series: series,
            timeframe: timeframe,
            now: now,
          )
        : null;
    final storage = currentStorage;
    final runway = review != null && storage != null
        ? StorageRunway.evaluate(
            series: series,
            timeframe: timeframe,
            now: now,
            storage: storage,
          )
        : null;
    final change = review?.usedByteChange ?? 0;
    final points = review?.percentagePointChange ?? 0;
    final direction = change > 0
        ? 'Increased'
        : change < 0
        ? 'Decreased'
        : 'Unchanged';
    return Card(
      key: const Key('storage-history-review'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Observed capacity change',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (review == null)
              const Text(
                'Comparison unavailable: a current visible storage and '
                'recent, complete, sufficiently spaced, fixed-capacity '
                'history are required. No conclusion from missing data.',
              )
            else ...[
              Text(
                '$direction by ${formatBytes(change.abs())} used '
                '(${points.abs().toStringAsFixed(2)} percentage points).',
              ),
              const SizedBox(height: 6),
              Text(
                '${review.sampleCount} RRD averages • '
                '${review.first.timestamp.toUtc().toIso8601String()} to '
                '${review.last.timestamp.toUtc().toIso8601String()} (UTC)',
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              'First-to-last observed change only. Not a continuous trend, '
              'forecast, time-to-full estimate or automatic action.',
            ),
            if (review != null) ...[
              const Divider(),
              Text(
                'Conditional capacity runway',
                key: const Key('storage-runway'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              if (runway == null)
                const Text(
                  'Runway scenario unavailable. Requires a recent, well-covered '
                  '24-hour or 7-day series with consistent positive growth '
                  'and a compatible current storage reading.',
                )
              else ...[
                Text(
                  'About ${runway.lowerHours}–${runway.upperHours} hours to '
                  '100% from the last RRD average, if growth continues '
                  'at either observed half-window rate.',
                ),
                Text(
                  'Observed rates: '
                  '${formatBytes(runway.firstRatePerHour.round())}/h and '
                  '${formatBytes(runway.secondRatePerHour.round())}/h.',
                ),
                const SizedBox(height: 6),
                const Text(
                  'Illustrative linear scenarios, not a confidence interval '
                  'or a reliable prediction. Deletions, allocations, '
                  'resizing, workload changes and backend limits may '
                  'invalidate them. No action was taken.',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
