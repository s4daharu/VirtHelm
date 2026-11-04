import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/app_preferences.dart';
import '../core/guest_list_filter.dart';
import '../core/guest_saved_view.dart';
import '../core/models.dart';
import 'connect_page.dart';
import 'guest_page.dart';
import 'theme.dart';
import 'task_details_page.dart';
import 'tls_warning.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final profile = controller.active;
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
                    '${profile?.name ?? 'No connection'}'
                    '${profile?.lastServerVersion == null ? '' : ' • PVE ${profile!.lastServerVersion}'}'
                    '${profile?.allowInvalidCertificates == true ? ' • TLS UNVERIFIED' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          if (profile?.allowInvalidCertificates == true) const TlsWarning(),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: [
                _OverviewTab(
                  controller: controller,
                  onOpenGuests: () => setState(() => selectedIndex = 1),
                ),
                _GuestsTab(controller: controller),
                _TasksTab(controller: controller),
                _SettingsTab(controller: controller),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) => setState(() => selectedIndex = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns_rounded),
            label: 'Guests',
          ),
          NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline_rounded),
            label: 'Tasks',
          ),
          NavigationDestination(
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
  const _OverviewTab({required this.controller, required this.onOpenGuests});
  final AppController controller;
  final VoidCallback onOpenGuests;

  @override
  Widget build(BuildContext context) {
    final inv = controller.inventory;
    final scheme = Theme.of(context).colorScheme;
    final countRunning = inv?.guests.where((g) => g.isRunning).length ?? 0;
    final countStopped = inv?.guests.where((g) => g.isStopped).length ?? 0;
    final nodeOnline =
        inv?.nodes.where((n) => n.status == 'online').length ?? 0;
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
                      ? 'Waiting for live inventory'
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
          if (controller.inventoryWarning != null) ...[
            const SizedBox(height: 14),
            _MessageCard(text: controller.inventoryWarning!),
          ],
          const SizedBox(height: 24),
          _SectionHeading(
            title: 'Infrastructure',
            trailing: 'CURRENT SNAPSHOT',
          ),
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
                value: inv == null ? '—' : '$nodeOnline / ${inv.nodes.length}',
                icon: Icons.hub_outlined,
                color: const Color(0xFF20BFAF),
              ),
              _MetricCard(
                title: 'Guests total',
                value: inv == null ? '—' : '${inv.guests.length}',
                icon: Icons.computer_outlined,
                color: const Color(0xFF6498F8),
              ),
              _MetricCard(
                title: 'Running',
                value: inv == null ? '—' : '$countRunning',
                icon: Icons.play_circle_outline,
                color: const Color(0xFF20BFAF),
              ),
              _MetricCard(
                title: 'Stopped',
                value: inv == null ? '—' : '$countStopped',
                icon: Icons.pause_circle_outline,
                color: const Color(0xFFE9A95D),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeading(
            title: 'Nodes',
            trailing: inv == null ? '' : '${inv.nodes.length} FOUND',
          ),
          const SizedBox(height: 12),
          if (inv == null)
            const _MessageCard(
              text: 'Connect to load node health. Pull to refresh.',
            )
          else if (inv.nodes.isEmpty)
            const _MessageCard(
              text: 'No nodes are visible to this token. Review permissions.',
            )
          else
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
                ),
              ),
              const SizedBox(height: 8),
            ],

          const SizedBox(height: 22),
          _SectionHeading(
            title: 'Storage',
            trailing: controller.storages.isEmpty
                ? ''
                : '${controller.storages.length} VISIBLE',
          ),
          const SizedBox(height: 12),
          if (controller.storageMessage != null) ...[
            _MessageCard(text: controller.storageMessage!),
            const SizedBox(height: 8),
          ],
          if (inv != null &&
              controller.storages.isEmpty &&
              controller.storageMessage == null)
            const _MessageCard(
              text: 'No storage pools are visible to this token.',
            )
          else
            for (final storage in controller.storages) ...[
              _StorageTile(storage: storage),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Workloads',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
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
            ],
          if (inv != null && inv.guests.isEmpty)
            const _MessageCard(
              text: 'No QEMU VMs or LXC containers are visible.',
            ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.trailing});
  final String title;
  final String trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      Text(
        trailing,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
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
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
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
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Text(text)),
  );
}

class _StorageTile extends StatelessWidget {
  const _StorageTile({required this.storage});
  final StoragePool storage;

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
      ),
    );
  }
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
          '${guest.kind.toUpperCase()} • ${guest.vmid} • ${guest.node}',
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
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GuestPage(
                    controller: controller,
                    guest: guest,
                    profileId: profileId,
                  ),
                ),
              ),
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
      sort = view.sort;
      activeViewId = view.id;
    });
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

  @override
  Widget build(BuildContext context) {
    final inv = widget.controller.inventory;
    final controller = widget.controller;
    final allGuests = inv?.guests ?? <Guest>[];
    final nodes = allGuests.map((guest) => guest.node).toSet().toList()..sort();
    final guests = visibleGuests(
      allGuests,
      isFavorite: controller.isGuestFavorite,
      search: query,
      status: filter,
      kind: kind,
      node: nodeFilter,
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
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                  child: TextField(
                    controller: search,
                    onChanged: (value) => _manualChange(() => query = value),
                    decoration: const InputDecoration(
                      hintText: 'Search guests, VMID, or node',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
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
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      for (final option in const [
                        (GuestKindFilter.all, 'Any type'),
                        (GuestKindFilter.qemu, 'VMs'),
                        (GuestKindFilter.lxc, 'Containers'),
                      ]) ...[
                        FilterChip(
                          label: Text(option.$2),
                          selected: kind == option.$1,
                          onSelected: (_) =>
                              _manualChange(() => kind = option.$1),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'Filter by node',
                        onSelected: (value) => _manualChange(
                          () => nodeFilter = value == '__all' ? null : value,
                        ),
                        itemBuilder: (_) => [
                          CheckedPopupMenuItem<String>(
                            value: '__all',
                            checked: nodeFilter == null,
                            child: const Text('All nodes'),
                          ),
                          for (final node in nodes)
                            CheckedPopupMenuItem<String>(
                              value: node,
                              checked: nodeFilter == node,
                              child: Text(node),
                            ),
                        ],
                        child: Chip(
                          avatar: const Icon(Icons.hub_outlined, size: 18),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: Text(
                              nodeFilter == null
                                  ? 'All nodes'
                                  : 'Node: $nodeFilter',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      PopupMenuButton<GuestSort>(
                        tooltip: 'Sort guests',
                        onSelected: (value) =>
                            _manualChange(() => sort = value),
                        itemBuilder: (_) => [
                          for (final option in GuestSort.values)
                            CheckedPopupMenuItem<GuestSort>(
                              value: option,
                              checked: sort == option,
                              child: Text(option.label),
                            ),
                        ],
                        child: Chip(
                          avatar: const Icon(Icons.sort_rounded, size: 18),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 170),
                            child: Text(
                              'Sort: ${sort.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text(
                        '${guests.length} workloads',
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
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          if (inv == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Not connected',
                body: 'Refresh or verify the connection to browse workloads.',
              ),
            )
          else if (guests.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No workloads found',
                body:
                    'Try a different search or filter, or check token permissions.',
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

class _TasksTab extends StatelessWidget {
  const _TasksTab({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final sessionTasks = controller.tasks;
    final serverTasks = controller.serverTasks;
    final empty =
        sessionTasks.isEmpty &&
        serverTasks.isEmpty &&
        controller.serverTaskMessage == null;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          if (empty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No recent tasks visible',
              body:
                  'Pull to refresh. Task visibility depends on Proxmox permissions.',
            ),
          if (!empty && sessionTasks.isNotEmpty) ...[
            _SectionHeading(
              title: 'This session',
              trailing: '${sessionTasks.length} TRACKED',
            ),
            const SizedBox(height: 10),
            for (final task in sessionTasks) ...[
              _SessionTaskCard(task: task, controller: controller),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
          ],
          if (!empty)
            _SectionHeading(
              title: 'Recent server tasks',
              trailing: serverTasks.isEmpty
                  ? ''
                  : '${serverTasks.length} VISIBLE',
            ),
          if (!empty) const SizedBox(height: 10),
          if (!empty && controller.serverTaskMessage != null) ...[
            _MessageCard(text: controller.serverTaskMessage!),
            const SizedBox(height: 10),
          ],
          if (!empty &&
              serverTasks.isEmpty &&
              controller.serverTaskMessage == null)
            const _MessageCard(
              text: 'No recent server tasks are visible to this token.',
            )
          else
            for (final task in serverTasks) ...[
              _ServerTaskCard(task: task, controller: controller),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
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

  @override
  Widget build(BuildContext context) {
    final started = task.startedAt;
    final resource = task.resourceId == null || task.resourceId!.isEmpty
        ? ''
        : ' • ${task.resourceId!}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${task.operationLabel}$resource',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusChip(status: task.stateLabel),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${task.node} • '
              '${started == null ? 'time unavailable' : formatAge(started)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (task.exitStatus != null) ...[
              const SizedBox(height: 6),
              Text(
                'Exit: ${task.exitStatus!}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'UPID: ${task.upid}',
              maxLines: 1,
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
                title: task.operationLabel,
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

  void _showPreferenceError(BuildContext context) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save local setting.')),
      );
    }
  }

  Future<void> _remove(BuildContext context, ConnectionProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove connection?'),
        content: Text(
          'Delete ${profile.name} and its locally stored API token. This will not revoke the token on the Proxmox server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteProfile(profile.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove stored connection.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text('Connections', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      for (final profile in controller.profiles) ...[
        Card(
          child: ListTile(
            leading: Icon(
              profile.id == controller.active?.id
                  ? Icons.check_circle_rounded
                  : Icons.dns_outlined,
            ),
            title: Text(profile.name),
            subtitle: Text(
              '${profile.endpoint}\n'
              '${profile.lastServerVersion == null ? 'Server version not observed' : 'PVE ${profile.lastServerVersion} (last observed)'}\n'
              '${profile.allowInvalidCertificates ? 'INSECURE: certificate verification disabled' : 'Certificate verification enabled'}',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => unawaited(controller.activate(profile)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit ${profile.name}',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ConnectPage(controller: controller, profile: profile),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Remove ${profile.name}',
                  onPressed: () => _remove(context, profile),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ConnectPage(controller: controller),
          ),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add connection'),
      ),
      const SizedBox(height: 28),
      Text('Display & refresh', style: Theme.of(context).textTheme.titleLarge),
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
                ],
                onChanged: (value) {
                  if (value != null) {
                    unawaited(_updateTheme(context, value));
                  }
                },
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
                'Version 0.1: No console, background monitoring, or guest deletion. Use VPN for remote access.',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 26),
      Text('VirtHelm 0.1.0', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(
        'Independent, unofficial Proxmox VE client',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
