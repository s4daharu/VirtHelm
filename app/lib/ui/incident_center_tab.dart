import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/device_connectivity.dart';
import '../core/incident_center.dart';
import '../core/incident_triage.dart';
import '../core/models.dart';
import 'alert_rules_page.dart';
import 'components.dart';
import 'guest_page.dart';
import 'node_page.dart';
import 'storage_page.dart';
import 'task_details_page.dart';
import 'theme.dart';

enum _IncidentFilter { all, critical, warning }

enum _IncidentTriageView { needsReview, acknowledged, earlier }

class IncidentCenterTab extends StatefulWidget {
  const IncidentCenterTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<IncidentCenterTab> createState() => _IncidentCenterTabState();
}

class _IncidentCenterTabState extends State<IncidentCenterTab> {
  _IncidentFilter filter = _IncidentFilter.all;
  _IncidentTriageView view = _IncidentTriageView.needsReview;

  List<IncidentTriageRecord> _visible(List<IncidentTriageRecord> records) {
    return switch (filter) {
      _IncidentFilter.all => records,
      _IncidentFilter.critical =>
        records
            .where(
              (record) =>
                  record.incident.severity == CockpitIncidentSeverity.critical,
            )
            .toList(growable: false),
      _IncidentFilter.warning =>
        records
            .where(
              (record) =>
                  record.incident.severity == CockpitIncidentSeverity.warning,
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
    final renderingProfileId = controller.active?.id;
    final renderingGeneration = controller.connectionGeneration;
    final incidents = controller.incidents;
    final current = _visible(controller.currentIncidentTriage);
    final earlier = _visible(controller.earlierIncidentTriage);
    final needsReview = current
        .where((record) => !record.isAcknowledged)
        .toList();
    final acknowledged = current
        .where((record) => record.isAcknowledged)
        .toList();
    final selected = switch (view) {
      _IncidentTriageView.needsReview => needsReview,
      _IncidentTriageView.acknowledged => acknowledged,
      _IncidentTriageView.earlier => earlier,
    };
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
                              builder: (_) => ForegroundThresholdAlertRulesPage(
                                controller: controller,
                                profileId: profileId,
                                generation: controller.connectionGeneration,
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
            'Foreground-only signals. Acknowledgement changes only your '
            'current session view, not server health or task outcomes. '
            'Earlier signals are kept in memory until you reconnect; '
            'there is no persistent history, background monitoring or '
            'Android notification delivery.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (incidents.isNotEmpty) ...[
            const SizedBox(height: 14),
            _IncidentSeveritySummary(incidents: incidents),
          ],
          if (stale) ...[
            const SizedBox(height: 14),
            const MessageCard(
              key: Key('incident-stale-warning'),
              tone: MessageTone.warning,
              text:
                  'INCIDENT DATA MAY BE STALE • Retained incidents are not '
                  'resolved while live inventory is unavailable. Refresh a '
                  'clean authenticated connection to confirm recovery.',
            ),
          ],
          if (taskCoverageIncomplete) ...[
            const SizedBox(height: 10),
            MessageCard(
              key: const Key('incident-task-coverage-warning'),
              tone: MessageTone.warning,
              text:
                  'Task incident coverage is incomplete. '
                  '${controller.serverTaskMessage}',
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            key: const Key('incident-triage-view'),
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('Needs review (${needsReview.length})'),
                selected: view == _IncidentTriageView.needsReview,
                onSelected: (_) =>
                    setState(() => view = _IncidentTriageView.needsReview),
              ),
              ChoiceChip(
                label: Text('Acknowledged (${acknowledged.length})'),
                selected: view == _IncidentTriageView.acknowledged,
                onSelected: (_) =>
                    setState(() => view = _IncidentTriageView.acknowledged),
              ),
              ChoiceChip(
                label: Text('Earlier (${earlier.length})'),
                selected: view == _IncidentTriageView.earlier,
                onSelected: (_) =>
                    setState(() => view = _IncidentTriageView.earlier),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
          else if (selected.isEmpty && view == _IncidentTriageView.earlier)
            const EmptyState(
              icon: Icons.history_rounded,
              title: 'No earlier signals',
              body:
                  'Only signals that disappear after a complete foreground '
                  'refresh appear here. This is not a recovery certificate.',
            )
          else if (selected.isEmpty && view == _IncidentTriageView.acknowledged)
            const EmptyState(
              icon: Icons.done_all_rounded,
              title: 'Nothing acknowledged',
              body: 'Use Acknowledge on a signal to mark it reviewed locally.',
            )
          else if (selected.isEmpty && incidents.isNotEmpty)
            EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'No signals in this view',
              body: 'Choose another triage view or severity to see incidents.',
              action: TextButton(
                onPressed: () => setState(() {
                  filter = _IncidentFilter.all;
                  view = _IncidentTriageView.needsReview;
                }),
                child: const Text('Show needs review'),
              ),
            )
          else if (incidents.isEmpty && (stale || taskCoverageIncomplete))
            EmptyState(
              icon: Icons.help_outline_rounded,
              title: 'Health cannot be confirmed',
              body:
                  'No retained incidents are visible, but one or more live '
                  'sources are unavailable or incomplete.',
              action: FilledButton.tonalIcon(
                onPressed: controller.refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
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
            for (final record in selected) ...[
              if (record.isCurrent)
                _IncidentCard(
                  incident: record.incident,
                  acknowledged: record.isAcknowledged,
                  onTap: () => _openIncident(context, record.incident),
                  onAcknowledge: () {
                    if (renderingProfileId == null) return;
                    controller.setIncidentAcknowledged(
                      record.incident.key,
                      !record.isAcknowledged,
                      expectedProfileId: renderingProfileId,
                      expectedGeneration: renderingGeneration,
                    );
                  },
                )
              else
                _EarlierIncidentCard(record: record),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _IncidentSeveritySummary extends StatelessWidget {
  const _IncidentSeveritySummary({required this.incidents});

  final List<CockpitIncident> incidents;

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
    return Row(
      children: [
        Expanded(
          child: _IncidentSummaryTile(
            label: 'Critical',
            count: critical,
            color: status.error,
            icon: Icons.error_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _IncidentSummaryTile(
            label: 'Warnings',
            count: warning,
            color: status.warning,
            icon: Icons.warning_amber_rounded,
          ),
        ),
      ],
    );
  }
}

class _IncidentSummaryTile extends StatelessWidget {
  const _IncidentSummaryTile({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String label;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({
    required this.incident,
    required this.onTap,
    required this.onAcknowledge,
    required this.acknowledged,
  });

  final CockpitIncident incident;
  final VoidCallback onTap;
  final VoidCallback onAcknowledge;
  final bool acknowledged;

  @override
  Widget build(BuildContext context) {
    final critical = incident.severity == CockpitIncidentSeverity.critical;
    final scheme = Theme.of(context).colorScheme;
    final color = critical ? scheme.error : scheme.tertiary;
    return Card(
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
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
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('incident-triage-action-${incident.key}'),
                onPressed: onAcknowledge,
                icon: Icon(
                  acknowledged ? Icons.undo_rounded : Icons.done_all_rounded,
                ),
                label: Text(
                  acknowledged ? 'Mark as unreviewed' : 'Acknowledge',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EarlierIncidentCard extends StatelessWidget {
  const _EarlierIncidentCard({required this.record});

  final IncidentTriageRecord record;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.history_rounded),
      title: Text(record.incident.title),
      subtitle: Text(
        '${record.departureLabel}\n'
        'Last observed ${formatAge(record.lastSeen)} • '
        '${record.isAcknowledged ? 'Acknowledged' : 'Not acknowledged'}',
      ),
      isThreeLine: true,
    ),
  );
}
