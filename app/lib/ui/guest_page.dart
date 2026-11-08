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
  bool loadingSnapshots = false;
  GuestSnapshotInventory? snapshotInventory;
  String? snapshotError;
  DateTime? snapshotsLoadedAt;
  bool loadingConfiguration = false;
  GuestConfiguration? configuration;
  String? configurationError;
  DateTime? configurationLoadedAt;

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

  Future<void> loadConfiguration() async {
    final guest = currentGuest();
    if (loadingConfiguration || !_currentSession || guest == null) return;
    setState(() {
      loadingConfiguration = true;
      configurationError = null;
    });
    try {
      final result = await widget.controller.inspectGuestConfiguration(
        profileId: widget.profileId,
        generation: widget.generation,
        guest: guest,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        configuration = result;
        configurationLoadedAt = result == null ? null : DateTime.now();
        if (result == null) {
          configurationError =
              'Guest configuration is no longer current. Refresh and reopen this guest.';
        }
      });
    } on PveFailure catch (error) {
      if (!mounted || !_currentSession) return;
      setState(() {
        configuration = null;
        configurationLoadedAt = null;
        configurationError = error.message;
      });
    } catch (_) {
      if (!mounted || !_currentSession) return;
      setState(() {
        configuration = null;
        configurationLoadedAt = null;
        configurationError = 'Could not load guest configuration.';
      });
    } finally {
      if (mounted && _currentSession) {
        setState(() => loadingConfiguration = false);
      }
    }
  }

  Future<void> loadSnapshots() async {
    final guest = currentGuest();
    if (loadingSnapshots || !_currentSession || guest == null) return;
    setState(() {
      loadingSnapshots = true;
      snapshotError = null;
    });
    try {
      final result = await widget.controller.inspectGuestSnapshots(
        profileId: widget.profileId,
        generation: widget.generation,
        guest: guest,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        snapshotInventory = result;
        snapshotsLoadedAt = result == null ? null : DateTime.now();
        if (result == null) {
          snapshotError =
              'Snapshot inventory is no longer current. Refresh and reopen this guest.';
        }
      });
    } on PveFailure catch (error) {
      if (!mounted || !_currentSession) return;
      setState(() {
        snapshotInventory = null;
        snapshotsLoadedAt = null;
        snapshotError = error.message;
      });
    } catch (_) {
      if (!mounted || !_currentSession) return;
      setState(() {
        snapshotInventory = null;
        snapshotsLoadedAt = null;
        snapshotError = 'Could not load guest snapshots.';
      });
    } finally {
      if (mounted && _currentSession) {
        setState(() => loadingSnapshots = false);
      }
    }
  }

  List<RecentServerTask> _backupTasks(Guest? guest) {
    if (guest == null || !_currentSession) return const <RecentServerTask>[];
    final vmid = guest.vmid.toString();
    final matches = widget.controller.serverTasks
        .where(
          (task) =>
              task.operation.toLowerCase() == 'vzdump' &&
              task.resourceId == vmid,
        )
        .toList(growable: false);
    matches.sort((a, b) {
      final aTime =
          a.endedAt ??
          a.startedAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final bTime =
          b.endedAt ??
          b.startedAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return bTime.compareTo(aTime);
    });
    return matches.take(8).toList(growable: false);
  }

  String _snapshotSubtitle(GuestSnapshot snapshot) {
    final lines = <String>[];
    if (snapshot.isCurrent) {
      lines.add('Current configuration reported by Proxmox.');
    } else if (snapshot.createdAt != null) {
      lines.add('Created ${formatAge(snapshot.createdAt!)}');
    } else {
      lines.add('Creation time unavailable');
    }
    if (snapshot.parent != null) lines.add('Parent: ${snapshot.parent}');
    if (snapshot.includesMemory == true) lines.add('Includes VM memory state');
    if (snapshot.description != null) lines.add(snapshot.description!);
    return lines.join('\n');
  }

  String _backupTaskSubtitle(RecentServerTask task) {
    final when = task.endedAt ?? task.startedAt;
    final parts = <String>[task.node];
    if (when != null) parts.add(formatAge(when));
    if (task.exitStatus != null && task.exitStatus!.trim().isNotEmpty) {
      parts.add('Exit: ${task.exitStatus}');
    }
    return parts.join(' • ');
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
        'Read-only reviewed configuration fields are available in the '
        'Configuration tab. Console, snapshot changes, migrations, and '
        'configuration editing remain gated behind additional validated workflows.',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _metricsTab() {
    final points = metricSeries?.points ?? const <GuestMetricPoint>[];
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

  Widget _configurationSection(
    String title,
    IconData icon,
    List<GuestConfigurationField> fields,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(field.value),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _configurationTab(Guest? guest) {
    final visibleConfiguration = guest == null ? null : configuration;
    final scheme = Theme.of(context).colorScheme;
    final sections = <Widget>[];
    if (visibleConfiguration != null) {
      if (visibleConfiguration.compute.isNotEmpty) {
        sections.add(
          _configurationSection(
            'Compute',
            Icons.memory_rounded,
            visibleConfiguration.compute,
          ),
        );
      }
      if (visibleConfiguration.platform.isNotEmpty) {
        sections.add(
          _configurationSection(
            'Platform & boot',
            Icons.settings_suggest_outlined,
            visibleConfiguration.platform,
          ),
        );
      }
      if (visibleConfiguration.storage.isNotEmpty) {
        sections.add(
          _configurationSection(
            'Storage',
            Icons.storage_rounded,
            visibleConfiguration.storage,
          ),
        );
      }
      if (visibleConfiguration.network.isNotEmpty) {
        sections.add(
          _configurationSection(
            'Network',
            Icons.hub_outlined,
            visibleConfiguration.network,
          ),
        );
      }
    }

    return _tabList(
      key: const Key('guest-configuration-list'),
      children: [
        Text(
          'Guest configuration',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Loaded only when requested and never persisted. VirtHelm displays '
          'only reviewed allowlisted fields; passwords, SSH keys, arbitrary '
          'arguments, hooks, descriptions, and unknown keys are not rendered.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('guest-load-configuration'),
            onPressed: guest == null || loadingConfiguration
                ? null
                : loadConfiguration,
            icon: loadingConfiguration
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.tune_rounded),
            label: Text(
              visibleConfiguration == null
                  ? 'Load configuration'
                  : 'Refresh configuration',
            ),
          ),
        ),
        if (guest != null && configurationError != null) ...[
          const SizedBox(height: 10),
          Text(configurationError!, style: TextStyle(color: scheme.error)),
        ],
        if (visibleConfiguration != null) ...[
          const SizedBox(height: 10),
          Text(
            '${visibleConfiguration.visibleFieldCount} reviewed fields'
            '${visibleConfiguration.withheldFields > 0 ? ' • ${visibleConfiguration.withheldFields} withheld/unsupported' : ''}'
            '${visibleConfiguration.malformedFields > 0 ? ' • ${visibleConfiguration.malformedFields} malformed ignored' : ''}'
            '${visibleConfiguration.truncated ? ' • device lists truncated locally' : ''}'
            '${configurationLoadedAt != null ? ' • loaded ${formatAge(configurationLoadedAt!)}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (visibleConfiguration.visibleFieldCount == 0) ...[
            const SizedBox(height: 8),
            const Card(
              child: ListTile(
                leading: Icon(Icons.visibility_off_outlined),
                title: Text('No reviewed fields available'),
                subtitle: Text(
                  'The server response contained no configuration fields '
                  'currently approved for display.',
                ),
              ),
            ),
          ],
          for (final section in sections) ...[
            const SizedBox(height: 8),
            section,
          ],
        ],
        const SizedBox(height: 14),
        Text(
          'Configuration editing, create/clone, and migration remain disabled '
          'until their M4 mutation contracts and live-lab safety evidence exist.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
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

  Widget _recoveryTab(Guest? guest) {
    final visibleSnapshots = guest == null ? null : snapshotInventory;
    final snapshots = visibleSnapshots?.snapshots ?? const <GuestSnapshot>[];
    final recoveryPoints = snapshots.where((item) => !item.isCurrent).length;
    final backupTasks = _backupTasks(guest);
    final scheme = Theme.of(context).colorScheme;
    return _tabList(
      key: const Key('guest-recovery-list'),
      children: [
        Text(
          'Recovery visibility',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Snapshots are not backups. Snapshot inventory is read-only and '
          'loaded only when requested. Create, rollback, and delete actions '
          'are intentionally unavailable.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('guest-load-snapshots'),
            onPressed: guest == null || loadingSnapshots ? null : loadSnapshots,
            icon: loadingSnapshots
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restore_rounded),
            label: Text(
              snapshotInventory == null
                  ? 'Load snapshots'
                  : 'Refresh snapshots',
            ),
          ),
        ),
        if (guest != null && snapshotError != null) ...[
          const SizedBox(height: 10),
          Text(snapshotError!, style: TextStyle(color: scheme.error)),
        ],
        if (visibleSnapshots != null) ...[
          const SizedBox(height: 10),
          Text(
            '$recoveryPoints snapshot${recoveryPoints == 1 ? '' : 's'}'
            '${visibleSnapshots.malformedRecords > 0 ? ' • ${visibleSnapshots.malformedRecords} malformed ignored' : ''}'
            '${visibleSnapshots.truncated ? ' • response truncated locally' : ''}'
            '${snapshotsLoadedAt != null ? ' • loaded ${formatAge(snapshotsLoadedAt!)}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (snapshots.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.restore_page_outlined),
                title: Text('No snapshots reported'),
                subtitle: Text(
                  'Proxmox did not return any snapshot entries for this guest.',
                ),
              ),
            ),
          for (final snapshot in snapshots)
            Card(
              child: ListTile(
                leading: Icon(
                  snapshot.isCurrent
                      ? Icons.radio_button_checked_rounded
                      : Icons.restore_page_rounded,
                ),
                title: Text(
                  snapshot.isCurrent ? 'Current state' : snapshot.name,
                ),
                subtitle: Text(_snapshotSubtitle(snapshot)),
              ),
            ),
        ],
        const SizedBox(height: 22),
        Text(
          'Recent backup tasks',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Recent Proxmox vzdump task outcomes for this VMID only. A successful '
          'task does not prove an archive exists, is verified, or is restorable.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (widget.controller.serverTaskMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            'Recent task history is incomplete: '
            '${widget.controller.serverTaskMessage}',
            style: TextStyle(color: scheme.error),
          ),
        ],
        const SizedBox(height: 8),
        if (backupTasks.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.backup_outlined),
              title: Text('No recent backup task visible'),
              subtitle: Text(
                'The current recent-task window does not contain a vzdump task '
                'for this guest.',
              ),
            ),
          ),
        for (final task in backupTasks)
          Card(
            child: ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: Text('Backup task • ${task.stateLabel}'),
              subtitle: Text(_backupTaskSubtitle(task)),
            ),
          ),
      ],
    );
  }

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
          color:
              Theme.of(context).cardTheme.color ??
              Theme.of(context).colorScheme.surface,
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
        length: 5,
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
                Tab(key: Key('guest-overview-tab'), text: 'Overview'),
                Tab(key: Key('guest-configuration-tab'), text: 'Configuration'),
                Tab(key: Key('guest-metrics-tab'), text: 'Metrics'),
                Tab(key: Key('guest-io-tab'), text: 'I/O'),
                Tab(key: Key('guest-recovery-tab'), text: 'Recovery'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _overviewTab(guest, scheme),
              _configurationTab(guest),
              _metricsTab(),
              _ioTab(guest),
              _recoveryTab(guest),
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
