enum ForegroundAlertSeverity { warning, critical }

enum ForegroundThresholdMetric { nodeCpu, guestCpu, storageUsage }

const int maxForegroundThresholdRules = 32;

extension ForegroundThresholdMetricLabel on ForegroundThresholdMetric {
  String get label => switch (this) {
    ForegroundThresholdMetric.nodeCpu => 'Node CPU',
    ForegroundThresholdMetric.guestCpu => 'Guest CPU',
    ForegroundThresholdMetric.storageUsage => 'Storage usage',
  };
}

class ForegroundThresholdAlertRule {
  const ForegroundThresholdAlertRule({
    required this.id,
    required this.metric,
    required this.node,
    required this.displayName,
    required this.thresholdPercent,
    required this.severity,
    this.guestKind,
    this.guestVmid,
    this.storageId,
    this.enabled = true,
  });

  factory ForegroundThresholdAlertRule.create({
    required ForegroundThresholdMetric metric,
    required String node,
    required String displayName,
    required int thresholdPercent,
    required ForegroundAlertSeverity severity,
    String? guestKind,
    int? guestVmid,
    String? storageId,
  }) {
    return ForegroundThresholdAlertRule(
      id: 'rule-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      metric: metric,
      node: node,
      displayName: displayName,
      thresholdPercent: thresholdPercent,
      severity: severity,
      guestKind: guestKind,
      guestVmid: guestVmid,
      storageId: storageId,
    );
  }

  final String id;
  final ForegroundThresholdMetric metric;
  final String node;
  final String displayName;
  final int thresholdPercent;
  final ForegroundAlertSeverity severity;
  final String? guestKind;
  final int? guestVmid;
  final String? storageId;
  final bool enabled;

  double get thresholdFraction => thresholdPercent / 100;

  String get resourceKey => switch (metric) {
    ForegroundThresholdMetric.nodeCpu => 'node:$node',
    ForegroundThresholdMetric.guestCpu => 'guest:$guestKind:$node:$guestVmid',
    ForegroundThresholdMetric.storageUsage => 'storage:$node:$storageId',
  };

  ForegroundThresholdAlertRule copyWith({bool? enabled}) {
    return ForegroundThresholdAlertRule(
      id: id,
      metric: metric,
      node: node,
      displayName: displayName,
      thresholdPercent: thresholdPercent,
      severity: severity,
      guestKind: guestKind,
      guestVmid: guestVmid,
      storageId: storageId,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'metric': metric.name,
    'node': node,
    'display_name': displayName,
    'threshold_percent': thresholdPercent,
    'severity': severity.name,
    'guest_kind': guestKind,
    'guest_vmid': guestVmid,
    'storage_id': storageId,
    'enabled': enabled,
  };

  factory ForegroundThresholdAlertRule.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final metricName = json['metric'];
    final node = json['node'];
    final displayName = json['display_name'];
    final threshold = json['threshold_percent'];
    final severityName = json['severity'];
    final enabled = json['enabled'];

    ForegroundThresholdMetric? metric;
    for (final value in ForegroundThresholdMetric.values) {
      if (value.name == metricName) metric = value;
    }
    ForegroundAlertSeverity? severity;
    for (final value in ForegroundAlertSeverity.values) {
      if (value.name == severityName) severity = value;
    }

    if (id is! String ||
        id.trim().isEmpty ||
        id.length > 80 ||
        metric == null ||
        node is! String ||
        node.trim().isEmpty ||
        node.length > 120 ||
        displayName is! String ||
        displayName.trim().isEmpty ||
        displayName.length > 160 ||
        threshold is! int ||
        threshold < 1 ||
        threshold > 100 ||
        severity == null ||
        enabled is! bool) {
      throw const FormatException('Invalid foreground threshold rule.');
    }

    final guestKind = json['guest_kind'];
    final guestVmid = json['guest_vmid'];
    final storageId = json['storage_id'];
    final validTarget = switch (metric) {
      ForegroundThresholdMetric.nodeCpu =>
        guestKind == null && guestVmid == null && storageId == null,
      ForegroundThresholdMetric.guestCpu =>
        (guestKind == 'qemu' || guestKind == 'lxc') &&
            guestVmid is int &&
            guestVmid > 0 &&
            storageId == null,
      ForegroundThresholdMetric.storageUsage =>
        storageId is String &&
            storageId.trim().isNotEmpty &&
            storageId.length <= 120 &&
            guestKind == null &&
            guestVmid == null,
    };
    if (!validTarget) {
      throw const FormatException('Invalid foreground threshold target.');
    }

    return ForegroundThresholdAlertRule(
      id: id,
      metric: metric,
      node: node.trim(),
      displayName: displayName.trim(),
      thresholdPercent: threshold,
      severity: severity,
      guestKind: guestKind as String?,
      guestVmid: guestVmid as int?,
      storageId: storageId as String?,
      enabled: enabled,
    );
  }
}
