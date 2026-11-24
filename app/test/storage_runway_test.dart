import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/storage_runway.dart';

void main() {
  final now = DateTime.utc(2026, 11, 24, 12);

  StorageMetricSeries history(
    List<int> usage, {
    int stepHours = 4,
    int total = 100,
    bool truncated = false,
  }) => StorageMetricSeries(
    points: List.generate(
      usage.length,
      (i) => StorageMetricPoint(
        timestamp: now.subtract(
          Duration(hours: (usage.length - 1 - i) * stepHours),
        ),
        usedBytes: usage[i],
        totalBytes: total,
      ),
    ),
    truncated: truncated,
  );

  StoragePool storage({int? used = 64, int total = 100, bool active = true}) =>
      StoragePool(
        node: 'pve1',
        id: 'local',
        type: 'dir',
        active: active,
        used: used,
        total: total,
      );

  final rising = history([40, 44, 48, 52, 56, 60, 64]);

  StorageRunway? estimate(
    StorageMetricSeries series, {
    StoragePool? current,
    StorageMetricTimeframe timeframe = StorageMetricTimeframe.day,
    DateTime? evaluatedAt,
  }) => StorageRunway.evaluate(
    series: series,
    timeframe: timeframe,
    now: evaluatedAt ?? now,
    storage: current ?? storage(),
  );

  test('steady growth returns an as-of conditional linear scenario', () {
    final result = estimate(rising)!;
    expect(result.asOf, now);
    expect(result.lowerHours, 36);
    expect(result.upperHours, 36);
    expect(result.firstRatePerHour, 1);
    expect(result.secondRatePerHour, 1);
  });

  test('different half-window slopes produce outward rounded bounds', () {
    final result = estimate(
      history([34, 38, 42, 46, 52, 58, 64]),
    )!;
    expect(result.lowerHours, 24);
    expect(result.upperHours, 36);
    expect(result.secondRatePerHour, 1.5);
    final rounded = estimate(
      history([33, 37, 41, 46, 52, 58, 65]),
      current: storage(used: 65),
    )!;
    expect(rounded.lowerHours, 22);
    expect(rounded.upperHours, 33);
  });

  test('requires day or week history with sufficient coverage', () {
    expect(estimate(rising, timeframe: StorageMetricTimeframe.hour), isNull);
    expect(estimate(history([40, 46, 52, 58, 64])), isNull);
    expect(
      estimate(history([40, 44, 48, 52, 56, 60, 64], stepHours: 3)),
      isNotNull,
    );
    expect(
      estimate(
        history([40, 44, 48, 52, 56, 60, 64], stepHours: 28),
        timeframe: StorageMetricTimeframe.week,
      ),
      isNotNull,
    );
  });

  test('rejects shrinking, flat, or inconsistent growth', () {
    for (final usage in [
      [40, 44, 43, 52, 56, 60, 64],
      [52, 52, 52, 52, 56, 60, 64],
      [40, 41, 42, 43, 50, 57, 64],
      [64, 64, 64, 64, 64, 64, 64],
    ]) {
      expect(estimate(history(usage)), isNull);
    }
  });

  test('requires a compatible current capacity snapshot', () {
    for (final current in [
      storage(used: null),
      storage(used: -1),
      storage(used: 100),
      storage(used: 67),
      storage(total: 200),
      storage(active: false),
    ]) {
      expect(estimate(rising, current: current), isNull);
    }
    expect(estimate(rising, current: storage(used: 65)), isNotNull);
    expect(estimate(rising, current: storage(used: 63)), isNotNull);
  });

  test('rejects malformed, duplicate, resized, truncated or stale history', () {
    final points = rising.points.toList();
    points[2] = points[1];
    expect(estimate(StorageMetricSeries(points: points)), isNull);
    points[2] = StorageMetricPoint(
      timestamp: rising.points[2].timestamp,
      usedBytes: 48,
      totalBytes: 200,
    );
    expect(estimate(StorageMetricSeries(points: points)), isNull);
    expect(
      estimate(StorageMetricSeries(points: rising.points, malformedRecords: 1)),
      isNull,
    );
    expect(
      estimate(StorageMetricSeries(points: rising.points, truncated: true)),
      isNull,
    );
    expect(
      estimate(rising, evaluatedAt: now.add(const Duration(hours: 5))),
      isNull,
    );
  });

  test('rejects sub-one-percent growth and out-of-horizon scenarios', () {
    expect(
      estimate(
        history([500, 501, 502, 503, 504, 505, 506], total: 1000),
        current: storage(used: 506, total: 1000),
      ),
      isNull,
    );
    expect(
      estimate(
        history([0, 0, 1, 1, 2, 2, 3], total: 300),
        current: storage(used: 3, total: 300),
      ),
      isNull,
    );
    expect(
      estimate(
        history([69, 74, 79, 84, 89, 94, 99]),
        current: storage(used: 99),
      ),
      isNull,
    );
  });
}
