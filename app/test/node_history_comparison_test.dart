import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/node_history_comparison.dart';

void main() {
  final now = DateTime.utc(2026, 11, 24, 12);

  NodeMetricSeries series({
    int offset = 0,
    int step = 10,
    int count = 7,
    double? cpu = 0.2,
    double? memory = 0.5,
    bool truncated = false,
    int malformed = 0,
  }) => NodeMetricSeries(
    points: List.generate(
      count,
      (i) => NodeMetricPoint(
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

  NodeHistoryComparison? compare(NodeMetricSeries a, NodeMetricSeries b) =>
      NodeHistoryComparison.evaluate(
        primary: a,
        peer: b,
        timeframe: NodeMetricTimeframe.hour,
        now: now,
      );

  test('exact paired samples report separate means and UTC endpoints', () {
    final result = compare(series(), series(cpu: 0.8, memory: 0.25))!;
    expect(result.sampleCount, 7);
    expect(result.first, now.subtract(const Duration(hours: 1)));
    expect(result.last, now);
    expect(result.primaryCpu, closeTo(0.2, 0.00001));
    expect(result.peerCpu, closeTo(0.8, 0.00001));
    expect(result.primaryMemory, closeTo(0.5, 0.00001));
    expect(result.peerMemory, closeTo(0.25, 0.00001));
  });

  test('one shifted boundary bucket permits six exact matches', () {
    final result = compare(series(), series(offset: 10))!;
    expect(result.sampleCount, 6);
    expect(result.last, now.subtract(const Duration(minutes: 10)));
  });

  test('different timestamps are never interpolated or rounded', () {
    expect(compare(series(), series(offset: 1)), isNull);
    expect(compare(series(), series(step: 8)), isNull);
  });

  test('rejects stale, future, sparse and short history', () {
    for (final bad in [
      series(offset: 11),
      series(offset: -1),
      series(step: 11),
      series(count: 3),
      series(count: 2),
    ]) {
      expect(compare(series(), bad), isNull);
    }
  });

  test('rejects malformed, truncated and invalid fractions on either side', () {
    for (final bad in [
      series(truncated: true),
      series(malformed: 1),
      series(cpu: null),
      series(memory: null),
      series(cpu: double.nan),
      series(memory: double.infinity),
      series(cpu: -0.1),
      series(memory: 1.1),
    ]) {
      expect(compare(series(), bad), isNull);
      expect(compare(bad, series()), isNull);
    }
  });

  test('duplicate and reversed timestamps invalidate the series', () {
    final points = series().points;
    final duplicate = [...points]..[2] = points[1];
    expect(compare(series(), NodeMetricSeries(points: duplicate)), isNull);
    expect(
      compare(series(), NodeMetricSeries(points: points.reversed.toList())),
      isNull,
    );
  });

  test('unmatched buckets cannot create a sparse matched interval', () {
    final points = series().points;
    final changed = [...points];
    changed[3] = NodeMetricPoint(
      timestamp: points[3].timestamp.add(const Duration(minutes: 1)),
      cpuFraction: 0.5,
      memoryFraction: 0.5,
    );
    expect(compare(series(), NodeMetricSeries(points: changed)), isNull);
  });
}
