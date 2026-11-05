import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
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
      return Scaffold(
        appBar: AppBar(
          title: Text(guest?.name ?? widget.guest.name),
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
                              ),
                            ],
                          ),
                        ),
                        StatusChip(status: guest?.status ?? 'unavailable'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Node: ${widget.guest.node}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (widget.controller.inventory != null) ...[
                      const SizedBox(height: 4),
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
                    if (operationBlocked) ...[
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
            ),
            const SizedBox(height: 22),
            Text(
              'Live utilization',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _ResourceMeter(
              label: 'CPU',
              current: formatPercent(guest?.cpu),
              fraction: guest?.cpu,
            ),
            const SizedBox(height: 8),
            _ResourceMeter(
              label: 'Memory',
              current:
                  '${formatBytes(guest?.mem)} / ${formatBytes(guest?.maxMem)}',
              fraction:
                  guest != null &&
                      guest.maxMem != null &&
                      guest.maxMem! > 0 &&
                      guest.mem != null
                  ? guest.mem! / guest.maxMem!
                  : null,
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
              'Guest I/O counters',
              style: Theme.of(context).textTheme.titleLarge,
            ),
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
            const SizedBox(height: 26),
            Text(
              'Power controls',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Each operation is checked against fresh server state and tracked as a task.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            for (final action in GuestAction.values) ...[
              Card(
                child: ListTile(
                  leading: Icon(
                    switch (action) {
                      GuestAction.start => Icons.play_arrow_rounded,
                      GuestAction.shutdown => Icons.power_settings_new_rounded,
                      GuestAction.reboot => Icons.restart_alt_rounded,
                      GuestAction.stop => Icons.warning_amber_rounded,
                    },
                    color: action == GuestAction.stop
                        ? scheme.error
                        : scheme.primary,
                  ),
                  title: Text(action.label),
                  subtitle: Text(
                    action == GuestAction.stop
                        ? 'Immediate power off • possible data loss'
                        : action == GuestAction.start
                        ? 'Boot guest'
                        : action == GuestAction.shutdown
                        ? 'Request a graceful shutdown'
                        : 'Request guest reboot',
                  ),
                  enabled: allowed && action.allowedFor(guest),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: allowed && action.allowedFor(guest)
                      ? () => execute(guest, action)
                      : null,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (submitting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Console, snapshots, migrations, and configuration editing require additional validated authentication and API workflows. They are not part of this first build.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    },
  );
}

class _ResourceMeter extends StatelessWidget {
  const _ResourceMeter({
    required this.label,
    required this.current,
    required this.fraction,
  });
  final String label;
  final String current;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Flexible(child: Text(current, textAlign: TextAlign.end)),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              label: fraction == null || !fraction!.isFinite
                  ? '$label unavailable'
                  : label,
              child: ExcludeSemantics(
                excluding: fraction == null || !fraction!.isFinite,
                child: LinearProgressIndicator(
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(5),
                  value: fraction != null && fraction!.isFinite
                      ? fraction!.clamp(0.0, 1.0).toDouble()
                      : 0,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
