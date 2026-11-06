import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'theme.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({
    super.key,
    required this.controller,
    required this.storage,
    required this.profileId,
    required this.generation,
  });

  final AppController controller;
  final StoragePool storage;
  final String profileId;
  final int generation;

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  bool loadingMetrics = false;
  StorageMetricTimeframe metricTimeframe = StorageMetricTimeframe.hour;
  StorageMetricSeries? metricSeries;
  String? metricError;

  bool get _currentSession =>
      widget.controller.active?.id == widget.profileId &&
      widget.controller.connectionGeneration == widget.generation;

  StoragePool? currentStorage() {
    if (!_currentSession) return null;
    final matches = widget.controller.storages.where(
      (storage) =>
          storage.node == widget.storage.node &&
          storage.id == widget.storage.id,
    );
    return matches.length == 1 ? matches.single : null;
  }

  Future<void> loadMetrics() async {
    final storage = currentStorage();
    if (loadingMetrics || !_currentSession || storage == null) return;
    setState(() {
      loadingMetrics = true;
      metricError = null;
    });
    try {
      final result = await widget.controller.inspectStorageMetrics(
        profileId: widget.profileId,
        generation: widget.generation,
        storage: storage,
        timeframe: metricTimeframe,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        metricSeries = result;
        if (result == null) {
          metricError =
              'Storage capacity data is no longer current. Refresh and reopen this storage.';
        }
      });
    } on PveFailure catch (error) {
      if (!mounted || !_currentSession) return;
      setState(() {
        metricSeries = null;
        metricError = error.message;
      });
    } catch (_) {
      if (!mounted || !_currentSession) return;
      setState(() {
        metricSeries = null;
        metricError = 'Could not load storage capacity history.';
      });
    } finally {
      if (mounted && _currentSession) {
        setState(() => loadingMetrics = false);
      }
    }
  }

  void selectMetricTimeframe(StorageMetricTimeframe value) {
    if (value == metricTimeframe) return;
    setState(() {
      metricTimeframe = value;
      metricSeries = null;
      metricError = null;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (!_currentSession) {
        return Scaffold(
          appBar: AppBar(title: const Text('Storage unavailable')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Connection changed. Reopen storage details from the active '
                'connection.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }

      final storage = currentStorage();
      final scheme = Theme.of(context).colorScheme;
      final content = storage?.contentTypes.isEmpty ?? true
          ? 'Content types unavailable'
          : storage!.contentTypes.join(', ');
      final capacity =
          '${formatBytes(storage?.used)} / ${formatBytes(storage?.total)}';
      final usage = storage?.usageFraction;

      return Scaffold(
        appBar: AppBar(
          title: Text(storage?.id ?? widget.storage.id),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: widget.controller.refresh,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          child: const Icon(Icons.storage_rounded),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            storage?.id ?? widget.storage.id,
                            style: Theme.of(context).textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StatusChip(
                          status: storage?.stateLabel ?? 'unavailable',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      storage == null
                          ? 'Storage is no longer present in the current overview.'
                          : '${storage.node} • ${storage.type}'
                                '${storage.shared == true ? ' • shared' : ''}',
                    ),
                    if (storage != null) ...[
                      const SizedBox(height: 6),
                      Text(content),
                      const SizedBox(height: 10),
                      Text(
                        'Current capacity: $capacity'
                        '${usage == null ? '' : ' • ${formatPercent(usage)} used'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                    if (widget.controller.inventory != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Last refreshed ${formatAge(widget.controller.inventory!.fetchedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (!widget.controller.isInventoryFresh) ...[
                      const SizedBox(height: 10),
                      Text(
                        'STALE / OFFLINE — historical reads require a live connection.',
                        style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Capacity history',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Read-only Proxmox storage RRD averages loaded only when requested. '
              'History stays in this screen and is not cached.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final timeframe in StorageMetricTimeframe.values)
                  ChoiceChip(
                    label: Text(timeframe.label),
                    selected: metricTimeframe == timeframe,
                    onSelected: storage == null || loadingMetrics
                        ? null
                        : (_) => selectMetricTimeframe(timeframe),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: storage == null || loadingMetrics
                    ? null
                    : loadMetrics,
                icon: loadingMetrics
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.show_chart_rounded),
                label: Text(
                  metricSeries == null ? 'Load history' : 'Refresh history',
                ),
              ),
            ),
            if (metricError != null) ...[
              const SizedBox(height: 10),
              Text(metricError!, style: TextStyle(color: scheme.error)),
            ],
            if (metricSeries != null) ...[
              const SizedBox(height: 10),
              Text(
                '${metricSeries!.points.length} usable samples'
                '${metricSeries!.malformedRecords > 0 ? ' • ${metricSeries!.malformedRecords} malformed ignored' : ''}'
                '${metricSeries!.truncated ? ' • response truncated locally' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _StorageMetricHistoryCard(points: metricSeries!.points),
            ],
          ],
        ),
      );
    },
  );
}

class _StorageMetricHistoryCard extends StatelessWidget {
  const _StorageMetricHistoryCard({required this.points});

  final List<StorageMetricPoint> points;

  @override
  Widget build(BuildContext context) {
    final usable = points
        .where(
          (point) =>
              point.usageFraction != null &&
              point.usedBytes != null &&
              point.totalBytes != null,
        )
        .toList(growable: false);
    if (usable.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.data_usage_rounded),
          title: Text('Storage usage'),
          subtitle: Text('No usable used/total samples in this response.'),
        ),
      );
    }

    final values = usable
        .map((point) => point.usageFraction!)
        .toList(growable: false);
    final usedValues = usable.map((point) => point.usedBytes!).toList();
    final latest = usable.last;
    final minimum = values.reduce((left, right) => left < right ? left : right);
    final maximum = values.reduce((left, right) => left > right ? left : right);
    final minimumUsed = usedValues.reduce(
      (left, right) => left < right ? left : right,
    );
    final maximumUsed = usedValues.reduce(
      (left, right) => left > right ? left : right,
    );
    final summary =
        'Latest ${formatPercent(latest.usageFraction)} • '
        '${formatBytes(latest.usedBytes)} / ${formatBytes(latest.totalBytes)}';
    final range =
        'Usage range ${formatPercent(minimum)}–${formatPercent(maximum)} • '
        'Used range ${formatBytes(minimumUsed)}–${formatBytes(maximumUsed)}';
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.data_usage_rounded),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Storage usage',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(summary),
            const SizedBox(height: 4),
            Text(range),
            const SizedBox(height: 10),
            Semantics(
              label:
                  'Storage usage. $summary. $range. ${values.length} samples.',
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 108,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _StorageMetricSparklinePainter(
                      values: values,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageMetricSparklinePainter extends CustomPainter {
  const _StorageMetricSparklinePainter({
    required this.values,
    required this.color,
  });

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (values.length == 1) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height * (1 - values.single)),
        2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y = size.height * (1 - values[index].clamp(0.0, 1.0).toDouble());
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StorageMetricSparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
