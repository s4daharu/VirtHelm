import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/device_connectivity.dart';
import '../core/incident_center.dart';
import '../core/models.dart';
import 'alert_rules_page.dart';
import 'guest_page.dart';
import 'node_page.dart';
import 'storage_page.dart';
import 'task_details_page.dart';
import 'theme.dart';

enum _IncidentFilter { all, critical, warning }

class IncidentCenterTab extends StatefulWidget {
  const IncidentCenterTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<IncidentCenterTab> createState() => _IncidentCenterTabState();
}

class _IncidentCenterTabState extends State<IncidentCenterTab> {
  _IncidentFilter filter = _IncidentFilter.all;

  List<CockpitIncident> _visible(List<CockpitIncident> incidents) {
    return switch (filter) {
      _IncidentFilter.all => incidents,
      _IncidentFilter.critical =>
        incidents
            .where(
              (incident) =>
                  incident.severity == CockpitIncidentSeverity.critical,
            )
            .toList(growable: false),
      _IncidentFilter.warning =>
        incidents
            .where(
              (incident) =>
                  incident.severity == CockpitIncidentSeverity.warning,
            )
            .toList(growable: false),
    };
  }

  void _openIncident(BuildContext context, CockpitIncident incident) {
    final profileId = widget.controller.active?.id;
    if (profileId == null) return;
    final generation = widget.controller.connectionGeneration;
    final upid = incident.taskUpid;
    final nodeName = incident.node;
    final guestVmid = incident.guestVmid;
    final guestKind = incident.guestKind;
    if (guestVmid != null && guestKind != null && nodeName != null) {
      final inventory = widget.controller.inventory;
      if (inventory == null) return;
      final matches = inventory.guests.where(
        (guest) =>
            guest.node == nodeName &&
            guest.kind == guestKind &&
            guest.vmid == guestVmid,
      );
      if (matches.length != 1) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GuestPage(
            controller: widget.controller,
            guest: matches.single,
            profileId: profileId,
            generation: generation,
          ),
        ),
      );
      return;
    }

    final storageId = incident.storageId;
    if (storageId != null && nodeName != null) {
      final matches = widget.controller.storages.where(
        (storage) => storage.node == nodeName && storage.id == storageId,
      );
      if (matches.length != 1) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StoragePage(
            controller: widget.controller,
            storage: matches.single,
            profileId: profileId,
            generation: generation,
          ),
        ),
      );
      return;
    }

    if (upid != null && nodeName != null) {
      final known =
          widget.controller.tasks.any(
            (task) => task.node == nodeName && task.upid == upid,
          ) ||
          widget.controller.serverTasks.any(
            (task) => task.node == nodeName && task.upid == upid,
          );
      if (!known) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TaskDetailsPage(
            controller: widget.controller,
            profileId: profileId,
            generation: generation,
            node: nodeName,
            upid: upid,
            title: incident.taskTitle ?? incident.title,
          ),
        ),
      );
      return;
    }

    if (nodeName == null) return;
    final inventory = widget.controller.inventory;
    if (inventory == null) return;
    final matches = inventory.nodes.where((node) => node.name == nodeName);
    if (matches.length != 1) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NodePage(
          controller: widget.controller,
          node: matches.single,
          profileId: profileId,
          generation: generation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final incidents = controller.incidents;
    final visible = _visible(incidents);
    final stale =
        controller.active != null &&
        (!controller.isInventoryFresh ||
            controller.deviceNetworkState == DeviceNetworkState.unavailable);
    final taskCoverageIncomplete = controller.serverTaskMessage != null;

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const Key('incident-inbox-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Incident inbox',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Badge.count(
                count: controller.thresholdAlertRules.length,
                isLabelVisible: controller.thresholdAlertRules.isNotEmpty,
                child: IconButton(
                  key: const Key('manage-threshold-rules'),
                  tooltip: 'Manage threshold rules',
                  onPressed: controller.active == null
                      ? null
                      : () {
                          final profileId = controller.active!.id;
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ForegroundThresholdAlertRulesPage(
                                    controller: controller,
                                    profileId: profileId,
                                    generation:
                                        controller.connectionGeneration,
                                  ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
              const SizedBox(width: 6),
              Badge.count(
                count: incidents.length,
                isLabelVisible: incidents.isNotEmpty,
                child: const Icon(Icons.notifications_active_outlined),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Foreground-only signals from the current connection. '
            'Threshold rules are profile-scoped local metadata; incidents '
            'still have no persisted history, background checks, or Android '
            'notifications.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (stale) ...[
            const SizedBox(height: 14),
            const _IncidentMessageCard(
              key: Key('incident-stale-warning'),
              text:
                  'INCIDENT DATA MAY BE STALE • Retained incidents are not '
                  'resolved while live inventory is unavailable. Refresh a '
                  'clean authenticated connection to confirm recovery.',
            ),
          ],
          if (taskCoverageIncomplete) ...[
            const SizedBox(height: 10),
            _IncidentMessageCard(
              key: const Key('incident-task-coverage-warning'),
              text:
                  'Task incident coverage is incomplete. '
                  '${controller.serverTaskMessage}',
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: filter == _IncidentFilter.all,
                onSelected: (_) => setState(() => filter = _IncidentFilter.all),
              ),
              ChoiceChip(
                label: const Text('Critical'),
                selected: filter == _IncidentFilter.critical,
                onSelected: (_) =>
                    setState(() => filter = _IncidentFilter.critical),
              ),
              ChoiceChip(
                label: const Text('Warnings'),
                selected: filter == _IncidentFilter.warning,
                onSelected: (_) =>
                    setState(() => filter = _IncidentFilter.warning),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (controller.active == null)
            const EmptyState(
              icon: Icons.notifications_off_outlined,
              title: 'No active connection',
              body: 'Open a connection to evaluate foreground incidents.',
            )
          else if (visible.isEmpty && incidents.isNotEmpty)
            const EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'No incidents in this filter',
              body: 'Choose another severity to see retained incidents.',
            )
          else if (incidents.isEmpty && (stale || taskCoverageIncomplete))
            const EmptyState(
              icon: Icons.help_outline_rounded,
              title: 'Health cannot be confirmed',
              body:
                  'No retained incidents are visible, but one or more live '
                  'sources are unavailable or incomplete.',
            )
          else if (incidents.isEmpty)
            const EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'No current incidents',
              body:
                  'The current foreground inventory and visible recent task '
                  'history contain no node-state problems or failed tasks.',
            )
          else
            for (final incident in visible) ...[
              _IncidentCard(
                incident: incident,
                onTap: () => _openIncident(context, incident),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _IncidentMessageCard extends StatelessWidget {
  const _IncidentMessageCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident, required this.onTap});

  final CockpitIncident incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final critical = incident.severity == CockpitIncidentSeverity.critical;
    final scheme = Theme.of(context).colorScheme;
    final color = critical ? scheme.error : scheme.tertiary;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
          child: Icon(switch (incident.source) {
            CockpitIncidentSource.node => Icons.dns_outlined,
            CockpitIncidentSource.task => Icons.error_outline_rounded,
            CockpitIncidentSource.rule => Icons.speed_outlined,
          }),
        ),
        title: Text(
          incident.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${incident.detail}\n'
            '${incident.sourceLabel} • ${formatAge(incident.observedAt)}',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chevron_right_rounded, color: color),
            Text(
              incident.severityLabel.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
