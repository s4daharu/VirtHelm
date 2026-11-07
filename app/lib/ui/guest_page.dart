import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'components.dart';
import 'theme.dart';

class GuestPage extends StatefulWidget {
  const GuestPage({
    super.key,
    required this.controller,
    required this.guest,
    required this.profileId,
    required this.generation,
  });
  final AppController controller;
  final Guest guest;
  final String profileId;
  final int generation;

  @override
  State<GuestPage> createState() => _GuestPageState();
}

class _GuestPageState extends State<GuestPage> {
  bool submitting = false;
  bool loadingMetrics = false;
  GuestMetricTimeframe metricTimeframe = GuestMetricTimeframe.hour;
  GuestMetricSeries? metricSeries;
  String? metricError;

  bool get _currentSession =>
      widget.controller.active?.id == widget.profileId &&
      widget.controller.connectionGeneration == widget.generation;

  Guest? currentGuest() {
    if (!_currentSession) return null;
    final inv = widget.controller.inventory;
    if (inv == null) return null;
    for (final guest in inv.guests) {
      if (guest.vmid == widget.guest.vmid &&
          guest.node == widget.guest.node &&
          guest.kind == widget.guest.kind) {
        return guest;
      }
    }
    return null;
  }

  Future<void> loadMetrics() async {
    final guest = currentGuest();
    if (loadingMetrics || !_currentSession || guest == null) return;
    setState(() {
      loadingMetrics = true;
      metricError = null;
    });
    try {
      final result = await widget.controller.inspectGuestMetrics(
        profileId: widget.profileId,
        generation: widget.generation,
        guest: guest,
        timeframe: metricTimeframe,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        metricSeries = result;
        if (result == null) {
          metricError =
              'Guest performance data is no longer current. Refresh and reopen this guest.';
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
        metricError = 'Could not load guest performance history.';
      });
    } finally {
      if (mounted && _currentSession) {
        setState(() => loadingMetrics = false);
      }
    }
  }

  void selectMetricTimeframe(GuestMetricTimeframe value) {
    if (value == metricTimeframe) return;
    setState(() {
      metricTimeframe = value;
      metricSeries = null;
      metricError = null;
    });
  }

  Future<void> execute(Guest guest, GuestAction action) async {
    if (submitting || !_currentSession) return;
    final isForce = action == GuestAction.stop;
    final tlsWarning =
        widget.controller.active?.allowInvalidCertificates == true
        ? '\n\nINSECURE: server certificate verification is disabled.'
        : '';
    final target =
        'Target: ${widget.controller.active?.name ?? 'Unknown connection'} / '
        '${guest.node} / ${guest.kind.toUpperCase()} ${guest.vmid}.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          if (!_currentSession) {
            return AlertDialog(
              title: const Text('Connection changed'),
              content: const Text(
                'Guest details are no longer current. Reopen this guest '
                'from the active connection.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Dismiss'),
                ),
              ],
            );
          }
          return AlertDialog(
            title: Text('${action.label} ${guest.name}?'),
            content: SingleChildScrollView(
              child: Text(
                (isForce
                        ? '$target\n\nForce stop immediately terminates this guest '
                              'without a graceful shutdown and can cause data loss. '
                              'Check the connection, node, VMID, and running services.'
                        : '$target\n\nProxmox will run this operation asynchronously.') +
                    tlsWarning,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(isForce ? 'Force stop' : 'Confirm'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !mounted || !_currentSession) return;
    setState(() => submitting = true);
    try {
      await widget.controller.runAction(
        guest,
        action,
        profileId: widget.profileId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task submitted. Check Tasks for its final result.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is PveFailure ? e.message : 'Could not submit action.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  GuestAction _primaryAction(Guest? guest) {
    if (guest == null) return GuestAction.start;
    return guest.isStopped ? GuestAction.start : GuestAction.shutdown;
  }

  IconData _actionIcon(GuestAction action) => switch (action) {
    GuestAction.start => Icons.play_arrow_rounded,
    GuestAction.shutdown => Icons.power_settings_new_rounded,
    GuestAction.reboot => Icons.restart_alt_rounded,
    GuestAction.stop => Icons.warning_amber_rounded,
  };

  String? _guardReason(Guest? guest, bool operationBlocked) {
    if (guest == null) {
      return 'Guest is not present in the current inventory.';
    }
    if (operationBlocked) {
      return 'An operation is pending or its outcome is uncertain. Check server Tasks before another action.';
    }
    if (!widget.controller.isInventoryFresh) {
      return 'STALE / OFFLINE — actions are disabled until a fresh refresh.';
    }
    if (!widget.controller.isInventoryWriteSafe) {
      return widget.controller.inventoryWarning ??
          'Inventory verification is incomplete — actions disabled.';
    }
    if (widget.controller.refreshing) {
      return 'Refreshing inventory — actions are temporarily disabled.';
    }
    return null;
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

  Widget _identityHeading(
    Guest? guest,
    ColorScheme scheme, {
    required bool includeStatus,
  }) => Row(
    children: [
      CircleAvatar(
        radius: 26,
        backgroundColor: scheme.primaryContainer,
        child: Icon(
          widget.guest.kind == 'qemu'
              ? Icons.computer_rounded
              : Icons.view_in_ar_rounded,
          color: scheme.onPrimaryContainer,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              guest?.name ?? widget.guest.name,
              style: Theme.of(context).textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${widget.guest.kind.toUpperCase()} • VMID ${widget.guest.vmid}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      if (includeStatus) StatusChip(status: guest?.status ?? 'unavailable'),
    ],
  );

  Widget _identityCard(Guest? guest, ColorScheme scheme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (MediaQuery.textScalerOf(context).scale(12) > 16) ...[
            _identityHeading(guest, scheme, includeStatus: false),
            const SizedBox(height: 10),
            StatusChip(status: guest?.status ?? 'unavailable'),
          ] else
            _identityHeading(guest, scheme, includeStatus: true),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(
                icon: Icons.dns_outlined,
                label: 'Node: ${widget.guest.node}',
              ),
              if (guest?.pool != null)
                _InfoPill(
                  icon: Icons.folder_outlined,
                  label: 'Pool: ${guest!.pool}',
                ),
              if (guest != null && guest.tags.isNotEmpty)
                _InfoPill(
                  icon: Icons.sell_outlined,
                  label: 'Tags: ${guest.tags.join(', ')}',
                ),
            ],
          ),
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
              'STALE / OFFLINE — operations disabled until a fresh refresh.',
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (!widget.controller.isInventoryWriteSafe) ...[
            const SizedBox(height: 10),
            Text(
              widget.controller.inventoryWarning ??
                  'Inventory verification is incomplete — operations disabled.',
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (guest != null &&
              widget.controller.isGuestActionBlocked(guest)) ...[
            const SizedBox(height: 10),
            Text(
              'An operation is pending or its outcome is uncertain. '
              'Check server Tasks before attempting another action.',
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (guest == null) ...[
            const SizedBox(height: 8),
            const Text(
              'The guest is not present at its previous node. It may have moved.',
            ),
          ],
        ],
      ),
    ),
  );

  Widget _overviewTab(Guest? guest, ColorScheme scheme) => _tabList(
    key: const Key('guest-overview-list'),
    children: [
      _identityCard(guest, scheme),
      const SizedBox(height: 22),
      Text('Live utilization', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      MetricBar(
        label: 'CPU',
        value: formatPercent(guest?.cpu),
        fraction: guest?.cpu,
        icon: Icons.memory_rounded,
      ),
      const SizedBox(height: 8),
      MetricBar(
        label: 'Memory',
        value: '${formatBytes(guest?.mem)} / ${formatBytes(guest?.maxMem)}',
        fraction:
            guest != null &&
                guest.maxMem != null &&
                guest.maxMem! > 0 &&
                guest.mem != null
            ? guest.mem! / guest.maxMem!
            : null,
        icon: Icons.storage_rounded,
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          title: const Text('Disk usage'),
          subtitle: Text(
            '${formatBytes(guest?.disk)} / ${formatBytes(guest?.maxDisk)}',
          ),
          leading: const Icon(Icons.disc_full_outlined),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          title: const Text('Uptime'),
          subtitle: Text(formatUptime(guest?.uptime)),
          leading: const Icon(Icons.schedule_rounded),
        ),
      ),
      const SizedBox(height: 22),
      Text(
        'Power actions are available below. Each operation is checked '
        'against fresh server state and tracked as a task.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 14),
      Text(
        'Console, snapshots, migrations, and configuration editing require '
        'additional validated authentication and API workflows. They are not '
        'part of this preview build.',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _metricsTab() {
    final cpuHistory = normalizedSamples(
      (metricSeries?.points ?? const <GuestMetricPoint>[]).map(
        (point) => point.cpuFraction,
      ),
    );
    final memoryHistory = normalizedSamples(
      (metricSeries?.points ?? const <GuestMetricPoint>[]).map(
        (point) => point.memoryFraction,
      ),
    );
    return _tabList(
      key: const Key('guest-metrics-list'),
      children: [
        Text(
          'Performance history',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Read-only Proxmox RRD averages loaded only when requested. '
          'History stays in this screen and is not cached.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final timeframe in GuestMetricTimeframe.values)
              ChoiceChip(
                label: Text(timeframe.label),
                selected: metricTimeframe == timeframe,
                onSelected: currentGuest() == null || loadingMetrics
                    ? null
                    : (_) => selectMetricTimeframe(timeframe),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: currentGuest() == null || loadingMetrics
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
            summary: fractionRangeSummary(cpuHistory),
          ),
          const SizedBox(height: 8),
          SparklineCard(
            title: 'Memory average',
            icon: Icons.storage_rounded,
            values: memoryHistory,
            summary: fractionRangeSummary(memoryHistory),
          ),
        ],
      ],
    );
  }

  Widget _ioTab(Guest? guest) => _tabList(
    key: const Key('guest-io-list'),
    children: [
      Text('Guest I/O counters', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      Text(
        'Cumulative bytes reported since the guest started, '
        'not live transfer rates. Counters may reset or be unavailable.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          title: const Text('Network traffic'),
          subtitle: Text(
            'Received: ${formatBytes(guest?.netIn)}\n'
            'Sent: ${formatBytes(guest?.netOut)}',
          ),
          leading: const Icon(Icons.swap_vert_rounded),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          title: const Text('Disk I/O'),
          subtitle: Text(
            'Read: ${formatBytes(guest?.diskRead)}\n'
            'Written: ${formatBytes(guest?.diskWrite)}',
          ),
          leading: const Icon(Icons.storage_rounded),
        ),
      ),
    ],
  );

  Widget _actionBar(
    Guest? guest,
    bool allowed,
    String? guardReason,
    ColorScheme scheme,
  ) {
    final primary = _primaryAction(guest);
    final canSubmit = allowed && guest != null && primary.allowedFor(guest);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (guardReason != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      guardReason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('guest-primary-action'),
                    onPressed: canSubmit ? () => execute(guest, primary) : null,
                    icon: submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_actionIcon(primary)),
                    label: Text(submitting ? 'Submitting…' : primary.label),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<GuestAction>(
                  key: const Key('guest-more-actions'),
                  enabled: allowed && guest != null,
                  tooltip: 'More power actions',
                  onSelected: (action) {
                    if (guest != null) execute(guest, action);
                  },
                  itemBuilder: (context) => [
                    for (final action in GuestAction.values.where(
                      (option) => option != primary,
                    ))
                      PopupMenuItem<GuestAction>(
                        value: action,
                        enabled:
                            allowed &&
                            guest != null &&
                            action.allowedFor(guest),
                        child: Row(
                          children: [
                            Icon(
                              _actionIcon(action),
                              size: 20,
                              color: action == GuestAction.stop
                                  ? scheme.error
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Text(action.label),
                          ],
                        ),
                      ),
                  ],
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (!_currentSession) {
        return Scaffold(
          appBar: AppBar(title: const Text('Guest unavailable')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Connection changed. Reopen guest details from the active '
                'connection.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }
      final guest = currentGuest();
      final scheme = Theme.of(context).colorScheme;
      final operationBlocked =
          guest != null && widget.controller.isGuestActionBlocked(guest);
      final allowed =
          guest != null &&
          widget.controller.isInventoryWriteSafe &&
          !widget.controller.refreshing &&
          !submitting &&
          !operationBlocked;
      final guardReason = _guardReason(guest, operationBlocked);
      return DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text(guest?.name ?? widget.guest.name),
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
                Tab(text: 'Overview'),
                Tab(text: 'Metrics'),
                Tab(text: 'I/O'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _overviewTab(guest, scheme),
              _metricsTab(),
              _ioTab(guest),
            ],
          ),
          bottomNavigationBar: _actionBar(guest, allowed, guardReason, scheme),
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
