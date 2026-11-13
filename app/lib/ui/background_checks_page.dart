import 'dart:async';

import 'package:flutter/material.dart';

import '../core/alert_rules.dart';
import '../core/app_controller.dart';
import '../core/background_checks.dart';
import '../core/foreground_notifications.dart';
import '../core/models.dart';
import 'components.dart';

class BackgroundChecksPage extends StatefulWidget {
  const BackgroundChecksPage({
    super.key,
    required this.controller,
    required this.profile,
    this.scheduler = const AndroidBackgroundCheckScheduler(),
    this.notifier = const AndroidForegroundIncidentNotifier(),
  });

  final AppController controller;
  final ConnectionProfile profile;
  final BackgroundCheckScheduler scheduler;
  final ForegroundIncidentNotifier notifier;

  @override
  State<BackgroundChecksPage> createState() => _BackgroundChecksPageState();
}

class _BackgroundChecksPageState extends State<BackgroundChecksPage> {
  BackgroundCheckStatus? _status;
  bool _busy = false;
  String? _error;

  BackgroundCheckPolicy get _policy =>
      _status?.policy ?? const BackgroundCheckPolicy();

  ConnectionProfile? get _currentProfile {
    final matches = widget.controller.profiles.where(
      (profile) => profile.id == widget.profile.id,
    );
    return matches.length == 1 ? matches.single : null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final status = await widget.scheduler.status(widget.profile.id);
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
    } on Object catch (caught) {
      if (!mounted) return;
      setState(() => _error = _message(caught));
    }
  }

  String _message(Object caught) => caught is BackgroundCheckException
      ? caught.message
      : caught is FormatException
      ? caught.message
      : 'Could not update scheduled checks.';

  Future<void> _apply(BackgroundCheckPolicy next) async {
    if (_busy) return;
    final profile = _currentProfile;
    if (profile == null) {
      setState(() => _error = 'Connection no longer exists.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final validated = next.validated();
      if (!validated.enabled) {
        await widget.scheduler.disable(profile.id);
      } else {
        if (profile.allowInvalidCertificates) {
          throw const FormatException(
            'Scheduled checks require certificate and hostname verification. '
            'Edit this connection and remove the TLS exception first.',
          );
        }
        final credentials = await widget.controller.repository.vault.retrieve(
          profile.id,
        );
        if (credentials == null || !credentials.isValid) {
          throw const BackgroundCheckException(
            'Saved API token is unavailable. Edit this connection and enter a replacement token.',
          );
        }
        if (_policy.enabled == false) {
          final granted = await widget.notifier.requestPermission();
          if (!granted) {
            throw const BackgroundCheckException(
              'Android notification permission was not granted. Scheduled checks remain off.',
            );
          }
        }
        final scheduler = widget.scheduler;
        if (scheduler is ThresholdAwareBackgroundCheckScheduler) {
          final thresholdScheduler =
              scheduler as ThresholdAwareBackgroundCheckScheduler;
          await thresholdScheduler.configureWithThresholdRules(
            profile,
            credentials,
            validated,
            widget.controller.thresholdAlertRules,
          );
        } else {
          await scheduler.configure(profile, credentials, validated);
        }
      }
      final status = await widget.scheduler.status(profile.id);
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
    } on Object catch (caught) {
      if (!mounted) return;
      setState(() => _error = _message(caught));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickQuietTime({required bool start}) async {
    if (_busy) return;
    final policy = _policy;
    final minute = start ? policy.quietStartMinute : policy.quietEndMinute;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      helpText: start
          ? 'Scheduled quiet hours start'
          : 'Scheduled quiet hours end',
    );
    if (selected == null || !mounted) return;
    final nextMinute = selected.hour * 60 + selected.minute;
    await _apply(
      start
          ? policy.copyWith(quietStartMinute: nextMinute)
          : policy.copyWith(quietEndMinute: nextMinute),
    );
  }

  String _formatMinute(int minute) => MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay(hour: minute ~/ 60, minute: minute % 60));

  String _formatDate(DateTime? value) {
    if (value == null) return 'Never';
    final local = value.toLocal();
    return '${MaterialLocalizations.of(context).formatMediumDate(local)} '
        '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  String _outcomeLabel(String? value) => switch (value) {
    'healthy' => 'Completed: no scheduled incident found',
    'incident' => 'Completed: node-state incident found',
    'node_incident' => 'Completed: node-state incident found',
    'task_incident' => 'Completed: recent failed task incident found',
    'node_and_task_incident' =>
      'Completed: node-state and recent task incidents found',
    'task_authorization_denied' =>
      'Incomplete: recent task authorization denied',
    'task_redirect_blocked' => 'Incomplete: recent task redirect blocked',
    'task_incomplete' => 'Incomplete: recent task data could not be confirmed',
    'task_read_failed' => 'Incomplete: recent task read failed',
    'threshold_incomplete' =>
      'Incomplete: one or more node CPU threshold samples are unavailable',
    'threshold_incident' => 'Completed: node CPU threshold incident found',
    'node_and_threshold_incident' =>
      'Completed: node-state and node CPU threshold incidents found',
    'task_and_threshold_incident' =>
      'Completed: recent task and node CPU threshold incidents found',
    'node_task_threshold_incident' =>
      'Completed: node-state, recent task and node CPU threshold incidents found',
    'guest_threshold_incomplete' =>
      'Incomplete: one or more guest CPU threshold samples are unavailable',
    'guest_threshold_incident' =>
      'Completed: guest CPU threshold incident found',
    'combined_incident' => 'Completed: multiple scheduled incident types found',
    'guest_cpu_authorization_denied' =>
      'Incomplete: guest CPU authorization denied',
    'guest_cpu_redirect_blocked' => 'Incomplete: guest CPU redirect blocked',
    'guest_cpu_incomplete' =>
      'Incomplete: guest CPU data could not be confirmed',
    'guest_cpu_read_failed' => 'Incomplete: guest CPU read failed',
    'storage_threshold_incomplete' =>
      'Incomplete: one or more storage usage threshold samples are unavailable',
    'storage_threshold_incident' =>
      'Completed: storage usage threshold incident found',
    'storage_usage_authorization_denied' =>
      'Incomplete: storage usage authorization denied',
    'storage_usage_redirect_blocked' =>
      'Incomplete: storage usage redirect blocked',
    'storage_usage_incomplete' =>
      'Incomplete: storage usage data could not be confirmed',
    'storage_usage_read_failed' => 'Incomplete: storage usage read failed',
    'authorization_denied' => 'Incomplete: token authorization denied',
    'redirect_blocked' => 'Incomplete: redirect blocked',
    'incomplete' => 'Incomplete: node data could not be confirmed',
    'read_failed' => 'Incomplete: scheduled read failed',
    'configuration_unavailable' =>
      'Disabled: encrypted scheduled credential is unavailable',
    'skipped_foreground' => 'Skipped: VirtHelm was already in the foreground',
    _ => 'No scheduled result yet',
  };

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

  @override
  Widget build(BuildContext context) {
    final profile = _currentProfile ?? widget.profile;
    final policy = _policy;
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled checks')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: [
            const MessageCard(
              icon: Icons.schedule_rounded,
              title: 'Best-effort Android monitoring',
              text:
                  'Android WorkManager can run read-only node-state checks and, '
                  'when separately enabled, bounded recent-task checks plus '
                  'saved node CPU, guest CPU and storage usage threshold rules '
                  'while VirtHelm is closed. The minimum interval is 15 minutes, but '
                  'execution is inexact and may be delayed by the OS, battery '
                  'policy, missing network or VPN. This is not 24/7 monitoring '
                  'and is not suitable for critical paging.',
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      key: const Key('periodic-incident-checks'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Periodic scheduled checks'),
                      subtitle: Text(
                        profile.allowInvalidCertificates
                            ? 'Unavailable while this connection disables TLS identity verification.'
                            : 'Opt in to generic Android alerts for newly observed non-online node state.',
                      ),
                      value: policy.enabled,
                      onChanged: _busy || profile.allowInvalidCertificates
                          ? null
                          : (value) => unawaited(
                              _apply(policy.copyWith(enabled: value)),
                            ),
                    ),
                    if (policy.enabled) ...[
                      const Divider(),
                      SwitchListTile(
                        key: const Key('periodic-failed-task-checks'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Include recent failed tasks'),
                        subtitle: const Text(
                          'Also check up to 20 recent tasks per visible node. '
                          'Only generic incident state is retained; raw task IDs, '
                          'resource names and logs are never stored by the worker. '
                          'Correlation retains profile-scoped hashes only.',
                        ),
                        value: policy.failedTaskChecksEnabled,
                        onChanged: _busy
                            ? null
                            : (value) => unawaited(
                                _apply(
                                  policy.copyWith(
                                    failedTaskChecksEnabled: value,
                                  ),
                                ),
                              ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        key: const Key('periodic-node-cpu-threshold-checks'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Include node CPU threshold rules'),
                        subtitle: Text(
                          'Evaluate the '
                          '${widget.controller.thresholdAlertRules.where((rule) => rule.enabled && rule.metric == ForegroundThresholdMetric.nodeCpu).length} '
                          'enabled node CPU rule(s) on each scheduled node snapshot. '
                          'Guest CPU and storage usage rules use separate opt-ins below.',
                        ),
                        value: policy.nodeCpuThresholdChecksEnabled,
                        onChanged: _busy
                            ? null
                            : (value) => unawaited(
                                _apply(
                                  policy.copyWith(
                                    nodeCpuThresholdChecksEnabled: value,
                                  ),
                                ),
                              ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        key: const Key('periodic-guest-cpu-threshold-checks'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Include guest CPU threshold rules'),
                        subtitle: Text(
                          'Evaluate the '
                          '${widget.controller.thresholdAlertRules.where((rule) => rule.enabled && rule.metric == ForegroundThresholdMetric.guestCpu).length} '
                          'enabled guest CPU rule(s) from a bounded scheduled guest inventory read. '
                          'Storage usage rules use the separate opt-in below.',
                        ),
                        value: policy.guestCpuThresholdChecksEnabled,
                        onChanged: _busy
                            ? null
                            : (value) => unawaited(
                                _apply(
                                  policy.copyWith(
                                    guestCpuThresholdChecksEnabled: value,
                                  ),
                                ),
                              ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        key: const Key(
                          'periodic-storage-usage-threshold-checks',
                        ),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Include storage usage threshold rules',
                        ),
                        subtitle: Text(
                          'Evaluate the '
                          '${widget.controller.thresholdAlertRules.where((rule) => rule.enabled && rule.metric == ForegroundThresholdMetric.storageUsage).length} '
                          'enabled storage rule(s) from bounded per-node '
                          'read-only storage checks (up to 16 nodes).',
                        ),
                        value: policy.storageUsageThresholdChecksEnabled,
                        onChanged: _busy
                            ? null
                            : (value) => unawaited(
                                _apply(
                                  policy.copyWith(
                                    storageUsageThresholdChecksEnabled: value,
                                  ),
                                ),
                              ),
                      ),
                      const Divider(),
                      const Text('Requested interval'),
                      DropdownButton<int>(
                        key: const Key('periodic-check-interval'),
                        value: policy.intervalMinutes,
                        isExpanded: true,
                        items: const [15, 30, 60, 120, 240]
                            .map(
                              (minutes) => DropdownMenuItem<int>(
                                value: minutes,
                                child: Text(
                                  minutes < 60
                                      ? 'Every $minutes minutes (inexact)'
                                      : 'Every ${minutes ~/ 60} hour${minutes == 60 ? '' : 's'} (inexact)',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) {
                                if (value != null) {
                                  unawaited(
                                    _apply(
                                      policy.copyWith(intervalMinutes: value),
                                    ),
                                  );
                                }
                              },
                      ),
                      const Text(
                        'Android may run later than requested. A missing run is '
                        'reported as missing evidence, never continuous coverage.',
                      ),
                      const Divider(),
                      SwitchListTile(
                        key: const Key('periodic-check-quiet-hours'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Quiet hours'),
                        subtitle: const Text(
                          'Suppress scheduled Android delivery only. Suppressed '
                          'occurrences are not queued for later.',
                        ),
                        value: policy.quietHoursEnabled,
                        onChanged: _busy
                            ? null
                            : (value) => unawaited(
                                _apply(
                                  policy.copyWith(quietHoursEnabled: value),
                                ),
                              ),
                      ),
                      if (policy.quietHoursEnabled) ...[
                        ListTile(
                          key: const Key('periodic-check-quiet-start'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Starts'),
                          trailing: Text(
                            _formatMinute(policy.quietStartMinute),
                          ),
                          onTap: _busy
                              ? null
                              : () => unawaited(_pickQuietTime(start: true)),
                        ),
                        ListTile(
                          key: const Key('periodic-check-quiet-end'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Ends'),
                          trailing: Text(_formatMinute(policy.quietEndMinute)),
                          onTap: _busy
                              ? null
                              : () => unawaited(_pickQuietTime(start: false)),
                        ),
                      ],
                      const Divider(),
                      const Text('Scheduled notification cooldown'),
                      DropdownButton<int>(
                        key: const Key('periodic-check-cooldown'),
                        value: policy.cooldownMinutes,
                        isExpanded: true,
                        items: _cooldownOptions(policy.cooldownMinutes)
                            .map(
                              (minutes) => DropdownMenuItem<int>(
                                value: minutes,
                                child: Text(_cooldownLabel(minutes)),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) {
                                if (value != null) {
                                  unawaited(
                                    _apply(
                                      policy.copyWith(cooldownMinutes: value),
                                    ),
                                  );
                                }
                              },
                      ),
                      const Text(
                        'This scheduled cooldown is checked against the last '
                        'successful scheduled or foreground notification for '
                        'this connection.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              MessageCard(
                title: 'Scheduled checks need attention',
                text: _error!,
                tone: MessageTone.warning,
                icon: Icons.warning_amber_rounded,
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Coverage evidence',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          key: const Key('periodic-check-refresh-status'),
                          tooltip: 'Refresh scheduled-check status',
                          onPressed: _busy ? null : () => unawaited(_reload()),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Last attempt: ${_formatDate(_status?.lastAttemptAt)}',
                    ),
                    Text(
                      'Last complete check: ${_formatDate(_status?.lastSuccessfulAt)}',
                    ),
                    Text(_outcomeLabel(_status?.lastOutcome)),
                    Text(
                      'Last scheduled notification: '
                      '${_formatDate(_status?.lastNotificationAt)}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            MessageCard(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy and safety boundary',
              text:
                  'The worker performs GET only against the saved HTTPS origin '
                  'with normal certificate and hostname validation and redirects '
                  'disabled. Failed-task scanning is separately opted in, is '
                  'bounded to 16 nodes and 20 recent task rows per node, and '
                  'never persists raw task identifiers or resource names. '
                   'Correlation retains profile-scoped hashes only. Optional '
                  'threshold rules keep node, guest and storage selectors plus '
                  'thresholds only inside the Android-Keystore-encrypted worker '
                  'payload. Runtime threshold and cross-mode correlation state '
                  'uses profile-scoped hashes, bounded counters/booleans and '
                  'observation timestamps only. Exact identities are supplied '
                  'only from the unlocked live incident list for in-memory '
                  'matching. The API token '
                  'copy is encrypted with Android Keystore for this opt-in '
                  'worker. Notifications are generic: '
                  'no connection name, endpoint, node name, guest name, VMID, '
                  'task ID or task log is included. Lock-screen exposure follows '
                  'Settings > Incident notifications and is currently '
                  '${widget.controller.notificationLockScreenPrivacy == IncidentNotificationLockScreenPrivacy.hidden ? 'hidden on secure lock screens' : 'generic alert only'}. '
                  'Editing or removing the connection clears the worker credential '
                  'copy and schedule.',
            ),
          ],
        ),
      ),
    );
  }
}
