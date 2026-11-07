import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'components.dart';
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
      final usablePoints =
          (metricSeries?.points ?? const <StorageMetricPoint>[])
              .where(
                (point) =>
                    point.usageFraction != null &&
                    point.usedBytes != null &&
                    point.totalBytes != null,
              )
              .toList(growable: false);
      final usageHistory = usablePoints
          .map((point) => point.usageFraction!)
          .toList(growable: false);
      final usedHistory = usablePoints
          .map((point) => point.usedBytes!)
          .toList(growable: false);
      final storageSummary = usablePoints.isEmpty
          ? ''
          : 'Latest ${formatPercent(usablePoints.last.usageFraction)} • '
                '${formatBytes(usablePoints.last.usedBytes)} / '
                '${formatBytes(usablePoints.last.totalBytes)}';
      final storageRange = usablePoints.isEmpty
          ? ''
          : 'Usage range '
                '${formatPercent(usageHistory.reduce((a, b) => a < b ? a : b))}–'
                '${formatPercent(usageHistory.reduce((a, b) => a > b ? a : b))} • '
                'Used range '
                '${formatBytes(usedHistory.reduce((a, b) => a < b ? a : b))}–'
                '${formatBytes(usedHistory.reduce((a, b) => a > b ? a : b))}';

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
        body: RefreshIndicator(
          onRefresh: widget.controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
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
                SparklineCard(
                  title: 'Storage usage',
                  icon: Icons.data_usage_rounded,
                  values: usageHistory,
                  summary: storageSummary,
                  secondaryText: storageRange,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
