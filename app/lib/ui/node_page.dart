import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'components.dart';
import 'theme.dart';

class NodePage extends StatefulWidget {
  const NodePage({
    super.key,
    required this.controller,
    required this.node,
    required this.profileId,
    required this.generation,
  });

  final AppController controller;
  final Node node;
  final String profileId;
  final int generation;

  @override
  State<NodePage> createState() => _NodePageState();
}

class _NodePageState extends State<NodePage> {
  bool loadingMetrics = false;
  NodeMetricTimeframe metricTimeframe = NodeMetricTimeframe.hour;
  NodeMetricSeries? metricSeries;
  String? metricError;

  bool get _currentSession =>
      widget.controller.active?.id == widget.profileId &&
      widget.controller.connectionGeneration == widget.generation;

  Node? currentNode() {
    if (!_currentSession) return null;
    final inventory = widget.controller.inventory;
    if (inventory == null) return null;
    final matches = inventory.nodes.where(
      (node) => node.name == widget.node.name,
    );
    return matches.length == 1 ? matches.single : null;
  }

  Future<void> loadMetrics() async {
    final node = currentNode();
    if (loadingMetrics || !_currentSession || node == null) return;
    setState(() {
      loadingMetrics = true;
      metricError = null;
    });
    try {
      final result = await widget.controller.inspectNodeMetrics(
        profileId: widget.profileId,
        generation: widget.generation,
        node: node,
        timeframe: metricTimeframe,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        metricSeries = result;
        if (result == null) {
          metricError =
              'Node performance data is no longer current. Refresh and reopen this node.';
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
        metricError = 'Could not load node performance history.';
      });
    } finally {
      if (mounted && _currentSession) {
        setState(() => loadingMetrics = false);
      }
    }
  }

  void selectMetricTimeframe(NodeMetricTimeframe value) {
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

  Widget _identityHeading(Node? node, ColorScheme scheme) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          node?.name ?? widget.node.name,
          style: Theme.of(context).textTheme.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          'Node • ${widget.node.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    final avatar = CircleAvatar(
      radius: 26,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: const Icon(Icons.dns_rounded),
    );
    final status = StatusChip(status: node?.status ?? 'unavailable');
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

  Widget _overviewTab(Node? node, ColorScheme scheme) => _tabList(
    key: const Key('node-overview-list'),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _identityHeading(node, scheme),
              if (widget.controller.inventory != null) ...[
                const SizedBox(height: 14),
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
              if (node == null) ...[
                const SizedBox(height: 8),
                const Text(
                  'This node is no longer present in the current inventory.',
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      Text(
        'Current utilization',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      MetricBar(
        label: 'CPU',
        value: formatPercent(node?.cpu),
        fraction: node?.cpu,
        icon: Icons.memory_rounded,
      ),
      const SizedBox(height: 8),
      MetricBar(
        label: 'Memory',
        value: '${formatBytes(node?.mem)} / ${formatBytes(node?.maxMem)}',
        fraction:
            node != null &&
                node.maxMem != null &&
                node.maxMem! > 0 &&
                node.mem != null
            ? node.mem! / node.maxMem!
            : null,
        icon: Icons.storage_rounded,
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          leading: const Icon(Icons.schedule_rounded),
          title: const Text('Uptime'),
          subtitle: Text(formatUptime(node?.uptime)),
        ),
      ),
    ],
  );

  Widget _metricsTab() {
    final points = metricSeries?.points ?? const <NodeMetricPoint>[];
    final cpuPoints = points
        .where((point) => point.cpuFraction != null)
        .toList(growable: false);
    final memoryPoints = points
        .where((point) => point.memoryFraction != null)
        .toList(growable: false);
    final cpuHistory = normalizedSamples(
      cpuPoints.map((point) => point.cpuFraction),
    );
    final memoryHistory = normalizedSamples(
      memoryPoints.map((point) => point.memoryFraction),
    );
    return _tabList(
      key: const Key('node-metrics-list'),
      children: [
        Text(
          'Performance history',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Read-only Proxmox node RRD averages loaded only when requested. '
          'History stays in this screen and is not cached.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final timeframe in NodeMetricTimeframe.values)
              ChoiceChip(
                label: Text(timeframe.label),
                selected: metricTimeframe == timeframe,
                onSelected: currentNode() == null || loadingMetrics
                    ? null
                    : (_) => selectMetricTimeframe(timeframe),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: currentNode() == null || loadingMetrics
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
            title: 'CPU average',
            icon: Icons.memory_rounded,
            values: cpuHistory,
            timestamps: cpuPoints.map((point) => point.timestamp).toList(),
            summary: fractionRangeSummary(cpuHistory),
            axisLabel: 'CPU usage (%)',
            timeframeLabel: metricTimeframe.label,
          ),
          const SizedBox(height: 8),
          SparklineCard(
            title: 'Memory average',
            icon: Icons.storage_rounded,
            values: memoryHistory,
            timestamps: memoryPoints.map((point) => point.timestamp).toList(),
            summary: fractionRangeSummary(memoryHistory),
            axisLabel: 'Memory usage (%)',
            timeframeLabel: metricTimeframe.label,
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
          appBar: AppBar(title: const Text('Node unavailable')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Connection changed. Reopen node details from the active '
                'connection.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }

      final node = currentNode();
      final scheme = Theme.of(context).colorScheme;
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(node?.name ?? widget.node.name),
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
                Tab(key: Key('node-overview-tab'), text: 'Overview'),
                Tab(key: Key('node-metrics-tab'), text: 'Metrics'),
              ],
            ),
          ),
          body: TabBarView(
            children: [_overviewTab(node, scheme), _metricsTab()],
          ),
        ),
      );
    },
  );
}
