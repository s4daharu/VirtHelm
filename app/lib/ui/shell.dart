import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/app_info.dart';
import '../core/device_connectivity.dart';
import '../core/foreground_notifications.dart';
import '../core/app_preferences.dart';
import '../core/guest_list_filter.dart';
import '../core/guest_saved_view.dart';
import '../core/incident_center.dart';
import '../core/models.dart';
import '../core/offline_inventory.dart';
import '../core/task_history_filter.dart';
import 'components.dart';
import 'connect_page.dart';
import 'connections_page.dart';
import 'guest_page.dart';
import 'incident_center_tab.dart';
import 'lxc_create_page.dart';
import 'node_page.dart';
import 'qemu_create_page.dart';
import 'storage_page.dart';
import 'theme.dart';
import 'task_details_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  late int selectedIndex;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.controller.takeIncidentCenterNavigationRequest()
        ? 3
        : 0;
    widget.controller.addListener(_handleControllerNavigation);
  }

  @override
  void didUpdateWidget(covariant ShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerNavigation);
      widget.controller.addListener(_handleControllerNavigation);
      _handleControllerNavigation();
    }
  }

  void _handleControllerNavigation() {
    if (!widget.controller.takeIncidentCenterNavigationRequest()) return;
    if (!mounted || selectedIndex == 3) return;
    setState(() => selectedIndex = 3);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerNavigation);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final profile = controller.active;
    final insecure = profile?.allowInvalidCertificates == true;
    final inventory = controller.inventory;
    final freshness = profile == null
        ? null
        : controller.deviceNetworkState == DeviceNetworkState.unavailable
        ? 'Network unavailable'
        : inventory == null
        ? 'No live snapshot'
        : controller.isInventoryFresh
        ? 'Live • ${formatAge(inventory.fetchedAt)}'
        : 'Stale • ${formatAge(inventory.fetchedAt)}';
    return Scaffold(
      appBar: AppBar(
        toolbarHeight:
            32 +
            MediaQuery.textScalerOf(context).scale(20) +
            MediaQuery.textScalerOf(context).scale(12),
        titleSpacing: 16,
        title: Row(
          children: [
            Icon(
              Icons.hub_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('VirtHelm'),
                  Text(
                    '${insecure ? 'TLS UNVERIFIED • ' : ''}'
                    '${profile?.name ?? 'No connection'}'
                    '${profile?.lastServerVersion == null ? '' : ' • PVE ${profile!.lastServerVersion}'}'
                    '${freshness == null ? '' : ' • $freshness'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color:
                          controller.deviceNetworkState ==
                                  DeviceNetworkState.unavailable ||
                              inventory != null && !controller.isInventoryFresh
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (controller.refreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: () => unawaited(controller.refresh()),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh inventory',
            ),
          PopupMenuButton<String>(
            tooltip: 'Switch connection',
            onSelected: (value) {
              if (value == '__manage') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConnectionsPage(controller: controller),
                  ),
                );
                return;
              }
              if (value == '__add') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConnectPage(controller: controller),
                  ),
                );
                return;
              }
              for (final p in controller.profiles) {
                if (p.id == value) {
                  unawaited(controller.activate(p));
                  break;
                }
              }
            },
            itemBuilder: (context) => [
              for (final p in controller.profiles)
                PopupMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      Icon(
                        p.id == profile?.id
                            ? Icons.check_circle
                            : Icons.dns_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${p.name}${p.allowInvalidCertificates ? ' • TLS UNVERIFIED' : ''}',
                        ),
                      ),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: '__manage',
                child: Row(
                  children: [
                    Icon(Icons.settings_input_component_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Manage connections'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '__add',
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline, size: 18),
                    SizedBox(width: 10),
                    Text('Add connection'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (controller.deviceNetworkState == DeviceNetworkState.unavailable)
            const Padding(
              key: Key('device-network-unavailable'),
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.wifi_off_rounded),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'NO DEFAULT NETWORK • Android cannot see a default network. '
                      'Live actions are disabled; check Wi-Fi/VPN and refresh.',
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: [
                _OverviewTab(
                  controller: controller,
                  onOpenGuests: () => setState(() => selectedIndex = 1),
                  onOpenIncidents: () => setState(() => selectedIndex = 3),
                ),
                _GuestsTab(controller: controller),
                _TasksTab(
                  key: ValueKey(
                    'tasks:${profile?.id}:${controller.connectionGeneration}',
                  ),
                  controller: controller,
                ),
                IncidentCenterTab(
                  key: ValueKey(
                    'incidents:${profile?.id}:${controller.connectionGeneration}',
                  ),
                  controller: controller,
                ),
                _SettingsTab(controller: controller),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) => setState(() => selectedIndex = value),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns_rounded),
            label: 'Guests',
          ),
          const NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline_rounded),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Badge.count(
              count: controller.incidents.length,
              isLabelVisible: controller.incidents.isNotEmpty,
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge.count(
              count: controller.incidents.length,
              isLabelVisible: controller.incidents.isNotEmpty,
              child: const Icon(Icons.notifications_rounded),
            ),
            label: 'Incidents',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.controller,
    required this.onOpenGuests,
    required this.onOpenIncidents,
  });
  final AppController controller;
  final VoidCallback onOpenGuests;
  final VoidCallback onOpenIncidents;

  @override
  Widget build(BuildContext context) {
    final inv = controller.inventory;
    final cached = inv == null ? controller.cachedOverview : null;
    final cachedInventory = inv == null ? controller.cachedInventory : null;
    final hasCounts = inv != null || cached != null || cachedInventory != null;
    final scheme = Theme.of(context).colorScheme;
    final profileId = controller.active?.id;
    final generation = controller.connectionGeneration;
    final countGuests =
        inv?.guests.where((g) => !g.isTemplate).length ??
        cached?.totalGuests ??
        cachedInventory?.totalGuests ??
        0;
    final countRunning =
        inv?.guests.where((g) => !g.isTemplate && g.isRunning).length ??
        cached?.runningGuests ??
        cachedInventory?.runningGuests ??
        0;
    final countStopped =
        inv?.guests.where((g) => !g.isTemplate && g.isStopped).length ??
        cached?.stoppedGuests ??
        cachedInventory?.stoppedGuests ??
        0;
    final nodeOnline =
        inv?.nodes.where((n) => n.status == 'online').length ??
        cached?.onlineNodes ??
        cachedInventory?.onlineNodes ??
        0;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [
                  scheme.primaryContainer,
                  scheme.tertiaryContainer.withValues(alpha: 0.72),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'CLUSTER OVERVIEW',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  controller.active?.name ?? 'Cluster',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  inv == null
                      ? cachedInventory != null
                            ? 'CACHED INVENTORY • ${formatAge(cachedInventory.fetchedAt)} • not live'
                            : cached == null
                            ? 'Waiting for live inventory'
                            : 'CACHED COUNTS • ${formatAge(cached.fetchedAt)} • not live'
                      : controller.isInventoryFresh
                      ? 'Live snapshot • ${formatAge(inv.fetchedAt)}'
                      : 'STALE snapshot • ${formatAge(inv.fetchedAt)}',
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 18),
                Text(
                  controller.active?.endpoint ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          if (controller.message != null) ...[
            const SizedBox(height: 14),
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        controller.message!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (cachedInventory != null) ...[
            const SizedBox(height: 14),
            const MessageCard(
              text:
                  'CACHED / NOT LIVE • Node and guest identity/status are last-known '
                  'display-only data. Metrics, details, task reads and every '
                  'server action require a fresh live connection.',
            ),
          ] else if (cached != null) ...[
            const SizedBox(height: 14),
            const MessageCard(
              text:
                  'Last-known counts only. Guest details and power '
                  'actions require a fresh live connection.',
            ),
          ],
          if (controller.inventoryWarning != null) ...[
            const SizedBox(height: 14),
            MessageCard(text: controller.inventoryWarning!),
          ],
          if (controller.active != null &&
              (controller.inventory != null ||
                  controller.incidents.isNotEmpty)) ...[
            const SizedBox(height: 18),
            _OverviewIncidentSummary(
              controller: controller,
              onTap: onOpenIncidents,
            ),
          ],
          const SizedBox(height: 24),
          SectionHeading(title: 'Infrastructure', trailing: 'CURRENT SNAPSHOT'),
          const SizedBox(height: 12),
          GridView(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent:
                  112 +
                  MediaQuery.textScalerOf(context).scale(26) +
                  MediaQuery.textScalerOf(context).scale(11) * 2,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _MetricCard(
                title: 'Nodes online',
                value: hasCounts
                    ? '$nodeOnline / ${inv?.nodes.length ?? cached!.totalNodes}'
                    : '—',
                icon: Icons.hub_outlined,
                color: const Color(0xFF20BFAF),
              ),
              _MetricCard(
                title: 'Guests total',
                value: hasCounts ? '$countGuests' : '—',
                icon: Icons.computer_outlined,
                color: const Color(0xFF6498F8),
              ),
              _MetricCard(
                title: 'Running',
                value: hasCounts ? '$countRunning' : '—',
                icon: Icons.play_circle_outline,
                color: const Color(0xFF20BFAF),
              ),
              _MetricCard(
                title: 'Stopped',
                value: hasCounts ? '$countStopped' : '—',
                icon: Icons.pause_circle_outline,
                color: const Color(0xFFE9A95D),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SectionHeading(
            title: 'Nodes',
            trailing: inv == null ? '' : '${inv.nodes.length} FOUND',
          ),
          const SizedBox(height: 12),
          if (inv == null && cachedInventory == null)
            const MessageCard(
              text: 'Connect to load node health. Pull to refresh.',
            )
          else if (inv != null && inv.nodes.isEmpty)
            const MessageCard(
              text: 'No nodes are visible to this token. Review permissions.',
            )
          else if (inv != null)
            for (final node in inv.nodes) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storage_rounded),
                  title: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: controller.showNodeMetrics
                      ? Text(
                          'CPU ${formatPercent(node.cpu)} • '
                          'RAM ${formatBytes(node.mem)} • '
                          'Uptime ${formatUptime(node.uptime)}',
                        )
                      : null,
                  trailing: StatusChip(status: node.status),
                  onTap: profileId == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => NodePage(
                              controller: controller,
                              node: node,
                              profileId: profileId,
                              generation: generation,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
            ]
          else
            for (final node in cachedInventory!.nodes) ...[
              _OfflineNodeTile(node: node),
              const SizedBox(height: 8),
            ],

          const SizedBox(height: 22),
          SectionHeading(
            title: 'Storage',
            trailing: controller.storages.isEmpty
                ? ''
                : '${controller.storages.length} VISIBLE',
          ),
          const SizedBox(height: 12),
          if (controller.storageMessage != null) ...[
            MessageCard(text: controller.storageMessage!),
            const SizedBox(height: 8),
          ],
          if (inv != null &&
              controller.storages.isEmpty &&
              controller.storageMessage == null)
            const MessageCard(
              text: 'No storage pools are visible to this token.',
            )
          else
            for (final storage in controller.storages) ...[
              _StorageTile(
                storage: storage,
                onTap: profileId == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StoragePage(
                            controller: controller,
                            storage: storage,
                            profileId: profileId,
                            generation: generation,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Workloads',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: onOpenGuests,
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (inv != null)
            for (final guest in inv.guests.take(5)) ...[
              _GuestTile(guest: guest, controller: controller),
              const SizedBox(height: 8),
            ]
          else if (cachedInventory != null)
            for (final guest in cachedInventory.guests.take(5)) ...[
              _OfflineGuestTile(guest: guest),
              const SizedBox(height: 8),
            ],
          if (inv != null && inv.guests.isEmpty)
            const MessageCard(
              text: 'No QEMU VMs or LXC containers are visible.',
            )
          else if (inv == null &&
              cachedInventory != null &&
              cachedInventory.guests.isEmpty)
            const MessageCard(
              text: 'No cached QEMU VMs or LXC containers were visible.',
            ),
        ],
      ),
    );
  }
}

class _OverviewIncidentSummary extends StatelessWidget {
  const _OverviewIncidentSummary({
    required this.controller,
    required this.onTap,
  });

  final AppController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status =
        Theme.of(context).extension<VirtHelmStatusColors>() ??
        const VirtHelmStatusColors(
          positive: Color(0xFF087A64),
          warning: Color(0xFF9A5A12),
          error: Color(0xFFB3261E),
          neutral: Color(0xFF5F6368),
        );
    final incidents = controller.incidents;
    final critical = incidents
        .where(
          (incident) => incident.severity == CockpitIncidentSeverity.critical,
        )
        .length;
    final warning = incidents
        .where(
          (incident) => incident.severity == CockpitIncidentSeverity.warning,
        )
        .length;
    final stale = !controller.isInventoryFresh;
    return Card(
      key: const Key('overview-incident-summary'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    incidents.isEmpty
                        ? Icons.verified_outlined
                        : Icons.notifications_active_outlined,
                    size: 20,
                    color: incidents.isEmpty ? status.positive : status.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Foreground incidents',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (stale) ...[
                Text(
                  'MAY BE STALE • Confirm with a clean refresh.',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: status.warning,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (incidents.isEmpty)
                Text(
                  stale
                      ? 'No retained incidents, but live health cannot be confirmed.'
                      : 'No current node or task incidents in the foreground snapshot.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Row(
                  children: [
                    _IncidentCount(
                      label: 'Critical',
                      count: critical,
                      color: status.error,
                    ),
                    const SizedBox(width: 10),
                    _IncidentCount(
                      label: 'Warnings',
                      count: warning,
                      color: status.warning,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncidentCount extends StatelessWidget {
  const _IncidentCount({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _StorageTile extends StatelessWidget {
  const _StorageTile({required this.storage, this.onTap});
  final StoragePool storage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final usage = storage.usageFraction;
    final content = storage.contentTypes.isEmpty
        ? 'content unknown'
        : storage.contentTypes.join(', ');
    final capacity = storage.used == null && storage.total == null
        ? 'capacity unavailable'
        : '${formatBytes(storage.used)} / ${formatBytes(storage.total)}';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.storage_outlined),
        title: Text(storage.id, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${storage.node} • ${storage.type} • $content\n'
          '$capacity${usage == null ? '' : ' • ${formatPercent(usage)}'}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusChip(status: storage.stateLabel),
        onTap: onTap,
      ),
    );
  }
}

class _OfflineNodeTile extends StatelessWidget {
  const _OfflineNodeTile({required this.node});

  final OfflineInventoryNode node;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('offline-node-${node.name}'),
    child: ListTile(
      leading: const Icon(Icons.history_rounded),
      title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: const Text('CACHED / NOT LIVE • metrics unavailable'),
      trailing: StatusChip(status: node.status),
    ),
  );
}

class _OfflineGuestTile extends StatelessWidget {
  const _OfflineGuestTile({required this.guest});

  final OfflineInventoryGuest guest;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('offline-guest-${guest.kind}-${guest.vmid}'),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        child: Icon(
          guest.kind == 'qemu'
              ? Icons.computer_outlined
              : Icons.view_in_ar_outlined,
        ),
      ),
      title: Text(guest.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        'CACHED / NOT LIVE • '
        '${guest.isTemplate ? 'TEMPLATE • ' : ''}'
        '${guest.kind.toUpperCase()} • ${guest.vmid} • ${guest.node}\n'
        'Details and actions require a fresh live connection.',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: StatusChip(status: guest.status),
    ),
  );
}

class _GuestTile extends StatelessWidget {
  const _GuestTile({required this.guest, required this.controller});
  final Guest guest;
  final AppController controller;

  Future<void> _toggleFavorite(BuildContext context, String profileId) async {
    try {
      await controller.toggleGuestFavorite(guest, expectedProfileId: profileId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update guest favorites.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Capture scope when this tile is rendered, not later when a route builds.
    final profileId = controller.active?.id;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: Icon(
            guest.kind == 'qemu'
                ? Icons.computer_rounded
                : Icons.view_in_ar_rounded,
          ),
        ),
        title: Text(guest.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${guest.isTemplate ? 'TEMPLATE • ' : ''}'
          '${guest.kind.toUpperCase()} • ${guest.vmid} • ${guest.node}'
          '${guest.pool == null ? '' : '\nPool: ${guest.pool}'}'
          '${guest.tags.isEmpty ? '' : '\nTags: ${guest.tags.join(', ')}'}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: controller.isGuestFavorite(guest)
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              onPressed: profileId == null
                  ? null
                  : () => _toggleFavorite(context, profileId),
              icon: Icon(
                controller.isGuestFavorite(guest)
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
              ),
            ),
            StatusChip(status: guest.status),
          ],
        ),
        onTap: profileId == null
            ? null
            : () {
                final generation = controller.connectionGeneration;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GuestPage(
                      controller: controller,
                      guest: guest,
                      profileId: profileId,
                      generation: generation,
                    ),
                  ),
                );
              },
      ),
    );
  }
}

class _GuestsTab extends StatefulWidget {
  const _GuestsTab({required this.controller});
  final AppController controller;
  @override
  State<_GuestsTab> createState() => _GuestsTabState();
}

class _GuestsTabState extends State<_GuestsTab> {
  final search = TextEditingController();
  String query = '';
  String filter = 'all';
  GuestKindFilter kind = GuestKindFilter.all;
  GuestSort sort = GuestSort.favorites;
  String? nodeFilter;
  String? tagFilter;
  String? poolFilter;
  String? profileId;
  String? activeViewId;

  @override
  void initState() {
    super.initState();
    profileId = widget.controller.active?.id;
  }

  @override
  void didUpdateWidget(covariant _GuestsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextId = widget.controller.active?.id;
    if (profileId != nextId) {
      // A saved list selection must not hide another profile's inventory.
      profileId = nextId;
      search.clear();
      query = '';
      filter = 'all';
      kind = GuestKindFilter.all;
      nodeFilter = null;
      tagFilter = null;
      poolFilter = null;
      sort = GuestSort.favorites;
      activeViewId = null;
    }
  }

  void _manualChange(VoidCallback update) {
    setState(() {
      activeViewId = null;
      update();
    });
  }

  void _applyView(SavedGuestView view) {
    setState(() {
      search.value = TextEditingValue(
        text: view.search,
        selection: TextSelection.collapsed(offset: view.search.length),
      );
      query = view.search;
      filter = view.status;
      kind = view.kind;
      nodeFilter = view.node;
      tagFilter = view.tag;
      poolFilter = view.pool;
      sort = view.sort;
      activeViewId = view.id;
    });
  }

  bool get _hasActiveFilters =>
      query.isNotEmpty ||
      filter != 'all' ||
      kind != GuestKindFilter.all ||
      nodeFilter != null ||
      tagFilter != null ||
      poolFilter != null ||
      sort != GuestSort.favorites;

  void _clearFilters() {
    search.clear();
    setState(() {
      query = '';
      filter = 'all';
      kind = GuestKindFilter.all;
      nodeFilter = null;
      tagFilter = null;
      poolFilter = null;
      sort = GuestSort.favorites;
      activeViewId = null;
    });
  }

  int get _sheetFilterCount =>
      (kind == GuestKindFilter.all ? 0 : 1) +
      (nodeFilter == null ? 0 : 1) +
      (tagFilter == null ? 0 : 1) +
      (poolFilter == null ? 0 : 1) +
      (sort == GuestSort.favorites ? 0 : 1);

  String _kindLabel(GuestKindFilter value) => switch (value) {
    GuestKindFilter.all => 'Any type',
    GuestKindFilter.qemu => 'VMs',
    GuestKindFilter.lxc => 'Containers',
  };

  Future<void> _openFilters(
    BuildContext context, {
    required List<String> nodes,
    required List<String> tags,
    required List<String> pools,
  }) async {
    final selection = await showModalBottomSheet<_GuestFilterSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _GuestFilterSheet(
        kind: kind,
        node: nodeFilter,
        tag: tagFilter,
        pool: poolFilter,
        sort: sort,
        nodes: nodes,
        tags: tags,
        pools: pools,
      ),
    );
    if (selection == null || !mounted) return;
    _manualChange(() {
      kind = selection.kind;
      nodeFilter = selection.node;
      tagFilter = selection.tag;
      poolFilter = selection.pool;
      sort = selection.sort;
    });
  }

  Future<void> _openQemuCreate(BuildContext context) async {
    final scopedProfileId = widget.controller.active?.id;
    if (scopedProfileId == null || !widget.controller.isInventoryWriteSafe) {
      return;
    }
    final generation = widget.controller.connectionGeneration;
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QemuCreatePage(
          controller: widget.controller,
          profileId: scopedProfileId,
          generation: generation,
        ),
      ),
    );
    if (!context.mounted ||
        submitted != true ||
        widget.controller.active?.id != scopedProfileId ||
        widget.controller.connectionGeneration != generation) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'QEMU create task submitted. Check Tasks for its final result.',
        ),
      ),
    );
  }

  Future<void> _openLxcCreate(BuildContext context) async {
    final scopedProfileId = widget.controller.active?.id;
    if (scopedProfileId == null || !widget.controller.isInventoryWriteSafe) {
      return;
    }
    final generation = widget.controller.connectionGeneration;
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LxcCreatePage(
          controller: widget.controller,
          profileId: scopedProfileId,
          generation: generation,
        ),
      ),
    );
    if (!context.mounted ||
        submitted != true ||
        widget.controller.active?.id != scopedProfileId ||
        widget.controller.connectionGeneration != generation) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'LXC create task submitted. Check Tasks for its final result.',
        ),
      ),
    );
  }

  Future<void> _saveCurrentView(BuildContext context) async {
    final scopedProfileId = profileId;
    if (scopedProfileId == null) return;
    var viewName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save guest view'),
        content: TextField(
          autofocus: true,
          maxLength: maxSavedGuestViewNameLength,
          decoration: const InputDecoration(
            labelText: 'View name',
            helperText: 'Saving the same name updates that view.',
          ),
          textInputAction: TextInputAction.done,
          onChanged: (value) => viewName = value,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, viewName),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    try {
      final view = SavedGuestView.create(
        name: name,
        search: query,
        status: filter,
        kind: kind,
        node: nodeFilter,
        tag: tagFilter,
        pool: poolFilter,
        sort: sort,
      );
      final saved = await widget.controller.saveGuestView(
        view,
        expectedProfileId: scopedProfileId,
      );
      if (!mounted || saved == null) return;
      setState(() => activeViewId = saved.id);
    } on FormatException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a view name up to 40 characters.'),
          ),
        );
      }
    } on StateError {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save view. Remove an old view or use another name.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteView(BuildContext context, SavedGuestView view) async {
    final scopedProfileId = profileId;
    if (scopedProfileId == null) return;
    try {
      await widget.controller.deleteGuestView(
        view.id,
        expectedProfileId: scopedProfileId,
      );
      if (mounted && activeViewId == view.id) {
        setState(() => activeViewId = null);
      }
    } on StateError {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove saved view.')),
        );
      }
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<OfflineInventoryGuest> _visibleOfflineGuests(
    OfflineInventorySnapshot snapshot,
  ) {
    final needle = query.trim().toLowerCase();
    final result = snapshot.guests.where((guest) {
      if (needle.isEmpty) return true;
      return guest.name.toLowerCase().contains(needle) ||
          guest.vmid.toString().contains(needle) ||
          guest.node.toLowerCase().contains(needle) ||
          guest.kind.contains(needle);
    }).toList();
    result.sort((left, right) {
      final byName = left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      );
      if (byName != 0) return byName;
      final byVmid = left.vmid.compareTo(right.vmid);
      if (byVmid != 0) return byVmid;
      return left.node.compareTo(right.node);
    });
    return result;
  }

  Widget _buildOfflineInventory(
    BuildContext context,
    OfflineInventorySnapshot snapshot,
  ) {
    final guests = _visibleOfflineGuests(snapshot);
    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const MessageCard(
                    key: Key('offline-inventory-banner'),
                    text:
                        'CACHED / NOT LIVE • This is a last-known inventory list. '
                        'Guest/node details, metrics, task reads and every server '
                        'action remain unavailable until a fresh live refresh succeeds.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('offline-inventory-search'),
                    controller: search,
                    onChanged: (value) => setState(() => query = value),
                    decoration: const InputDecoration(
                      hintText: 'Search cached guest, VMID, node, or type',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text(
                        '${guests.length} cached entries',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Snapshot ${formatAge(snapshot.fetchedAt)} • max 24h',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (guests.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: query.trim().isEmpty
                    ? 'No cached workloads'
                    : 'No cached workloads found',
                body: query.trim().isEmpty
                    ? 'The last eligible live inventory contained no cached guest entries.'
                    : 'Try another cached guest name, VMID, node, or type.',
                action: query.trim().isEmpty
                    ? null
                    : TextButton(
                        onPressed: () {
                          search.clear();
                          setState(() => query = '');
                        },
                        child: const Text('Clear search'),
                      ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              sliver: SliverList.builder(
                itemCount: guests.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OfflineGuestTile(guest: guests[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.controller.inventory;
    final controller = widget.controller;
    final cachedInventory = inv == null ? controller.cachedInventory : null;
    if (cachedInventory != null) {
      return _buildOfflineInventory(context, cachedInventory);
    }
    final allGuests = inv?.guests ?? <Guest>[];
    final nodes = allGuests.map((guest) => guest.node).toSet().toList()..sort();
    final tags = allGuests.expand((guest) => guest.tags).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final pools =
        allGuests
            .map((guest) => guest.pool)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final canCreateQemu =
        profileId != null &&
        controller.isInventoryWriteSafe &&
        !controller.refreshing &&
        (inv?.nodes.any((node) => node.status == 'online') ?? false);
    final guests = visibleGuests(
      allGuests,
      isFavorite: controller.isGuestFavorite,
      search: query,
      status: filter,
      kind: kind,
      node: nodeFilter,
      tag: tagFilter,
      pool: poolFilter,
      sort: sort,
    );
    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: search,
                          onChanged: (value) =>
                              _manualChange(() => query = value),
                          decoration: const InputDecoration(
                            hintText: 'Search guests, VMID, node, tag, or pool',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Badge.count(
                        count: _sheetFilterCount,
                        isLabelVisible: _sheetFilterCount > 0,
                        child: IconButton.filledTonal(
                          key: const Key('guest-filter-button'),
                          tooltip: 'Filter guests',
                          onPressed: () => _openFilters(
                            context,
                            nodes: nodes,
                            tags: tags,
                            pools: pools,
                          ),
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      ActionChip(
                        key: const Key('guest-create-qemu'),
                        avatar: const Icon(Icons.add_box_outlined, size: 18),
                        label: const Text('Create VM'),
                        onPressed: canCreateQemu
                            ? () => _openQemuCreate(context)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        key: const Key('guest-create-lxc'),
                        avatar: const Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                        ),
                        label: const Text('Create CT'),
                        onPressed: canCreateQemu
                            ? () => _openLxcCreate(context)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(
                          Icons.bookmark_add_outlined,
                          size: 18,
                        ),
                        label: const Text('Save view'),
                        onPressed: profileId == null
                            ? null
                            : () => _saveCurrentView(context),
                      ),
                      for (final view in controller.guestSavedViews) ...[
                        const SizedBox(width: 8),
                        InputChip(
                          label: Text(view.name),
                          selected: activeViewId == view.id,
                          onPressed: () => _applyView(view),
                          onDeleted: profileId == null
                              ? null
                              : () => _deleteView(context, view),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      for (final option in const [
                        ('all', 'All'),
                        ('favorites', 'Favorites'),
                        ('running', 'Running'),
                        ('stopped', 'Stopped'),
                        ('templates', 'Templates'),
                      ]) ...[
                        FilterChip(
                          label: Text(option.$2),
                          selected: filter == option.$1,
                          onSelected: (_) =>
                              _manualChange(() => filter = option.$1),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                if (_sheetFilterCount > 0) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (kind != GuestKindFilter.all)
                          InputChip(
                            label: Text('Type: ${_kindLabel(kind)}'),
                            onDeleted: () =>
                                _manualChange(() => kind = GuestKindFilter.all),
                          ),
                        if (nodeFilter != null)
                          InputChip(
                            label: Text('Node: $nodeFilter'),
                            onDeleted: () =>
                                _manualChange(() => nodeFilter = null),
                          ),
                        if (tagFilter != null)
                          InputChip(
                            label: Text('Tag: $tagFilter'),
                            onDeleted: () =>
                                _manualChange(() => tagFilter = null),
                          ),
                        if (poolFilter != null)
                          InputChip(
                            label: Text('Pool: $poolFilter'),
                            onDeleted: () =>
                                _manualChange(() => poolFilter = null),
                          ),
                        if (sort != GuestSort.favorites)
                          InputChip(
                            label: Text('Sort: ${sort.label}'),
                            onDeleted: () =>
                                _manualChange(() => sort = GuestSort.favorites),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text(
                        filter == 'templates'
                            ? '${guests.length} templates'
                            : '${guests.length} workloads',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        inv == null
                            ? 'No live data'
                            : widget.controller.isInventoryFresh
                            ? 'Live'
                            : 'STALE',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_hasActiveFilters)
                        TextButton(
                          onPressed: _clearFilters,
                          child: const Text('Clear filters'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          if (inv == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Not connected',
                body: 'Refresh or verify the connection to browse workloads.',
                action: FilledButton.tonalIcon(
                  onPressed: widget.controller.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh'),
                ),
              ),
            )
          else if (guests.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No workloads found',
                body:
                    'Try a different search or filter, or check token permissions.',
                action: _hasActiveFilters
                    ? TextButton(
                        onPressed: _clearFilters,
                        child: const Text('Clear filters'),
                      )
                    : null,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GuestTile(
                      guest: guests[index],
                      controller: widget.controller,
                    ),
                  ),
                  childCount: guests.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void _openTaskDetails(
  BuildContext context,
  AppController controller, {
  required String node,
  required String upid,
  required String title,
}) {
  final profileId = controller.active?.id;
  if (profileId == null) return;
  final generation = controller.connectionGeneration;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TaskDetailsPage(
        controller: controller,
        profileId: profileId,
        generation: generation,
        node: node,
        upid: upid,
        title: title,
      ),
    ),
  );
}

class _TasksTab extends StatefulWidget {
  const _TasksTab({super.key, required this.controller});
  final AppController controller;

  @override
  State<_TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<_TasksTab> {
  final search = TextEditingController();
  String query = '';
  String nodeFilter = '';
  ServerTaskStateFilter stateFilter = ServerTaskStateFilter.all;

  bool get _hasActiveFilters =>
      query.isNotEmpty ||
      nodeFilter.isNotEmpty ||
      stateFilter != ServerTaskStateFilter.all;

  void _clearFilters() {
    search.clear();
    setState(() {
      query = '';
      nodeFilter = '';
      stateFilter = ServerTaskStateFilter.all;
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final sessionTasks = controller.tasks;
    final serverTasks = controller.serverTasks;
    final nodes = serverTasks.map((task) => task.node).toSet().toList()..sort();
    final activeNode = nodes.contains(nodeFilter) ? nodeFilter : '';
    final visible = visibleServerTasks(
      serverTasks,
      search: query,
      node: activeNode,
      status: stateFilter,
    );
    final empty =
        sessionTasks.isEmpty &&
        serverTasks.isEmpty &&
        controller.serverTaskMessage == null;
    final running = serverTasks
        .where((task) => task.stateLabel == 'running')
        .length;
    final succeeded = serverTasks
        .where((task) => task.stateLabel == 'succeeded')
        .length;
    final failed = serverTasks
        .where((task) => task.stateLabel == 'failed')
        .length;
    final unknown = serverTasks
        .where((task) => task.stateLabel == 'unknown')
        .length;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (empty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No recent tasks visible',
                body:
                    'Pull to refresh. Task visibility depends on Proxmox permissions.',
                action: FilledButton.tonalIcon(
                  onPressed: controller.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh'),
                ),
              ),
            )
          else ...[
            if (serverTasks.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: _TaskSummaryBar(
                    running: running,
                    succeeded: succeeded,
                    failed: failed,
                    unknown: unknown,
                  ),
                ),
              ),
            if (sessionTasks.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: SectionHeading(
                    title: 'This session',
                    trailing: '${sessionTasks.length} TRACKED',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                sliver: SliverList.builder(
                  itemCount: sessionTasks.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SessionTaskCard(
                      task: sessionTasks[index],
                      controller: controller,
                    ),
                  ),
                ),
              ),
            ],
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                18,
                sessionTasks.isEmpty ? 18 : 22,
                18,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeading(
                      title: 'Recent server tasks',
                      trailing: serverTasks.isEmpty
                          ? ''
                          : '${visible.length} OF ${serverTasks.length} VISIBLE',
                    ),
                    const SizedBox(height: 10),
                    if (controller.serverTaskMessage != null) ...[
                      MessageCard(text: controller.serverTaskMessage!),
                      const SizedBox(height: 10),
                    ],
                    if (serverTasks.isNotEmpty) ...[
                      TextField(
                        key: const Key('task-history-search'),
                        controller: search,
                        onChanged: (value) => setState(() => query = value),
                        decoration: const InputDecoration(
                          hintText: 'Search recent tasks, node, or resource',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Semantics(
                            label: 'Filter recent tasks by node',
                            child: DropdownButton<String>(
                              key: const Key('task-node-filter'),
                              value: activeNode,
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text('All nodes'),
                                ),
                                for (final node in nodes)
                                  DropdownMenuItem(
                                    value: node,
                                    child: Text(node),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => nodeFilter = value ?? ''),
                            ),
                          ),
                          Semantics(
                            label: 'Filter recent tasks by state',
                            child: DropdownButton<ServerTaskStateFilter>(
                              key: const Key('task-state-filter'),
                              value: stateFilter,
                              items: const [
                                DropdownMenuItem(
                                  value: ServerTaskStateFilter.all,
                                  child: Text('All states'),
                                ),
                                DropdownMenuItem(
                                  value: ServerTaskStateFilter.running,
                                  child: Text('Running'),
                                ),
                                DropdownMenuItem(
                                  value: ServerTaskStateFilter.succeeded,
                                  child: Text('Succeeded'),
                                ),
                                DropdownMenuItem(
                                  value: ServerTaskStateFilter.failed,
                                  child: Text('Failed'),
                                ),
                                DropdownMenuItem(
                                  value: ServerTaskStateFilter.unknown,
                                  child: Text('Unknown'),
                                ),
                              ],
                              onChanged: (value) => setState(
                                () => stateFilter =
                                    value ?? ServerTaskStateFilter.all,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
            if (serverTasks.isEmpty && controller.serverTaskMessage == null)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 30),
                sliver: SliverToBoxAdapter(
                  child: MessageCard(
                    text: 'No recent server tasks are visible to this token.',
                  ),
                ),
              )
            else if (serverTasks.isNotEmpty && visible.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
                sliver: SliverToBoxAdapter(
                  child: MessageCard(
                    text:
                        'No recent tasks match these filters. Clear search or choose another state or node.',
                    action: _hasActiveFilters
                        ? TextButton(
                            onPressed: _clearFilters,
                            child: const Text('Clear filters'),
                          )
                        : null,
                  ),
                ),
              )
            else if (visible.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ServerTaskCard(
                      task: visible[index],
                      controller: controller,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TaskSummaryBar extends StatelessWidget {
  const _TaskSummaryBar({
    required this.running,
    required this.succeeded,
    required this.failed,
    required this.unknown,
  });

  final int running;
  final int succeeded;
  final int failed;
  final int unknown;

  @override
  Widget build(BuildContext context) {
    final status =
        Theme.of(context).extension<VirtHelmStatusColors>() ??
        const VirtHelmStatusColors(
          positive: Color(0xFF087A64),
          warning: Color(0xFF9A5A12),
          error: Color(0xFFB3261E),
          neutral: Color(0xFF5F6368),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TaskCount(
              label: 'Running',
              count: running,
              color: Theme.of(context).colorScheme.primary,
            ),
            _TaskCount(
              label: 'Succeeded',
              count: succeeded,
              color: status.positive,
            ),
            _TaskCount(label: 'Failed', count: failed, color: status.error),
            _TaskCount(label: 'Unknown', count: unknown, color: status.neutral),
          ],
        ),
      ),
    );
  }
}

class _TaskCount extends StatelessWidget {
  const _TaskCount({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _SessionTaskCard extends StatelessWidget {
  const _SessionTaskCard({required this.task, required this.controller});
  final TrackedTask task;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final finished = task.outcome != OperationOutcome.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  finished
                      ? Icons.task_alt_rounded
                      : Icons.pending_actions_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusChip(status: task.outcome.name),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${task.node} • ${formatAge(task.startedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (task.detail != null) ...[
              const SizedBox(height: 6),
              Text(task.detail!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 6),
            Text(
              'UPID: ${task.upid}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _openTaskDetails(
                context,
                controller,
                node: task.node,
                upid: task.upid,
                title: task.title,
              ),
              icon: const Icon(Icons.list_alt_outlined),
              label: const Text('View details'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerTaskCard extends StatelessWidget {
  const _ServerTaskCard({required this.task, required this.controller});
  final RecentServerTask task;
  final AppController controller;

  IconData get _stateIcon => switch (task.stateLabel) {
    'running' => Icons.sync_rounded,
    'succeeded' => Icons.task_alt_rounded,
    'failed' => Icons.error_outline_rounded,
    _ => Icons.help_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final started = task.startedAt;
    final resource = task.resourceId == null || task.resourceId!.isEmpty
        ? ''
        : ' • ${task.resourceId!}';
    final scheme = Theme.of(context).colorScheme;
    void openDetails() => _openTaskDetails(
      context,
      controller,
      node: task.node,
      upid: task.upid,
      title: task.operationLabel,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openDetails,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              Icon(_stateIcon, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${task.operationLabel}$resource',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusChip(status: task.stateLabel),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${task.node} • '
                      '${started == null ? 'time unavailable' : formatAge(started)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (task.exitStatus != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Exit: ${task.exitStatus!}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'UPID: ${task.upid}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.controller});
  final AppController controller;

  Future<void> _updateTheme(
    BuildContext context,
    AppThemePreference value,
  ) async {
    try {
      await controller.setThemePreference(value);
    } catch (_) {
      if (context.mounted) _showPreferenceError(context);
    }
  }

  Future<void> _updateRefresh(
    BuildContext context,
    AutoRefreshPreference value,
  ) async {
    try {
      await controller.setAutoRefreshPreference(value);
    } catch (_) {
      if (context.mounted) _showPreferenceError(context);
    }
  }

  Future<void> _updateNodeMetrics(BuildContext context, bool value) async {
    try {
      await controller.setShowNodeMetrics(value);
    } catch (_) {
      if (context.mounted) _showPreferenceError(context);
    }
  }

  Future<void> _updateHighContrast(BuildContext context, bool value) async {
    try {
      await controller.setHighContrast(value);
    } catch (_) {
      if (context.mounted) _showPreferenceError(context);
    }
  }

  Future<void> _updateReduceMotion(BuildContext context, bool value) async {
    try {
      await controller.setReduceMotion(value);
    } catch (_) {
      if (context.mounted) _showPreferenceError(context);
    }
  }

  Future<void> _updateOfflineOverview(BuildContext context, bool value) async {
    try {
      await controller.setOfflineOverviewEnabled(value);
    } catch (_) {
      if (context.mounted) _showPreferenceError(context);
    }
  }

  Future<void> _updateOfflineInventory(BuildContext context, bool value) async {
    try {
      await controller.setOfflineInventoryEnabled(value);
    } catch (_) {
      if (context.mounted) _showPreferenceError(context);
    }
  }

  Future<void> _updateForegroundNotificationPolicy(
    BuildContext context,
    ForegroundNotificationPolicy policy,
  ) async {
    final profileId = controller.active?.id;
    if (profileId == null) return;
    try {
      final accepted = await controller.setForegroundNotificationPolicy(
        policy,
        expectedProfileId: profileId,
      );
      if (!accepted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications remain off. Android notification permission was not granted.',
            ),
          ),
        );
      }
    } on FormatException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quiet-hour start and end times must be different.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) _showPreferenceError(context);
    }
  }

  Future<void> _updateNotificationLockScreenPrivacy(
    BuildContext context,
    IncidentNotificationLockScreenPrivacy value,
  ) async {
    try {
      final applied = await controller.setNotificationLockScreenPrivacy(value);
      if (!applied && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not apply the Android lock-screen privacy setting.',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) _showPreferenceError(context);
    }
  }

  Future<void> _pickQuietTime(
    BuildContext context, {
    required bool start,
  }) async {
    final policy = controller.foregroundNotificationPolicy;
    final minute = start ? policy.quietStartMinute : policy.quietEndMinute;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      helpText: start ? 'Quiet hours start' : 'Quiet hours end',
    );
    if (selected == null || !context.mounted) return;
    final nextMinute = selected.hour * 60 + selected.minute;
    final next = start
        ? policy.copyWith(quietStartMinute: nextMinute)
        : policy.copyWith(quietEndMinute: nextMinute);
    await _updateForegroundNotificationPolicy(context, next);
  }

  List<int> _cooldownOptions(int current) {
    final values = <int>{0, 15, 30, 60, 120, 240, current}.toList()..sort();
    return values;
  }

  String _cooldownLabel(int minutes) {
    if (minutes == 0) return 'No cooldown';
    if (minutes < 60) return '$minutes minutes';
    if (minutes == 60) return '1 hour';
    if (minutes % 60 == 0) return '${minutes ~/ 60} hours';
    return '$minutes minutes';
  }

  String _formatMinute(BuildContext context, int minute) =>
      MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay(hour: minute ~/ 60, minute: minute % 60));

  void _showPreferenceError(BuildContext context) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save local setting.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('settings-list'),
    padding: const EdgeInsets.all(18),
    children: [
      Text('Connections', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Card(
        child: ListTile(
          key: const Key('manage-connections'),
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Manage connections'),
          subtitle: Text(
            controller.profiles.isEmpty
                ? 'Add and verify a Proxmox VE connection.'
                : '${controller.profiles.length} saved • add, test, edit, switch or remove',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ConnectionsPage(controller: controller),
            ),
          ),
        ),
      ),
      const SizedBox(height: 28),
      Text(
        'Display & accessibility',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Appearance'),
              DropdownButton<AppThemePreference>(
                key: const Key('theme-preference'),
                value: controller.themePreference,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: AppThemePreference.system,
                    child: Text('Device theme'),
                  ),
                  DropdownMenuItem(
                    value: AppThemePreference.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(
                    value: AppThemePreference.dark,
                    child: Text('Dark'),
                  ),
                  DropdownMenuItem(
                    value: AppThemePreference.amoled,
                    child: Text('AMOLED black'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    unawaited(_updateTheme(context, value));
                  }
                },
              ),
              const Divider(),
              SwitchListTile(
                key: const Key('high-contrast-preference'),
                contentPadding: EdgeInsets.zero,
                title: const Text('High contrast'),
                subtitle: const Text(
                  'Strengthen borders and semantic status contrast. '
                  'Android high-contrast mode is also respected.',
                ),
                value: controller.highContrast,
                onChanged: (value) =>
                    unawaited(_updateHighContrast(context, value)),
              ),
              const Divider(),
              SwitchListTile(
                key: const Key('reduce-motion-preference'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Reduce motion'),
                subtitle: const Text(
                  'Minimize theme and interface animation. '
                  'Android remove-animations is also respected.',
                ),
                value: controller.reduceMotion,
                onChanged: (value) =>
                    unawaited(_updateReduceMotion(context, value)),
              ),
              const Divider(),
              const Text('Automatic read refresh'),
              DropdownButton<AutoRefreshPreference>(
                key: const Key('refresh-preference'),
                value: controller.autoRefreshPreference,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: AutoRefreshPreference.off,
                    child: Text('Manual only'),
                  ),
                  DropdownMenuItem(
                    value: AutoRefreshPreference.every30Seconds,
                    child: Text('Every 30 seconds'),
                  ),
                  DropdownMenuItem(
                    value: AutoRefreshPreference.every60Seconds,
                    child: Text('Every minute'),
                  ),
                  DropdownMenuItem(
                    value: AutoRefreshPreference.every120Seconds,
                    child: Text('Every 2 minutes'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    unawaited(_updateRefresh(context, value));
                  }
                },
              ),
              const Text(
                'Refreshes reads only while the app is foregrounded. '
                'Pauses after inventory/authentication errors; no background '
                'monitoring or automatic guest actions.',
              ),
              const Divider(),
              SwitchListTile(
                key: const Key('node-metrics-preference'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show node metrics'),
                subtitle: const Text('CPU, memory and uptime on Home.'),
                value: controller.showNodeMetrics,
                onChanged: (value) =>
                    unawaited(_updateNodeMetrics(context, value)),
              ),
              const Divider(),
              SwitchListTile(
                key: const Key('offline-overview-preference'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep offline overview counts'),
                subtitle: const Text(
                  'Optional per-connection storage of timestamped node and '
                  'guest counts only. No names, VMIDs or task logs. '
                  'Turn off to erase this connection’s cached counts.',
                ),
                value: controller.offlineOverviewEnabled,
                onChanged: (value) =>
                    unawaited(_updateOfflineOverview(context, value)),
              ),
              const Divider(),
              SwitchListTile(
                key: const Key('offline-inventory-preference'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep offline inventory list'),
                subtitle: const Text(
                  'Separate opt-in: stores node names plus guest name, VMID, '
                  'type, node and last-known status for up to 24 hours. '
                  'No metrics, tags, pools, storage/config/task data or credentials. '
                  'Cached entries are display-only; turn off to erase them.',
                ),
                value: controller.offlineInventoryEnabled,
                onChanged: (value) =>
                    unawaited(_updateOfflineInventory(context, value)),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 28),
      Text(
        'Incident notifications',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Lock-screen privacy'),
              DropdownButton<IncidentNotificationLockScreenPrivacy>(
                key: const Key('incident-notification-lock-screen-privacy'),
                value: controller.notificationLockScreenPrivacy,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: IncidentNotificationLockScreenPrivacy.hidden,
                    child: Text('Hide on secure lock screen'),
                  ),
                  DropdownMenuItem(
                    value: IncidentNotificationLockScreenPrivacy.generic,
                    child: Text('Show generic VirtHelm alert'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    unawaited(
                      _updateNotificationLockScreenPrivacy(context, value),
                    );
                  }
                },
              ),
              Text(
                controller.notificationLockScreenPrivacy ==
                        IncidentNotificationLockScreenPrivacy.hidden
                    ? 'Default: Android is asked to reveal no part of VirtHelm incident notifications on a secure lock screen.'
                    : 'Only the generic VirtHelm incident title/icon may appear; infrastructure names, VMIDs, task IDs and logs remain excluded.',
              ),
              const Text(
                'This device setting applies to both foreground and scheduled incident notifications. Android system/channel settings can further restrict lock-screen visibility.',
              ),
              const Divider(),
              SwitchListTile(
                key: const Key('foreground-incident-notifications'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Foreground incident notifications'),
                subtitle: const Text(
                  'Opt in to a generic Android notification when a new '
                  'incident occurrence is observed while VirtHelm is open.',
                ),
                value: controller.foregroundNotificationPolicy.enabled,
                onChanged: (value) => unawaited(
                  _updateForegroundNotificationPolicy(
                    context,
                    controller.foregroundNotificationPolicy.copyWith(
                      enabled: value,
                    ),
                  ),
                ),
              ),
              if (controller.foregroundNotificationPolicy.enabled) ...[
                const Divider(),
                SwitchListTile(
                  key: const Key('incident-notification-quiet-hours'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Quiet hours'),
                  subtitle: const Text(
                    'Suppress Android delivery only. Incidents remain visible '
                    'and continue to count toward current health.',
                  ),
                  value:
                      controller.foregroundNotificationPolicy.quietHoursEnabled,
                  onChanged: (value) => unawaited(
                    _updateForegroundNotificationPolicy(
                      context,
                      controller.foregroundNotificationPolicy.copyWith(
                        quietHoursEnabled: value,
                      ),
                    ),
                  ),
                ),
                if (controller
                    .foregroundNotificationPolicy
                    .quietHoursEnabled) ...[
                  ListTile(
                    key: const Key('incident-notification-quiet-start'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Starts'),
                    trailing: Text(
                      _formatMinute(
                        context,
                        controller
                            .foregroundNotificationPolicy
                            .quietStartMinute,
                      ),
                    ),
                    onTap: () =>
                        unawaited(_pickQuietTime(context, start: true)),
                  ),
                  ListTile(
                    key: const Key('incident-notification-quiet-end'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ends'),
                    trailing: Text(
                      _formatMinute(
                        context,
                        controller.foregroundNotificationPolicy.quietEndMinute,
                      ),
                    ),
                    onTap: () =>
                        unawaited(_pickQuietTime(context, start: false)),
                  ),
                ],
                const Divider(),
                const Text('Notification cooldown'),
                DropdownButton<int>(
                  key: const Key('incident-notification-cooldown'),
                  value:
                      controller.foregroundNotificationPolicy.cooldownMinutes,
                  isExpanded: true,
                  items:
                      _cooldownOptions(
                            controller
                                .foregroundNotificationPolicy
                                .cooldownMinutes,
                          )
                          .map(
                            (minutes) => DropdownMenuItem<int>(
                              value: minutes,
                              child: Text(_cooldownLabel(minutes)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      unawaited(
                        _updateForegroundNotificationPolicy(
                          context,
                          controller.foregroundNotificationPolicy.copyWith(
                            cooldownMinutes: value,
                          ),
                        ),
                      );
                    }
                  },
                ),
                const Text(
                  'Quiet hours use this device’s local time. Suppressed '
                  'notifications are not queued for later delivery.',
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Notification text is generic and excludes profile names, '
                'infrastructure names, VMIDs, task IDs and task logs. '
                'Tapping an incident notification opens the Incidents tab only; '
                'the Android intent carries no profile or resource selector. '
                'Scheduled monitoring, when enabled for a connection, uses the same lock-screen privacy setting.',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 28),
      Text('Security', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Protected by design',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'HTTPS certificate verification by default (per-connection insecure opt-in available) • encrypted token storage • no automatic write retries • no analytics backend',
              ),
              SizedBox(height: 12),
              Text(
                'Preview build: no console, unattended guest actions, critical-paging guarantee, or automatic write retries. Scheduled checks are best-effort and inexact. Use VPN for remote access.',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 28),
      Text('About', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text('$virthelmDisplayName $virthelmDisplayVersion'),
              subtitle: const Text(
                'Independent, unofficial Proxmox VE client. '
                'Preview build for Android phones.',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Open-source licenses'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showLicensePage(
                context: context,
                applicationName: virthelmDisplayName,
                applicationVersion: virthelmDisplayVersion,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _GuestFilterSelection {
  const _GuestFilterSelection({
    required this.kind,
    required this.node,
    required this.tag,
    required this.pool,
    required this.sort,
  });

  final GuestKindFilter kind;
  final String? node;
  final String? tag;
  final String? pool;
  final GuestSort sort;
}

class _GuestFilterSheet extends StatefulWidget {
  const _GuestFilterSheet({
    required this.kind,
    required this.node,
    required this.tag,
    required this.pool,
    required this.sort,
    required this.nodes,
    required this.tags,
    required this.pools,
  });

  final GuestKindFilter kind;
  final String? node;
  final String? tag;
  final String? pool;
  final GuestSort sort;
  final List<String> nodes;
  final List<String> tags;
  final List<String> pools;

  @override
  State<_GuestFilterSheet> createState() => _GuestFilterSheetState();
}

class _GuestFilterSheetState extends State<_GuestFilterSheet> {
  late GuestKindFilter kind;
  String? node;
  String? tag;
  String? pool;
  late GuestSort sort;

  @override
  void initState() {
    super.initState();
    kind = widget.kind;
    node = widget.node;
    tag = widget.tag;
    pool = widget.pool;
    sort = widget.sort;
  }

  void _reset() {
    setState(() {
      kind = GuestKindFilter.all;
      node = null;
      tag = null;
      pool = null;
      sort = GuestSort.favorites;
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter guests',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(onPressed: _reset, child: const Text('Reset')),
              ],
            ),
            Text('Type', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in const [
                  (GuestKindFilter.all, 'Any type'),
                  (GuestKindFilter.qemu, 'VMs'),
                  (GuestKindFilter.lxc, 'Containers'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: kind == option.$1,
                    onSelected: (_) => setState(() => kind = option.$1),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Node', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const Key('guest-filter-node-all'),
                  label: const Text('All nodes'),
                  selected: node == null,
                  onSelected: (_) => setState(() => node = null),
                ),
                for (final value in widget.nodes)
                  ChoiceChip(
                    key: ValueKey('guest-filter-node-$value'),
                    label: Text(value),
                    selected: node == value,
                    onSelected: (_) => setState(() => node = value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Tag', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const Key('guest-filter-tag-all'),
                  label: const Text('All tags'),
                  selected: tag == null,
                  onSelected: (_) => setState(() => tag = null),
                ),
                for (final value in widget.tags)
                  ChoiceChip(
                    key: ValueKey('guest-filter-tag-$value'),
                    label: Text(value),
                    selected: tag == value,
                    onSelected: (_) => setState(() => tag = value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Pool', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const Key('guest-filter-pool-all'),
                  label: const Text('All pools'),
                  selected: pool == null,
                  onSelected: (_) => setState(() => pool = null),
                ),
                for (final value in widget.pools)
                  ChoiceChip(
                    key: ValueKey('guest-filter-pool-$value'),
                    label: Text(value),
                    selected: pool == value,
                    onSelected: (_) => setState(() => pool = value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Sort', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final value in GuestSort.values)
                  ChoiceChip(
                    key: ValueKey('guest-filter-sort-${value.name}'),
                    label: Text(value.label),
                    selected: sort == value,
                    onSelected: (_) => setState(() => sort = value),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('guest-filter-apply'),
              onPressed: () => Navigator.pop(
                context,
                _GuestFilterSelection(
                  kind: kind,
                  node: node,
                  tag: tag,
                  pool: pool,
                  sort: sort,
                ),
              ),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Apply filters'),
            ),
          ],
        ),
      ),
    ),
  );
}
