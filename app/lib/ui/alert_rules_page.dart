import 'package:flutter/material.dart';

import '../core/alert_rules.dart';
import '../core/app_controller.dart';

class ForegroundThresholdAlertRulesPage extends StatefulWidget {
  const ForegroundThresholdAlertRulesPage({
    super.key,
    required this.controller,
    required this.profileId,
    required this.generation,
  });

  final AppController controller;
  final String profileId;
  final int generation;

  @override
  State<ForegroundThresholdAlertRulesPage> createState() =>
      _ForegroundThresholdAlertRulesPageState();
}

class _ForegroundThresholdAlertRulesPageState
    extends State<ForegroundThresholdAlertRulesPage> {
  bool get _currentSession =>
      widget.controller.active?.id == widget.profileId &&
      widget.controller.connectionGeneration == widget.generation;

  List<_ThresholdTarget> _targets() {
    final targets = <_ThresholdTarget>[];
    final inventory = widget.controller.inventory;
    if (inventory != null) {
      for (final node in inventory.nodes) {
        targets.add(
          _ThresholdTarget(
            key: 'node:${node.name}',
            label: 'Node ${node.name} • CPU',
            metric: ForegroundThresholdMetric.nodeCpu,
            node: node.name,
            displayName: node.name,
          ),
        );
      }
      for (final guest in inventory.guests) {
        targets.add(
          _ThresholdTarget(
            key: 'guest:${guest.kind}:${guest.node}:${guest.vmid}',
            label: 'Guest ${guest.name} (${guest.vmid}) on ${guest.node} • CPU',
            metric: ForegroundThresholdMetric.guestCpu,
            node: guest.node,
            displayName: '${guest.name} (${guest.vmid})',
            guestKind: guest.kind,
            guestVmid: guest.vmid,
          ),
        );
      }
    }
    for (final storage in widget.controller.storages) {
      targets.add(
        _ThresholdTarget(
          key: 'storage:${storage.node}:${storage.id}',
          label: 'Storage ${storage.id} on ${storage.node} • usage',
          metric: ForegroundThresholdMetric.storageUsage,
          node: storage.node,
          displayName: '${storage.id} on ${storage.node}',
          storageId: storage.id,
        ),
      );
    }
    targets.sort((left, right) => left.label.compareTo(right.label));
    return targets;
  }

  Future<void> _addRule() async {
    if (!_currentSession) return;
    final targets = _targets();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Refresh live inventory before adding a threshold rule.',
          ),
        ),
      );
      return;
    }

    final byKey = {for (final target in targets) target.key: target};
    var selectedKey = targets.first.key;
    var threshold = 80.0;
    var consecutiveSamples = 1;
    var hysteresis = 0.0;
    var severity = ForegroundAlertSeverity.warning;
    final rule = await showDialog<ForegroundThresholdAlertRule>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final target = byKey[selectedKey]!;
          return AlertDialog(
            title: const Text('Add foreground threshold'),
            scrollable: true,
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    key: const Key('threshold-rule-target'),
                    initialValue: selectedKey,
                    decoration: const InputDecoration(labelText: 'Target'),
                    isExpanded: true,
                    items: [
                      for (final item in targets)
                        DropdownMenuItem(
                          value: item.key,
                          child: Text(
                            item.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => selectedKey = value);
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Threshold: ${threshold.round()}%',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Slider(
                    key: const Key('threshold-rule-slider'),
                    value: threshold,
                    min: 10,
                    max: 100,
                    divisions: 18,
                    label: '${threshold.round()}%',
                    onChanged: (value) {
                      setDialogState(() {
                        threshold = value;
                        if (hysteresis >= threshold) {
                          hysteresis = threshold - 1;
                        }
                      });
                    },
                  ),
                  DropdownButtonFormField<int>(
                    key: const Key('threshold-rule-consecutive-samples'),
                    initialValue: consecutiveSamples,
                    decoration: const InputDecoration(
                      labelText: 'Consecutive live samples',
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 sample')),
                      DropdownMenuItem(value: 2, child: Text('2 samples')),
                      DropdownMenuItem(value: 3, child: Text('3 samples')),
                      DropdownMenuItem(value: 4, child: Text('4 samples')),
                      DropdownMenuItem(value: 5, child: Text('5 samples')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => consecutiveSamples = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Clear hysteresis: ${hysteresis.round()}% '
                    '(resolve at or below '
                    '${threshold.round() - hysteresis.round()}%)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Slider(
                    key: const Key('threshold-rule-hysteresis-slider'),
                    value: hysteresis,
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: '${hysteresis.round()}%',
                    onChanged: (value) {
                      setDialogState(() {
                        hysteresis = value >= threshold ? threshold - 1 : value;
                      });
                    },
                  ),
                  DropdownButtonFormField<ForegroundAlertSeverity>(
                    key: const Key('threshold-rule-severity'),
                    initialValue: severity,
                    decoration: const InputDecoration(labelText: 'Severity'),
                    items: const [
                      DropdownMenuItem(
                        value: ForegroundAlertSeverity.warning,
                        child: Text('Warning'),
                      ),
                      DropdownMenuItem(
                        value: ForegroundAlertSeverity.critical,
                        child: Text('Critical'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => severity = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This rule is evaluated only during foreground live '
                    'refreshes. Missing samples reset pending confirmation '
                    'but never resolve a prior firing.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('confirm-threshold-rule'),
                onPressed: () {
                  Navigator.of(dialogContext).pop(
                    target.toRule(
                      thresholdPercent: threshold.round(),
                      severity: severity,
                      consecutiveSamples: consecutiveSamples,
                      hysteresisPercent: hysteresis.round(),
                    ),
                  );
                },
                child: const Text('Add rule'),
              ),
            ],
          );
        },
      ),
    );
    if (rule == null || !mounted || !_currentSession) return;
    try {
      await widget.controller.saveThresholdAlertRule(
        rule,
        expectedProfileId: widget.profileId,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the threshold rule.')),
      );
    }
  }

  Future<void> _setEnabled(
    ForegroundThresholdAlertRule rule,
    bool enabled,
  ) async {
    try {
      await widget.controller.saveThresholdAlertRule(
        rule.copyWith(enabled: enabled),
        expectedProfileId: widget.profileId,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the threshold rule.')),
      );
    }
  }

  Future<void> _deleteRule(ForegroundThresholdAlertRule rule) async {
    try {
      await widget.controller.deleteThresholdAlertRule(
        rule.id,
        expectedProfileId: widget.profileId,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the threshold rule.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final current = _currentSession;
        final rules = current
            ? widget.controller.thresholdAlertRules
            : const <ForegroundThresholdAlertRule>[];
        return Scaffold(
          appBar: AppBar(title: const Text('Foreground threshold rules')),
          floatingActionButton:
              current && rules.length < maxForegroundThresholdRules
              ? FloatingActionButton.extended(
                  key: const Key('add-threshold-rule'),
                  onPressed: _addRule,
                  icon: const Icon(Icons.add_alert_outlined),
                  label: const Text('Add rule'),
                )
              : null,
          body: !current
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Connection changed. Return to Incidents before editing rules.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Rules are saved only for this connection profile. '
                          'CPU rules use the current node/guest inventory; '
                          'storage rules use the current per-node storage '
                          'overview. No background worker or Android '
                          'notification is created.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (rules.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No foreground threshold rules yet. Add a rule '
                            'after refreshing live inventory.',
                          ),
                        ),
                      )
                    else
                      for (final rule in rules) ...[
                        Card(
                          key: Key('threshold-rule-${rule.id}'),
                          child: ListTile(
                            leading: Icon(
                              rule.metric ==
                                      ForegroundThresholdMetric.storageUsage
                                  ? Icons.storage_outlined
                                  : Icons.speed_outlined,
                            ),
                            title: Text(rule.displayName),
                            subtitle: Text(
                              '${rule.metric.label} • at or above '
                              '${rule.thresholdPercent}% • '
                              '${rule.consecutiveSamples} sample(s) • '
                              '${rule.hysteresisPercent}% hysteresis • '
                              '${rule.severity.name}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: rule.enabled,
                                  onChanged: (value) =>
                                      _setEnabled(rule, value),
                                ),
                                IconButton(
                                  tooltip: 'Delete rule',
                                  onPressed: () => _deleteRule(rule),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
        );
      },
    );
  }
}

class _ThresholdTarget {
  const _ThresholdTarget({
    required this.key,
    required this.label,
    required this.metric,
    required this.node,
    required this.displayName,
    this.guestKind,
    this.guestVmid,
    this.storageId,
  });

  final String key;
  final String label;
  final ForegroundThresholdMetric metric;
  final String node;
  final String displayName;
  final String? guestKind;
  final int? guestVmid;
  final String? storageId;

  ForegroundThresholdAlertRule toRule({
    required int thresholdPercent,
    required ForegroundAlertSeverity severity,
    required int consecutiveSamples,
    required int hysteresisPercent,
  }) {
    return ForegroundThresholdAlertRule.create(
      metric: metric,
      node: node,
      displayName: displayName,
      thresholdPercent: thresholdPercent,
      severity: severity,
      consecutiveSamples: consecutiveSamples,
      hysteresisPercent: hysteresisPercent,
      guestKind: guestKind,
      guestVmid: guestVmid,
      storageId: storageId,
    );
  }
}
