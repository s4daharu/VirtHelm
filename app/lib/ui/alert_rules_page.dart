import 'package:flutter/material.dart';

import '../core/alert_rules.dart';
import '../core/app_controller.dart';
import '../core/background_checks.dart';

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

  Future<void> _openEditor({ForegroundThresholdAlertRule? rule}) async {
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
    if (rule != null &&
        !targets.any((target) => target.key == rule.resourceKey)) {
      targets.insert(0, _ThresholdTarget.fromRule(rule));
    }
    final result = await Navigator.of(context)
        .push<ForegroundThresholdAlertRule>(
          MaterialPageRoute<ForegroundThresholdAlertRule>(
            builder: (_) =>
                _ThresholdRuleEditorPage(targets: targets, existing: rule),
          ),
        );
    if (result == null || !mounted || !_currentSession) return;
    try {
      await widget.controller.saveThresholdAlertRule(
        result,
        expectedProfileId: widget.profileId,
      );
    } on BackgroundCheckException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Rule saved, but scheduled checks were disabled because the '
            'background rule copy could not be synchronized.',
          ),
        ),
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
    } on BackgroundCheckException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Rule updated, but scheduled checks were disabled because the '
            'background rule copy could not be synchronized.',
          ),
        ),
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
    } on BackgroundCheckException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Rule deleted, but scheduled checks were disabled because the '
            'background rule copy could not be synchronized.',
          ),
        ),
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
          appBar: AppBar(title: const Text('Threshold rules')),
          floatingActionButton:
              current && rules.length < maxForegroundThresholdRules
              ? FloatingActionButton.extended(
                  key: const Key('add-threshold-rule'),
                  onPressed: () => _openEditor(),
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
                          'overview. Node CPU rules can also be evaluated by '
                          'Scheduled checks when separately enabled. Guest CPU '
                          'and storage thresholds remain foreground-only.',
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
                          clipBehavior: Clip.antiAlias,
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
                            onTap: () => _openEditor(rule: rule),
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

class _ThresholdRuleEditorPage extends StatefulWidget {
  const _ThresholdRuleEditorPage({
    required this.targets,
    required this.existing,
  });

  final List<_ThresholdTarget> targets;
  final ForegroundThresholdAlertRule? existing;

  @override
  State<_ThresholdRuleEditorPage> createState() =>
      _ThresholdRuleEditorPageState();
}

class _ThresholdRuleEditorPageState extends State<_ThresholdRuleEditorPage> {
  late final Map<String, _ThresholdTarget> _byKey;
  late String _selectedKey;
  late double _threshold;
  late int _consecutiveSamples;
  late double _hysteresis;
  late ForegroundAlertSeverity _severity;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _byKey = {for (final target in widget.targets) target.key: target};
    final existing = widget.existing;
    _selectedKey = existing != null && _byKey.containsKey(existing.resourceKey)
        ? existing.resourceKey
        : widget.targets.first.key;
    _threshold = (existing?.thresholdPercent ?? 80).toDouble();
    _consecutiveSamples = (existing?.consecutiveSamples ?? 1).clamp(1, 10);
    _hysteresis = (existing?.hysteresisPercent ?? 0).toDouble().clamp(
      0,
      _threshold - 1,
    );
    _severity = existing?.severity ?? ForegroundAlertSeverity.warning;
  }

  Future<void> _pickTarget() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: _ThresholdTargetPicker(
            targets: widget.targets,
            selectedKey: _selectedKey,
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedKey = selected);
  }

  void _save() {
    final target = _byKey[_selectedKey];
    if (target == null) return;
    final threshold = _threshold.round();
    final hysteresis = _hysteresis.round().clamp(0, threshold - 1);
    final existing = widget.existing;
    final rule = existing == null
        ? target.toRule(
            thresholdPercent: threshold,
            severity: _severity,
            consecutiveSamples: _consecutiveSamples,
            hysteresisPercent: hysteresis,
          )
        : ForegroundThresholdAlertRule(
            id: existing.id,
            metric: target.metric,
            node: target.node,
            displayName: target.displayName,
            thresholdPercent: threshold,
            severity: _severity,
            guestKind: target.guestKind,
            guestVmid: target.guestVmid,
            storageId: target.storageId,
            enabled: existing.enabled,
            consecutiveSamples: _consecutiveSamples,
            hysteresisPercent: hysteresis,
          );
    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) {
    final target = _byKey[_selectedKey]!;
    final clearAt = _threshold.round() - _hysteresis.round();
    final largeText = MediaQuery.textScalerOf(context).scale(12) > 16;
    final confirm = FilledButton(
      key: const Key('confirm-threshold-rule'),
      onPressed: _save,
      child: Text(_editing ? 'Save changes' : 'Add rule'),
    );
    final cancel = OutlinedButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Cancel'),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? 'Edit foreground threshold' : 'Add foreground threshold',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
        children: [
          Text(
            'This rule is evaluated during foreground live refreshes. Node CPU '
            'rules can also be evaluated by Scheduled checks when separately '
            'enabled. Missing samples reset pending confirmation but never '
            'resolve a prior firing.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              key: const Key('threshold-rule-target'),
              leading: Icon(_targetIcon(target.metric)),
              title: const Text('Target'),
              subtitle: Text(target.label),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickTarget,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Threshold: ${_threshold.round()}%',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            key: const Key('threshold-rule-slider'),
            value: _threshold,
            min: 10,
            max: 100,
            divisions: 18,
            label: '${_threshold.round()}%',
            onChanged: (value) {
              setState(() {
                _threshold = value;
                if (_hysteresis >= _threshold) {
                  _hysteresis = _threshold - 1;
                }
              });
            },
          ),
          DropdownButtonFormField<int>(
            key: const Key('threshold-rule-consecutive-samples'),
            initialValue: _consecutiveSamples,
            decoration: const InputDecoration(
              labelText: 'Consecutive live samples',
            ),
            items: [
              for (var value = 1; value <= 10; value++)
                DropdownMenuItem(
                  value: value,
                  child: Text(value == 1 ? '1 sample' : '$value samples'),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _consecutiveSamples = value);
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Clear hysteresis: ${_hysteresis.round()}% '
            '(resolve at or below $clearAt%)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            key: const Key('threshold-rule-hysteresis-slider'),
            value: _hysteresis,
            min: 0,
            max: 20,
            divisions: 20,
            label: '${_hysteresis.round()}%',
            onChanged: (value) {
              setState(() {
                _hysteresis = value.clamp(0, _threshold - 1);
              });
            },
          ),
          const SizedBox(height: 12),
          Text('Severity', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('Warning'),
                selected: _severity == ForegroundAlertSeverity.warning,
                onSelected: (_) =>
                    setState(() => _severity = ForegroundAlertSeverity.warning),
              ),
              ChoiceChip(
                label: const Text('Critical'),
                selected: _severity == ForegroundAlertSeverity.critical,
                onSelected: (_) => setState(
                  () => _severity = ForegroundAlertSeverity.critical,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rule summary',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fire ${_severity.name} when ${target.displayName} '
                    '${target.metric == ForegroundThresholdMetric.storageUsage ? 'usage' : 'CPU'} '
                    'is at or above ${_threshold.round()}% for '
                    '$_consecutiveSamples usable sample(s). Resolve at or '
                    'below $clearAt%.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: largeText
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [confirm, const SizedBox(height: 8), cancel],
                )
              : Row(
                  children: [
                    Expanded(child: cancel),
                    const SizedBox(width: 12),
                    Expanded(child: confirm),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ThresholdTargetPicker extends StatefulWidget {
  const _ThresholdTargetPicker({
    required this.targets,
    required this.selectedKey,
  });

  final List<_ThresholdTarget> targets;
  final String selectedKey;

  @override
  State<_ThresholdTargetPicker> createState() => _ThresholdTargetPickerState();
}

class _ThresholdTargetPickerState extends State<_ThresholdTargetPicker> {
  final search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final visible = widget.targets
        .where(
          (target) =>
              needle.isEmpty || target.label.toLowerCase().contains(needle),
        )
        .toList(growable: false);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: TextField(
              key: const Key('threshold-rule-target-search'),
              controller: search,
              autofocus: true,
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                hintText: 'Search nodes, guests, or storage',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('No matching targets.'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    children: [
                      for (final metric in ForegroundThresholdMetric.values)
                        if (visible.any(
                          (target) => target.metric == metric,
                        )) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
                            child: Text(switch (metric) {
                              ForegroundThresholdMetric.nodeCpu => 'Nodes',
                              ForegroundThresholdMetric.guestCpu => 'Guests',
                              ForegroundThresholdMetric.storageUsage =>
                                'Storage',
                            }, style: Theme.of(context).textTheme.labelLarge),
                          ),
                          for (final target in visible.where(
                            (target) => target.metric == metric,
                          ))
                            ListTile(
                              key: ValueKey('threshold-target-${target.key}'),
                              leading: Icon(_targetIcon(target.metric)),
                              title: Text(target.label),
                              trailing: target.key == widget.selectedKey
                                  ? Icon(
                                      Icons.check_circle_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, target.key),
                            ),
                        ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

IconData _targetIcon(ForegroundThresholdMetric metric) => switch (metric) {
  ForegroundThresholdMetric.nodeCpu => Icons.dns_outlined,
  ForegroundThresholdMetric.guestCpu => Icons.computer_outlined,
  ForegroundThresholdMetric.storageUsage => Icons.storage_outlined,
};

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

  factory _ThresholdTarget.fromRule(ForegroundThresholdAlertRule rule) =>
      _ThresholdTarget(
        key: rule.resourceKey,
        label: '${rule.displayName} • ${rule.metric.label}',
        metric: rule.metric,
        node: rule.node,
        displayName: rule.displayName,
        guestKind: rule.guestKind,
        guestVmid: rule.guestVmid,
        storageId: rule.storageId,
      );

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
