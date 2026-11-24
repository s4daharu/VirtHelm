import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/storage_history_review.dart';

void main() {
  final now = DateTime.utc(2026, 11, 24, 12);

  StorageMetricPoint point(int minutesAgo, int? used, {int total = 100}) =>
      StorageMetricPoint(
        timestamp: now.subtract(Duration(minutes: minutesAgo)),
        usedBytes: used,
        totalBytes: total,
      );

  List<StorageMetricPoint> samples({int last = 70}) => [
    point(40, 40),
    point(30, 45),
    point(20, 50),
    point(10, 60),
    point(0, last),
  ];

  StorageHistoryReview? review(
    List<StorageMetricPoint> points, {
    bool truncated = false,
    int malformed = 0,
    StorageMetricTimeframe timeframe = StorageMetricTimeframe.hour,
  }) => StorageHistoryReview.evaluate(
    series: StorageMetricSeries(
      points: points,
      truncated: truncated,
      malformedRecords: malformed,
    ),
    timeframe: timeframe,
    now: now,
  );

  test('reports signed observed byte and percentage-point changes', () {
    final result = review(samples())!;
    expect(result.usedByteChange, 30);
    expect(result.percentagePointChange, closeTo(30, 0.00001));
    expect(result.sampleCount, 5);
    expect(result.first.timestamp, now.subtract(const Duration(minutes: 40)));
    expect(result.last.timestamp, now);
    expect(review(samples(last: 10))!.usedByteChange, -30);
    expect(review(samples(last: 40))!.percentagePointChange, 0);
  });

  test('rejects empty, short and oversized series', () {
    expect(review([]), isNull);
    expect(review(samples().take(2).toList()), isNull);
    expect(
      review(List.filled(StorageHistoryReview.maxSamples + 1, point(0, 1))),
      isNull,
    );
  });

  test('rejects truncated or malformed responses', () {
    expect(review(samples(), truncated: true), isNull);
    expect(review(samples(), malformed: 1), isNull);
  });

  test('rejects missing, invalid and resized capacity points', () {
    for (final bad in [
      point(20, null),
      point(20, -1),
      point(20, 101),
      point(20, 0, total: 0),
      point(20, 50, total: 200),
    ]) {
      final points = samples()..[2] = bad;
      expect(review(points), isNull);
    }
  });

  test('rejects duplicate, reversed and sparse timestamps', () {
    expect(review(samples()..[2] = point(30, 50)), isNull);
    expect(review(samples().reversed.toList()), isNull);
    expect(review([point(40, 40), point(30, 50), point(0, 70)]), isNull);
  });

  test('rejects stale, future and out-of-window samples', () {
    expect(review(List.generate(5, (i) => point(55 - i * 10, 50))), isNull);
    expect(review(samples()..[4] = point(-1, 70)), isNull);
    expect(review(List.generate(9, (i) => point(80 - i * 10, 50))), isNull);
  });

  test('rejects coverage shorter than half the requested window', () {
    expect(review([point(20, 40), point(10, 50), point(0, 70)]), isNull);
    expect(
      review([point(30, 40), point(20, 50), point(10, 60), point(0, 70)]),
      isNotNull,
    );
  });

  test('uses the selected day and week coverage bounds', () {
    expect(
      review(
        List.generate(7, (i) => point((6 - i) * 240, 50)),
        timeframe: StorageMetricTimeframe.day,
      ),
      isNotNull,
    );
    expect(
      review(
        List.generate(7, (i) => point((6 - i) * 1680, 50)),
        timeframe: StorageMetricTimeframe.week,
      ),
      isNotNull,
    );
    expect(review(samples(), timeframe: StorageMetricTimeframe.day), isNull);
  });
}
