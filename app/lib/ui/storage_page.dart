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

  Widget _tabList({required Key key, required List<Widget> children}) =>
      RefreshIndicator(
        onRefresh: widget.controller.refresh,
        child: ListView(
          key: key,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
          children: children,
        ),
      );

  Widget _identityHeading(StoragePool? storage, ColorScheme scheme) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          storage?.id ?? widget.storage.id,
          style: Theme.of(context).textTheme.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '${storage?.node ?? widget.storage.node} • '
          '${storage?.type ?? widget.storage.type}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    final avatar = CircleAvatar(
      radius: 26,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: const Icon(Icons.storage_rounded),
    );
    final status = StatusChip(status: storage?.stateLabel ?? 'unavailable');
    if (MediaQuery.textScalerOf(context).scale(12) > 16) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(child: title),
            ],
          ),
          const SizedBox(height: 10),
          status,
        ],
      );
    }
    return Row(
      children: [
        avatar,
        const SizedBox(width: 12),
        Expanded(child: title),
        status,
      ],
    );
  }

  Widget _overviewTab(StoragePool? storage, ColorScheme scheme) {
    final usage = storage?.usageFraction;
    final content = storage == null || storage.contentTypes.isEmpty
        ? 'Content types unavailable'
        : storage.contentTypes.join(', ');
    final capacity =
        '${formatBytes(storage?.used)} / ${formatBytes(storage?.total)}';
    return _tabList(
      key: const Key('storage-overview-list'),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _identityHeading(storage, scheme),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (storage?.shared == true)
                      const _InfoPill(
                        icon: Icons.share_outlined,
                        label: 'Shared',
                      ),
                    _InfoPill(icon: Icons.category_outlined, label: content),
                  ],
                ),
                if (storage != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Capacity',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '$capacity${usage == null ? '' : ' • ${formatPercent(usage)}'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  UsageBar(fraction: usage, semanticsLabel: 'Storage usage'),
                ],
                if (widget.controller.inventory != null) ...[
                  const SizedBox(height: 12),
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
                if (storage == null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Storage is no longer present in the current overview.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _capacityTab() {
    final usablePoints = (metricSeries?.points ?? const <StorageMetricPoint>[])
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
    return _tabList(
      key: const Key('storage-capacity-list'),
      children: [
        Text('Capacity history', style: Theme.of(context).textTheme.titleLarge),
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
                onSelected: currentStorage() == null || loadingMetrics
                    ? null
                    : (_) => selectMetricTimeframe(timeframe),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: currentStorage() == null || loadingMetrics
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
          Text(
            metricError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
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
    );
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
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(storage?.id ?? widget.storage.id),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                onPressed: widget.controller.refresh,
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(key: Key('storage-overview-tab'), text: 'Overview'),
                Tab(key: Key('storage-capacity-tab'), text: 'Capacity'),
              ],
            ),
          ),
          body: TabBarView(
            children: [_overviewTab(storage, scheme), _capacityTab()],
          ),
        ),
      );
    },
  );
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(50),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.45),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
