import 'dart:convert';
import 'dart:math';

/// Profile metadata is deliberately separate from encrypted API credentials.
class ConnectionProfile {
  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.endpoint,
    this.allowInvalidCertificates = false,
    this.lastServerVersion,
  });

  final String id;
  final String name;
  final String endpoint;
  final bool allowInvalidCertificates;
  final String? lastServerVersion;

  Map<String, Object> toJson() {
    final json = <String, Object>{
      'id': id,
      'name': name,
      'endpoint': endpoint,
      'allowInvalidCertificates': allowInvalidCertificates,
    };
    final version = lastServerVersion;
    if (version != null) json['lastServerVersion'] = version;
    return json;
  }

  factory ConnectionProfile.fromJson(Map<String, dynamic> json) =>
      ConnectionProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        endpoint: json['endpoint'] as String,
        // Only an explicit boolean enables this security-sensitive exception.
        allowInvalidCertificates: json['allowInvalidCertificates'] == true,
        lastServerVersion: _storedServerVersion(json['lastServerVersion']),
      );

  static ConnectionProfile create({
    required String name,
    required String address,
    bool allowInvalidCertificates = false,
  }) {
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_'
        '${Random.secure().nextInt(0x7fffffff)}';
    if (name.trim().isEmpty) {
      throw const FormatException('Enter a profile name.');
    }
    return ConnectionProfile(
      id: id,
      name: name.trim(),
      endpoint: normalizePveEndpoint(address),
      allowInvalidCertificates: allowInvalidCertificates,
    );
  }

  ConnectionProfile withServerVersion(String version) => ConnectionProfile(
    id: id,
    name: name,
    endpoint: endpoint,
    allowInvalidCertificates: allowInvalidCertificates,
    lastServerVersion: normalizeServerVersion(version),
  );
}

/// Result of an explicit read-only connection verification.
///
/// A successful version read proves that the configured HTTPS origin responded.
/// Inventory access is reported separately so the UI can distinguish a
/// reachable server from a token that lacks authentication or inventory
/// permissions. No credentials, raw responses or task data are retained here.
class ConnectionCheckResult {
  const ConnectionCheckResult({
    required this.serverVersion,
    required this.inventoryAccessible,
    required this.certificateVerificationEnabled,
    this.nodeCount = 0,
    this.guestCount = 0,
    this.inventoryMessage,
    this.inventoryStatus,
  });

  final String serverVersion;
  final bool inventoryAccessible;
  final bool certificateVerificationEnabled;
  final int nodeCount;
  final int guestCount;
  final String? inventoryMessage;
  final int? inventoryStatus;

  bool get permissionLimited =>
      !inventoryAccessible &&
      (inventoryStatus == 401 || inventoryStatus == 403);
}

String normalizeServerVersion(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 80) {
    throw const FormatException('Server returned an invalid version.');
  }
  return normalized;
}

String? _storedServerVersion(Object? value) {
  if (value is! String) return null;
  try {
    return normalizeServerVersion(value);
  } on FormatException {
    return null;
  }
}

/// First milestone only supports a direct PVE host:port (not reverse-proxy paths).
/// No HTTP, URL-embedded credentials, redirects, query strings, or fragments.
String normalizePveEndpoint(String input) {
  final trimmed = input.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty &&
          uri.path != '/' &&
          uri.path != '/api2/json' &&
          uri.path != '/api2/json/')) {
    throw const FormatException(
      'Use an HTTPS address, for example https://pve.example:8006',
    );
  }
  // Uri removes explicit default HTTPS ports: hasPort alone would silently
  // turn a user-selected :443 into Proxmox's :8006 on normalization/reload.
  final authority = RegExp(r'^[^:]+://([^/?#]*)').firstMatch(trimmed)?.group(1);
  final explicitPort = RegExp(
    r':([0-9]+)$',
  ).firstMatch(authority ?? '')?.group(1);
  final port = explicitPort == null ? 8006 : int.tryParse(explicitPort);
  if (authority == null ||
      authority.endsWith(':') ||
      port == null ||
      port <= 0 ||
      port > 65535) {
    throw const FormatException('Invalid server port.');
  }
  // Retain an explicit port, including 443, for stable stored origin identity.
  return '${Uri(scheme: 'https', host: uri.host).origin}:$port';
}

class ApiCredentials {
  const ApiCredentials({required this.tokenId, required this.secret});
  final String tokenId;
  final String secret;

  String get header => 'PVEAPIToken=$tokenId=$secret';

  bool get isValid =>
      RegExp(r'^[^\s!@]+@[^\s!@]+![^\s!=]+$').hasMatch(tokenId) &&
      secret.isNotEmpty &&
      secret == secret.trim() &&
      !RegExp(r'\s').hasMatch(secret);

  String encode() => jsonEncode({'id': tokenId, 'secret': secret});

  factory ApiCredentials.decode(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return ApiCredentials(
      tokenId: map['id'] as String,
      secret: map['secret'] as String,
    );
  }
}

int? asInteger(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

double? asDouble(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;
String? asText(Object? value) => value is String ? value : null;

bool? asFlag(Object? value) {
  if (value is bool) return value;
  if (value is num) return value.isFinite ? value != 0 : null;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
      return true;
    }
    if (normalized == '0' || normalized == 'false' || normalized == 'no') {
      return false;
    }
  }
  return null;
}

DateTime? asUnixSeconds(Object? value) {
  final seconds = asInteger(value);
  // DateTime's supported range is +/- 100 million days from the epoch.
  if (seconds == null || seconds < 0 || seconds > 8640000000000) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

enum GuestMetricTimeframe {
  hour(apiValue: 'hour', label: '1 hour'),
  day(apiValue: 'day', label: '24 hours'),
  week(apiValue: 'week', label: '7 days');

  const GuestMetricTimeframe({required this.apiValue, required this.label});

  final String apiValue;
  final String label;
}

class GuestMetricPoint {
  const GuestMetricPoint({
    required this.timestamp,
    this.cpuFraction,
    this.memoryFraction,
  });

  final DateTime timestamp;
  final double? cpuFraction;
  final double? memoryFraction;

  factory GuestMetricPoint.fromApi(Map<String, dynamic> json) {
    final timestamp = asUnixSeconds(json['time']);
    if (timestamp == null) {
      throw const FormatException('RRD sample is missing a valid timestamp.');
    }

    final rawCpu = asDouble(json['cpu']);
    final cpuFraction = rawCpu != null && rawCpu >= 0 && rawCpu <= 1
        ? rawCpu
        : null;

    final mem = asDouble(json['mem']);
    final maxMem = asDouble(json['maxmem']);
    final memoryFraction =
        mem != null && maxMem != null && mem >= 0 && maxMem > 0 && mem <= maxMem
        ? mem / maxMem
        : null;

    if (cpuFraction == null && memoryFraction == null) {
      throw const FormatException(
        'RRD sample has no usable CPU or memory data.',
      );
    }
    return GuestMetricPoint(
      timestamp: timestamp,
      cpuFraction: cpuFraction,
      memoryFraction: memoryFraction,
    );
  }
}

class GuestMetricSeries {
  const GuestMetricSeries({
    required this.points,
    this.malformedRecords = 0,
    this.truncated = false,
  });

  final List<GuestMetricPoint> points;
  final int malformedRecords;
  final bool truncated;
}

enum NodeMetricTimeframe {
  hour(apiValue: 'hour', label: '1 hour'),
  day(apiValue: 'day', label: '24 hours'),
  week(apiValue: 'week', label: '7 days');

  const NodeMetricTimeframe({required this.apiValue, required this.label});

  final String apiValue;
  final String label;
}

class NodeMetricPoint {
  const NodeMetricPoint({
    required this.timestamp,
    this.cpuFraction,
    this.memoryFraction,
  });

  final DateTime timestamp;
  final double? cpuFraction;
  final double? memoryFraction;

  factory NodeMetricPoint.fromApi(Map<String, dynamic> json) {
    final timestamp = asUnixSeconds(json['time']);
    if (timestamp == null) {
      throw const FormatException(
        'Node RRD sample is missing a valid timestamp.',
      );
    }

    final rawCpu = asDouble(json['cpu']);
    final cpuFraction = rawCpu != null && rawCpu >= 0 && rawCpu <= 1
        ? rawCpu
        : null;

    final mem = asDouble(json['mem']);
    final maxMem = asDouble(json['maxmem']);
    final memoryFraction =
        mem != null && maxMem != null && mem >= 0 && maxMem > 0 && mem <= maxMem
        ? mem / maxMem
        : null;

    if (cpuFraction == null && memoryFraction == null) {
      throw const FormatException(
        'Node RRD sample has no usable CPU or memory data.',
      );
    }
    return NodeMetricPoint(
      timestamp: timestamp,
      cpuFraction: cpuFraction,
      memoryFraction: memoryFraction,
    );
  }
}

class NodeMetricSeries {
  const NodeMetricSeries({
    required this.points,
    this.malformedRecords = 0,
    this.truncated = false,
  });

  final List<NodeMetricPoint> points;
  final int malformedRecords;
  final bool truncated;
}

enum StorageMetricTimeframe {
  hour(apiValue: 'hour', label: '1 hour'),
  day(apiValue: 'day', label: '24 hours'),
  week(apiValue: 'week', label: '7 days');

  const StorageMetricTimeframe({required this.apiValue, required this.label});

  final String apiValue;
  final String label;
}

class StorageMetricPoint {
  const StorageMetricPoint({
    required this.timestamp,
    this.usedBytes,
    this.totalBytes,
  });

  final DateTime timestamp;
  final int? usedBytes;
  final int? totalBytes;

  double? get usageFraction {
    final used = usedBytes;
    final total = totalBytes;
    if (used == null ||
        total == null ||
        used < 0 ||
        total <= 0 ||
        used > total) {
      return null;
    }
    return used / total;
  }

  factory StorageMetricPoint.fromApi(Map<String, dynamic> json) {
    final timestamp = asUnixSeconds(json['time']);
    if (timestamp == null) {
      throw const FormatException(
        'Storage RRD sample is missing a valid timestamp.',
      );
    }

    final rawUsed = asDouble(json['used']);
    final rawTotal = asDouble(json['total']);
    final used = rawUsed != null && rawUsed >= 0 ? rawUsed.round() : null;
    final total = rawTotal != null && rawTotal > 0 ? rawTotal.round() : null;

    if (used == null && total == null) {
      throw const FormatException(
        'Storage RRD sample has no usable capacity data.',
      );
    }
    return StorageMetricPoint(
      timestamp: timestamp,
      usedBytes: used,
      totalBytes: total,
    );
  }
}

class StorageMetricSeries {
  const StorageMetricSeries({
    required this.points,
    this.malformedRecords = 0,
    this.truncated = false,
  });

  final List<StorageMetricPoint> points;
  final int malformedRecords;
  final bool truncated;
}

class ReadCollection<T> {
  ReadCollection({
    required List<T> values,
    this.permissionDeniedNodes = 0,
    this.failedNodes = 0,
    this.malformedRecords = 0,
  }) : values = List.unmodifiable(values);

  final List<T> values;
  final int permissionDeniedNodes;
  final int failedNodes;
  final int malformedRecords;

  bool get complete =>
      permissionDeniedNodes == 0 && failedNodes == 0 && malformedRecords == 0;
}

class StoragePool {
  const StoragePool({
    required this.node,
    required this.id,
    required this.type,
    this.enabled,
    this.active,
    this.shared,
    this.contentTypes = const [],
    this.used,
    this.total,
    this.available,
  });

  final String node;
  final String id;
  final String type;
  final bool? enabled;
  final bool? active;
  final bool? shared;
  final List<String> contentTypes;
  final int? used;
  final int? total;
  final int? available;

  double? get usageFraction {
    if (used == null || used! < 0 || total == null || total! <= 0) return null;
    return (used! / total!).clamp(0.0, 1.0).toDouble();
  }

  String get stateLabel {
    if (enabled == false) return 'disabled';
    if (active == true) return 'active';
    if (active == false) return 'inactive';
    if (enabled == true) return 'enabled';
    return 'unknown';
  }

  factory StoragePool.fromApi(
    Map<String, dynamic> json, {
    required String node,
  }) {
    final id = asText(json['storage']);
    if (id == null || id.trim().isEmpty) {
      throw const FormatException('Storage record is missing its identifier.');
    }
    final content = asText(json['content']);
    final contentTypes = content == null
        ? const <String>[]
        : content
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
    return StoragePool(
      node: node,
      id: id,
      type: asText(json['type']) ?? 'unknown',
      enabled: asFlag(json['enabled']),
      active: asFlag(json['active']),
      shared: asFlag(json['shared']),
      contentTypes: contentTypes,
      used: asInteger(json['used']),
      total: asInteger(json['total']),
      available: asInteger(json['avail']),
    );
  }
}

class RecentServerTask {
  const RecentServerTask({
    required this.upid,
    required this.node,
    required this.operation,
    required this.status,
    this.resourceId,
    this.exitStatus,
    this.startedAt,
    this.endedAt,
  });

  final String upid;
  final String node;
  final String operation;
  final String? resourceId;
  final String status;
  final String? exitStatus;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get isDone => status == 'stopped';

  String get stateLabel {
    if (!isDone) return status;
    if (exitStatus == 'OK') return 'succeeded';
    if (exitStatus == null) return 'unknown';
    return 'failed';
  }

  String get operationLabel => switch (operation) {
    'qmstart' => 'Start VM',
    'qmshutdown' => 'Shut down VM',
    'qmstop' => 'Force stop VM',
    'qmreboot' => 'Reboot VM',
    'vzstart' => 'Start container',
    'vzshutdown' => 'Shut down container',
    'vzstop' => 'Force stop container',
    'vzreboot' => 'Reboot container',
    'vzdump' => 'Backup guest',
    _ => operation,
  };

  factory RecentServerTask.fromApi(
    Map<String, dynamic> json, {
    required String node,
  }) {
    final upid = asText(json['upid']);
    if (upid == null || !upid.startsWith('UPID:')) {
      throw const FormatException('Task record is missing a valid UPID.');
    }
    final rawStatus = asText(json['status'])?.trim();
    final running = rawStatus?.toUpperCase() == 'RUNNING';
    final explicitExitStatus = asText(json['exitstatus'])?.trim();
    // PVE task lists can report their terminal result in `status` (e.g.
    // `OK`), while other task shapes use `status: stopped` plus a distinct
    // `exitstatus`. A bare `stopped` is NOT proof of success or failure.
    final stopped = rawStatus?.toLowerCase() == 'stopped';
    final terminal =
        rawStatus != null &&
        rawStatus.isNotEmpty &&
        !running &&
        rawStatus.toLowerCase() != 'unknown';
    final exitStatus = !terminal
        ? null
        : explicitExitStatus != null && explicitExitStatus.isNotEmpty
        ? explicitExitStatus
        : stopped
        ? null
        : rawStatus;
    return RecentServerTask(
      upid: upid,
      node: asText(json['node']) ?? node,
      operation: asText(json['type']) ?? 'task',
      resourceId: asText(json['id']) ?? asInteger(json['id'])?.toString(),
      status: running
          ? 'running'
          : terminal
          ? 'stopped'
          : 'unknown',
      exitStatus: exitStatus,
      startedAt: asUnixSeconds(json['starttime']),
      endedAt: asUnixSeconds(json['endtime']),
    );
  }
}

/// One bounded task-log line. Logs are displayed on demand, never persisted.
class TaskLogEntry {
  const TaskLogEntry({required this.number, required this.text});

  final int number;
  final String text;

  factory TaskLogEntry.fromApi(Map<String, dynamic> json) {
    final number = asInteger(json['n']);
    final raw = json['t'];
    if (number == null || number < 0 || raw is! String) {
      throw const FormatException('Malformed task log entry.');
    }
    // Prevent a malicious or broken endpoint from allocating huge UI strings.
    return TaskLogEntry(
      number: number,
      text: raw.length <= 500 ? raw : '${raw.substring(0, 500)}…',
    );
  }
}

class TaskLogResult {
  const TaskLogResult({required this.entries, required this.malformedRecords});

  final List<TaskLogEntry> entries;
  final int malformedRecords;
}

/// Ephemeral, read-only inspection of an explicitly selected known task.
class TaskInspection {
  const TaskInspection({
    this.status,
    this.log,
    this.statusError,
    this.logError,
  });

  final ServerTaskStatus? status;
  final TaskLogResult? log;
  final String? statusError;
  final String? logError;
}

// Absent, fractional and negative I/O counters are unavailable, not zero.
int? _guestByteCounter(Object? value) {
  final number = asInteger(value);
  return number != null && number >= 0 ? number : null;
}

List<String> _guestTags(Object? value) {
  final raw = asText(value);
  if (raw == null || raw.trim().isEmpty || raw.length > 1024) {
    return const <String>[];
  }
  final result = <String>[];
  final seen = <String>{};
  final controlCharacters = RegExp(r'[\x00-\x1F\x7F]');
  for (final part in raw.split(';')) {
    final tag = part.trim();
    if (tag.isEmpty ||
        tag.length > 64 ||
        controlCharacters.hasMatch(tag) ||
        !seen.add(tag)) {
      continue;
    }
    result.add(tag);
    if (result.length == 32) break;
  }
  return List<String>.unmodifiable(result);
}

String? _guestPool(Object? value) {
  final raw = asText(value)?.trim();
  if (raw == null ||
      raw.isEmpty ||
      raw.length > 200 ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(raw)) {
    return null;
  }
  return raw;
}

String? _snapshotIdentityText(Object? value) {
  final text = asText(value)?.trim();
  if (text == null ||
      text.isEmpty ||
      text.length > 200 ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(text)) {
    return null;
  }
  return text;
}

String? _snapshotDescription(Object? value) {
  final raw = asText(value);
  if (raw == null) return null;
  final cleaned = raw
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
      .trim();
  if (cleaned.isEmpty) return null;
  return cleaned.length <= 500 ? cleaned : '${cleaned.substring(0, 500)}…';
}

/// Read-only guest snapshot metadata. The PVE "current" pseudo-entry is kept
/// separate from real snapshots so the UI never presents it as a restore point.
class GuestSnapshot {
  const GuestSnapshot({
    required this.name,
    this.parent,
    this.description,
    this.createdAt,
    this.includesMemory,
  });

  final String name;
  final String? parent;
  final String? description;
  final DateTime? createdAt;
  final bool? includesMemory;

  bool get isCurrent => name == 'current';

  factory GuestSnapshot.fromApi(Map<String, dynamic> json) {
    final name = _snapshotIdentityText(json['name']);
    if (name == null) {
      throw const FormatException('Snapshot record is missing a valid name.');
    }
    return GuestSnapshot(
      name: name,
      parent: _snapshotIdentityText(json['parent']),
      description: _snapshotDescription(json['description']),
      createdAt: asUnixSeconds(json['snaptime']),
      includesMemory: asFlag(json['vmstate']),
    );
  }
}

class GuestSnapshotInventory {
  const GuestSnapshotInventory({
    required this.snapshots,
    this.malformedRecords = 0,
    this.truncated = false,
  });

  final List<GuestSnapshot> snapshots;
  final int malformedRecords;
  final bool truncated;
}

String? _backupArchiveText(Object? value, {int maxLength = 512}) {
  final text = asText(value)?.trim();
  if (text == null ||
      text.isEmpty ||
      text.length > maxLength ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(text)) {
    return null;
  }
  return text;
}

int? _backupArchiveVmid(Object? value) {
  final numeric = asInteger(value);
  if (numeric != null) return numeric;
  final text = asText(value)?.trim();
  if (text == null || !RegExp(r'^\d{1,9}$').hasMatch(text)) return null;
  return int.tryParse(text);
}

({String kind, int vmid})? _backupArchiveIdentity(
  String volid,
  String storage,
) {
  final prefix = '$storage:backup/';
  if (!volid.startsWith(prefix)) return null;
  final path = volid.substring(prefix.length);

  final fileMatch = RegExp(
    r'^(?:.*/)?vzdump-(qemu|lxc)-(\d{1,9})-',
  ).firstMatch(path);
  if (fileMatch != null) {
    final vmid = int.tryParse(fileMatch.group(2)!);
    if (vmid != null) return (kind: fileMatch.group(1)!, vmid: vmid);
  }

  final pbsMatch = RegExp(r'^(vm|ct)/(\d{1,9})(?:/|$)').firstMatch(path);
  if (pbsMatch != null) {
    final vmid = int.tryParse(pbsMatch.group(2)!);
    if (vmid != null) {
      return (kind: pbsMatch.group(1) == 'vm' ? 'qemu' : 'lxc', vmid: vmid);
    }
  }
  return null;
}

/// Read-only metadata for one backup archive that PVE reports for the exact
/// guest VMID and type. Presence is not integrity or restore verification.
class GuestBackupArchive {
  const GuestBackupArchive({
    required this.node,
    required this.storage,
    required this.volid,
    required this.kind,
    required this.vmid,
    this.format,
    this.sizeBytes,
    this.createdAt,
    this.protected,
  });

  final String node;
  final String storage;
  final String volid;
  final String kind;
  final int vmid;
  final String? format;
  final int? sizeBytes;
  final DateTime? createdAt;
  final bool? protected;

  String get displayName {
    final slash = volid.lastIndexOf('/');
    return slash >= 0 && slash + 1 < volid.length
        ? volid.substring(slash + 1)
        : volid;
  }

  factory GuestBackupArchive.fromApi(
    Map<String, dynamic> json, {
    required Guest guest,
    required String storage,
  }) {
    final content = _backupArchiveText(json['content'], maxLength: 32);
    if (content != null && content != 'backup') {
      throw const FormatException('Storage record is not backup content.');
    }

    final volid = _backupArchiveText(json['volid']);
    if (volid == null) {
      throw const FormatException(
        'Backup record is missing a valid volume ID.',
      );
    }
    final identity = _backupArchiveIdentity(volid, storage);
    if (identity == null ||
        identity.vmid != guest.vmid ||
        identity.kind != guest.kind) {
      throw const FormatException(
        'Backup record does not match the requested guest identity.',
      );
    }

    final reportedVmid = _backupArchiveVmid(json['vmid']);
    if (reportedVmid != null && reportedVmid != guest.vmid) {
      throw const FormatException(
        'Backup record reports a mismatched guest VMID.',
      );
    }

    final sizeBytes = asInteger(json['size']);
    if (sizeBytes != null && sizeBytes < 0) {
      throw const FormatException('Backup record reports an invalid size.');
    }

    return GuestBackupArchive(
      node: guest.node,
      storage: storage,
      volid: volid,
      kind: identity.kind,
      vmid: identity.vmid,
      format: _backupArchiveText(json['format'], maxLength: 64),
      sizeBytes: sizeBytes,
      createdAt: asUnixSeconds(json['ctime']),
      protected: asFlag(json['protected']),
    );
  }
}

class GuestBackupArchiveInventory {
  const GuestBackupArchiveInventory({
    required this.storage,
    required this.archives,
    this.ignoredRecords = 0,
    this.truncated = false,
  });

  final String storage;
  final List<GuestBackupArchive> archives;
  final int ignoredRecords;
  final bool truncated;

  GuestBackupArchive? get latest => archives.isEmpty ? null : archives.first;
}

enum BackupValidationConfidence { notAssessed, insufficient, partial }

enum BackupTaskEvidence { none, running, succeeded, failed, unknown }

class GuestBackupValidationAssessment {
  const GuestBackupValidationAssessment({
    required this.confidence,
    required this.visibleArchiveCount,
    required this.ignoredArchiveRows,
    required this.archiveListTruncated,
    required this.taskEvidence,
    this.latestArchive,
    this.latestBackupTask,
  });

  final BackupValidationConfidence confidence;
  final int visibleArchiveCount;
  final int ignoredArchiveRows;
  final bool archiveListTruncated;
  final GuestBackupArchive? latestArchive;
  final BackupTaskEvidence taskEvidence;
  final RecentServerTask? latestBackupTask;

  bool get archiveReadCompleted =>
      confidence != BackupValidationConfidence.notAssessed;
  bool get hasVisibleArchive => latestArchive != null;

  String get headline => switch (confidence) {
    BackupValidationConfidence.notAssessed => 'Not assessed',
    BackupValidationConfidence.insufficient => 'Insufficient evidence',
    BackupValidationConfidence.partial => 'Partial evidence',
  };

  static GuestBackupValidationAssessment evaluate({
    required GuestBackupArchiveInventory? archives,
    required Iterable<RecentServerTask> backupTasks,
  }) {
    final tasks = backupTasks.toList(growable: false)
      ..sort((a, b) {
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
    final latestTask = tasks.isEmpty ? null : tasks.first;
    final taskEvidence = latestTask == null
        ? BackupTaskEvidence.none
        : latestTask.status == 'running'
        ? BackupTaskEvidence.running
        : !latestTask.isDone
        ? BackupTaskEvidence.unknown
        : latestTask.exitStatus == 'OK'
        ? BackupTaskEvidence.succeeded
        : latestTask.exitStatus == null
        ? BackupTaskEvidence.unknown
        : BackupTaskEvidence.failed;

    if (archives == null) {
      return GuestBackupValidationAssessment(
        confidence: BackupValidationConfidence.notAssessed,
        visibleArchiveCount: 0,
        ignoredArchiveRows: 0,
        archiveListTruncated: false,
        taskEvidence: taskEvidence,
        latestBackupTask: latestTask,
      );
    }

    final latestArchive = archives.latest;
    return GuestBackupValidationAssessment(
      confidence: latestArchive == null
          ? BackupValidationConfidence.insufficient
          : BackupValidationConfidence.partial,
      visibleArchiveCount: archives.archives.length,
      ignoredArchiveRows: archives.ignoredRecords,
      archiveListTruncated: archives.truncated,
      latestArchive: latestArchive,
      taskEvidence: taskEvidence,
      latestBackupTask: latestTask,
    );
  }
}

class GuestRestorePlanRequest {
  const GuestRestorePlanRequest({
    required this.targetNode,
    required this.targetVmid,
    required this.targetStorage,
  });

  final String targetNode;
  final int targetVmid;
  final String targetStorage;

  String? get validationError {
    final node = targetNode.trim();
    if (node.isEmpty ||
        node.length > 64 ||
        !RegExp(
          r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$',
        ).hasMatch(node)) {
      return 'Target node is invalid.';
    }
    if (targetVmid < 100 || targetVmid > 999999999) {
      return 'Target VMID must be between 100 and 999999999.';
    }
    final storage = targetStorage.trim();
    if (storage.isEmpty ||
        storage.length > 64 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$').hasMatch(storage)) {
      return 'Target storage identifier is invalid.';
    }
    return null;
  }

  bool get isValid => validationError == null;

  GuestRestorePlanRequest normalized() => GuestRestorePlanRequest(
    targetNode: targetNode.trim(),
    targetVmid: targetVmid,
    targetStorage: targetStorage.trim(),
  );
}

enum GuestRestorePlanStatus { blocked, preflightComplete }

/// Read-only restore planning evidence.
///
/// This object never authorizes or submits a restore. It records a point-in-time
/// conflict/ACL/storage preflight for one already identity-checked archive.
class GuestRestorePlanPreflight {
  const GuestRestorePlanPreflight({
    required this.sourceArchive,
    required this.targetNode,
    required this.targetVmid,
    required this.targetStorage,
    required this.status,
    required this.sourceArchiveVisible,
    required this.sourceStorageUsable,
    required this.targetNodeOnline,
    required this.targetVmidAvailable,
    required this.targetStorageUsable,
    required this.vmAllocateAvailable,
    required this.datastoreAllocateSpaceAvailable,
    required this.storageReadComplete,
    this.targetStorageAvailableBytes,
    this.blockers = const <String>[],
  });

  final GuestBackupArchive sourceArchive;
  final String targetNode;
  final int targetVmid;
  final String targetStorage;
  final GuestRestorePlanStatus status;
  final bool sourceArchiveVisible;
  final bool sourceStorageUsable;
  final bool targetNodeOnline;
  final bool targetVmidAvailable;
  final bool targetStorageUsable;
  final bool vmAllocateAvailable;
  final bool datastoreAllocateSpaceAvailable;
  final bool storageReadComplete;
  final int? targetStorageAvailableBytes;
  final List<String> blockers;

  bool get preflightComplete =>
      status == GuestRestorePlanStatus.preflightComplete;

  String get headline => switch (status) {
    GuestRestorePlanStatus.blocked => 'Blocked',
    GuestRestorePlanStatus.preflightComplete => 'Preflight complete',
  };
}

class GuestSnapshotCreateRequest {
  const GuestSnapshotCreateRequest({required this.name});

  final String name;

  String? get validationError {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 64) {
      return 'Snapshot name must be 1 to 64 characters.';
    }
    if (normalized.toLowerCase() == 'current') {
      return 'Snapshot name "current" is reserved by Proxmox.';
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(normalized)) {
      return 'Snapshot name may contain letters, numbers, underscores, and hyphens.';
    }
    return null;
  }

  bool get isValid => validationError == null;

  GuestSnapshotCreateRequest normalized() =>
      GuestSnapshotCreateRequest(name: name.trim());
}

class GuestBackupRequest {
  const GuestBackupRequest({required this.storage});

  final String storage;

  String? get validationError {
    final normalized = storage.trim();
    if (normalized.isEmpty || normalized.length > 64) {
      return 'Choose a backup storage.';
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$').hasMatch(normalized)) {
      return 'Backup storage identifier is invalid.';
    }
    return null;
  }

  bool get isValid => validationError == null;

  GuestBackupRequest normalized() =>
      GuestBackupRequest(storage: storage.trim());
}

bool _validPermissionPropagationFlag(Object? value) {
  if (value is bool) return true;
  if (value is num) return value == 0 || value == 1;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == '0' ||
        normalized == '1' ||
        normalized == 'false' ||
        normalized == 'true';
  }
  return false;
}

/// Transient effective permissions for one exact PVE guest ACL path.
///
/// Presence of a privilege means PVE reported it as effective at `/vms/<vmid>`.
/// The returned propagation flag is validated but intentionally not interpreted:
/// a non-propagating privilege is still effective at the exact requested path.
class GuestPermissionSnapshot {
  const GuestPermissionSnapshot({
    required this.privileges,
    this.malformedPrivileges = 0,
    this.truncated = false,
  });

  final Set<String> privileges;
  final int malformedPrivileges;
  final bool truncated;

  bool has(String privilege) => privileges.contains(privilege);

  factory GuestPermissionSnapshot.fromApi(
    Map<String, dynamic> json, {
    required int vmid,
  }) => GuestPermissionSnapshot.fromApiPath(json, path: '/vms/$vmid');

  factory GuestPermissionSnapshot.fromApiPath(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty || !normalizedPath.startsWith('/')) {
      throw const FormatException('Permission path is invalid.');
    }
    final raw = json[normalizedPath];
    if (raw == null) {
      return const GuestPermissionSnapshot(privileges: <String>{});
    }
    if (raw is! Map) {
      throw const FormatException('Permission map is malformed.');
    }

    const privilegeLimit = 128;
    final valid = <String>[];
    var malformed = 0;
    final privilegePattern = RegExp(r'^[A-Za-z][A-Za-z0-9.]{0,79}$');
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String ||
          !privilegePattern.hasMatch(key) ||
          !_validPermissionPropagationFlag(entry.value)) {
        malformed++;
        continue;
      }
      valid.add(key);
    }
    valid.sort();
    return GuestPermissionSnapshot(
      privileges: Set<String>.unmodifiable(valid.take(privilegeLimit)),
      malformedPrivileges: malformed,
      truncated: valid.length > privilegeLimit,
    );
  }
}

String? _configurationValue(Object? value) {
  String? raw;
  if (value is String) {
    raw = value;
  } else if (value is num || value is bool) {
    raw = value.toString();
  } else {
    return null;
  }
  final cleaned = raw
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
      .trim();
  if (cleaned.isEmpty) return null;
  return cleaned.length <= 300 ? cleaned : '${cleaned.substring(0, 300)}…';
}

class GuestConfigurationField {
  const GuestConfigurationField({
    required this.key,
    required this.label,
    required this.value,
  });

  final String key;
  final String label;
  final String value;
}

/// Transient, read-only subset of a PVE guest config.
///
/// Only explicitly reviewed fields are surfaced. Free-form or sensitive fields
/// such as passwords, SSH keys, arbitrary args, hooks and unknown future keys
/// are intentionally not copied into this model.
class GuestConfiguration {
  const GuestConfiguration({
    required this.compute,
    required this.platform,
    required this.storage,
    required this.network,
    required this.withheldFields,
    required this.malformedFields,
    required this.truncated,
  });

  final List<GuestConfigurationField> compute;
  final List<GuestConfigurationField> platform;
  final List<GuestConfigurationField> storage;
  final List<GuestConfigurationField> network;
  final int withheldFields;
  final int malformedFields;
  final bool truncated;

  int get visibleFieldCount =>
      compute.length + platform.length + storage.length + network.length;

  factory GuestConfiguration.fromApi(
    Map<String, dynamic> json, {
    required String kind,
  }) {
    if (kind != 'qemu' && kind != 'lxc') {
      throw const FormatException('Unsupported guest configuration kind.');
    }

    final compute = <GuestConfigurationField>[];
    final platform = <GuestConfigurationField>[];
    final storage = <GuestConfigurationField>[];
    final network = <GuestConfigurationField>[];
    final consumed = <String>{};
    var malformed = 0;
    var truncated = false;

    void add(String key, String label, List<GuestConfigurationField> target) {
      if (!json.containsKey(key)) return;
      consumed.add(key);
      final value = _configurationValue(json[key]);
      if (value == null) {
        malformed++;
        return;
      }
      target.add(GuestConfigurationField(key: key, label: label, value: value));
    }

    add('cores', 'CPU cores', compute);
    add('memory', 'Memory (MiB)', compute);
    add('onboot', 'Start at boot', platform);
    add('protection', 'Protected', platform);
    add('startup', 'Startup order/delay', platform);

    if (kind == 'qemu') {
      add('sockets', 'CPU sockets', compute);
      add('vcpus', 'Virtual CPUs', compute);
      add('balloon', 'Balloon minimum (MiB)', compute);
      add('cpu', 'CPU type', platform);
      add('bios', 'Firmware', platform);
      add('machine', 'Machine type', platform);
      add('ostype', 'Guest OS type', platform);
      add('agent', 'QEMU guest agent', platform);
      add('scsihw', 'SCSI controller', platform);
      add('numa', 'NUMA', platform);
      add('boot', 'Boot order', platform);
      add('hotplug', 'Hotplug', platform);
    } else {
      add('hostname', 'Hostname', platform);
      add('swap', 'Swap (MiB)', compute);
      add('arch', 'Architecture', platform);
      add('ostype', 'Container OS type', platform);
      add('unprivileged', 'Unprivileged container', platform);
      add('features', 'Container features', platform);
      add('console', 'Console', platform);
      add('tty', 'TTY count', platform);
    }

    final storagePattern = kind == 'qemu'
        ? RegExp(r'^(?:ide|sata|scsi|virtio|efidisk|tpmstate|unused)\d+$')
        : RegExp(r'^(?:mp|unused)\d+$');
    final storageKeys =
        json.keys
            .where(
              (key) =>
                  storagePattern.hasMatch(key) ||
                  (kind == 'lxc' && key == 'rootfs'),
            )
            .toList()
          ..sort();
    if (storageKeys.length > 32) truncated = true;
    for (final key in storageKeys.take(32)) {
      add(key, key == 'rootfs' ? 'Root filesystem' : key, storage);
    }

    final networkKeys =
        json.keys
            .where(
              (key) =>
                  RegExp(r'^net\d+$').hasMatch(key) ||
                  (kind == 'qemu' && RegExp(r'^ipconfig\d+$').hasMatch(key)),
            )
            .toList()
          ..sort();
    if (networkKeys.length > 32) truncated = true;
    for (final key in networkKeys.take(32)) {
      add(key, key.startsWith('ipconfig') ? 'Cloud-init $key' : key, network);
    }

    return GuestConfiguration(
      compute: List<GuestConfigurationField>.unmodifiable(compute),
      platform: List<GuestConfigurationField>.unmodifiable(platform),
      storage: List<GuestConfigurationField>.unmodifiable(storage),
      network: List<GuestConfigurationField>.unmodifiable(network),
      withheldFields: json.length - consumed.length,
      malformedFields: malformed,
      truncated: truncated,
    );
  }
}

class Guest {
  const Guest({
    required this.node,
    required this.vmid,
    required this.kind,
    required this.name,
    required this.status,
    this.isTemplate = false,
    this.cpu,
    this.mem,
    this.maxMem,
    this.disk,
    this.maxDisk,
    this.uptime,
    this.netIn,
    this.netOut,
    this.diskRead,
    this.diskWrite,
    this.tags = const <String>[],
    this.pool,
  });
  final String node;
  final int vmid;
  final String kind; // qemu or lxc
  final String name;
  final String status;
  final bool isTemplate;
  final double? cpu; // PVE fractional CPU usage, not percent
  final int? mem;
  final int? maxMem;
  final int? disk;
  final int? maxDisk;
  final int? uptime;
  // Optional cumulative bytes from /cluster/resources, not bytes per second.
  final int? netIn;
  final int? netOut;
  final int? diskRead;
  final int? diskWrite;
  final List<String> tags;
  final String? pool;

  bool get isRunning => status == 'running';
  bool get isStopped => status == 'stopped';

  factory Guest.fromResource(Map<String, dynamic> json) {
    final kind = asText(json['type']);
    if (kind != 'qemu' && kind != 'lxc') {
      throw const FormatException('Unexpected guest kind.');
    }
    final vmid = asInteger(json['vmid']);
    final node = asText(json['node']);
    if (vmid == null || vmid < 1 || node == null || node.trim().isEmpty) {
      throw const FormatException('Guest is missing node or VMID.');
    }
    final rawName = asText(json['name']);
    final template = asFlag(json['template']);
    if (json.containsKey('template') && template == null) {
      throw const FormatException('Guest has an invalid template marker.');
    }
    return Guest(
      node: node,
      vmid: vmid,
      kind: kind!,
      name: rawName != null && rawName.trim().isNotEmpty
          ? rawName
          : '$kind $vmid',
      status: asText(json['status']) ?? 'unknown',
      isTemplate: template == true,
      cpu: asDouble(json['cpu']),
      mem: asInteger(json['mem']),
      maxMem: asInteger(json['maxmem']),
      disk: asInteger(json['disk']),
      maxDisk: asInteger(json['maxdisk']),
      uptime: asInteger(json['uptime']),
      netIn: _guestByteCounter(json['netin']),
      netOut: _guestByteCounter(json['netout']),
      diskRead: _guestByteCounter(json['diskread']),
      diskWrite: _guestByteCounter(json['diskwrite']),
      tags: _guestTags(json['tags']),
      pool: _guestPool(json['pool']),
    );
  }
}

class Node {
  const Node({
    required this.name,
    required this.status,
    this.cpu,
    this.mem,
    this.maxMem,
    this.uptime,
  });
  final String name;
  final String status;
  final double? cpu;
  final int? mem;
  final int? maxMem;
  final int? uptime;

  factory Node.fromResource(Map<String, dynamic> json) => Node(
    name: asText(json['node']) ?? asText(json['id']) ?? 'Unknown',
    status: asText(json['status']) ?? 'unknown',
    cpu: asDouble(json['cpu']),
    mem: asInteger(json['mem']),
    maxMem: asInteger(json['maxmem']),
    uptime: asInteger(json['uptime']),
  );
}

class Inventory {
  const Inventory({
    required this.nodes,
    required this.guests,
    required this.fetchedAt,
    this.malformedGuestRecords = 0,
  });
  final List<Node> nodes;
  final List<Guest> guests;
  final DateTime fetchedAt;
  final int malformedGuestRecords;

  factory Inventory.fromResources(List<dynamic> values, {DateTime? fetchedAt}) {
    final nodes = <Node>[];
    final guests = <Guest>[];
    final vmids = <int>{};
    var malformedGuestRecords = 0;
    for (final entry in values) {
      if (entry is! Map<String, dynamic>) {
        malformedGuestRecords++;
        continue;
      }
      final kind = entry['type'];
      if (kind == 'node') {
        nodes.add(Node.fromResource(entry));
      } else if (kind == 'qemu' || kind == 'lxc') {
        try {
          final guest = Guest.fromResource(entry);
          if (!vmids.add(guest.vmid)) malformedGuestRecords++;
          guests.add(guest);
        } on FormatException {
          malformedGuestRecords++;
          continue;
        }
      }
    }
    nodes.sort((a, b) => a.name.compareTo(b.name));
    guests.sort((a, b) => a.vmid.compareTo(b.vmid));
    return Inventory(
      nodes: List.unmodifiable(nodes),
      guests: List.unmodifiable(guests),
      fetchedAt: fetchedAt ?? DateTime.now(),
      malformedGuestRecords: malformedGuestRecords,
    );
  }
}

enum GuestAction { start, shutdown, reboot, stop }

extension GuestActionLabel on GuestAction {
  String get label => switch (this) {
    GuestAction.start => 'Start',
    GuestAction.shutdown => 'Shut down',
    GuestAction.reboot => 'Reboot',
    GuestAction.stop => 'Force stop',
  };

  String get apiAction => name;
  bool allowedFor(Guest guest) =>
      !guest.isTemplate &&
      (this == GuestAction.start ? guest.isStopped : guest.isRunning);
}

String? _guestProvisioningNameError(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty || normalized.length > 63) {
    return 'Name must be 1 to 63 characters.';
  }
  final validName = RegExp(
    r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
  ).hasMatch(normalized);
  if (!validName) {
    return 'Name may contain letters, numbers, and hyphens, and cannot start or end with a hyphen.';
  }
  return null;
}

class GuestCloneRequest {
  const GuestCloneRequest({required this.newVmid, required this.name});

  final int newVmid;
  final String name;

  String? get validationError {
    if (newVmid < 100 || newVmid > 999999999) {
      return 'VMID must be between 100 and 999999999.';
    }
    return _guestProvisioningNameError(name);
  }

  bool get isValid => validationError == null;

  GuestCloneRequest normalized() =>
      GuestCloneRequest(newVmid: newVmid, name: name.trim());
}

class QemuCreateRequest {
  const QemuCreateRequest({
    required this.node,
    required this.vmid,
    required this.name,
    required this.cores,
    required this.memoryMiB,
    this.onBoot = false,
  });

  final String node;
  final int vmid;
  final String name;
  final int cores;
  final int memoryMiB;
  final bool onBoot;

  String? get validationError {
    final normalizedNode = node.trim();
    if (normalizedNode.isEmpty ||
        normalizedNode.length > 64 ||
        !RegExp(
          r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$',
        ).hasMatch(normalizedNode)) {
      return 'Select a valid destination node.';
    }
    if (vmid < 100 || vmid > 999999999) {
      return 'VMID must be between 100 and 999999999.';
    }
    final nameError = _guestProvisioningNameError(name);
    if (nameError != null) return nameError;
    if (cores < 1 || cores > 64) {
      return 'CPU cores must be between 1 and 64.';
    }
    if (memoryMiB < 128 || memoryMiB > 262144) {
      return 'Memory must be between 128 MiB and 262144 MiB.';
    }
    return null;
  }

  bool get isValid => validationError == null;

  QemuCreateRequest normalized() => QemuCreateRequest(
    node: node.trim(),
    vmid: vmid,
    name: name.trim(),
    cores: cores,
    memoryMiB: memoryMiB,
    onBoot: onBoot,
  );
}

class LxcTemplate {
  const LxcTemplate({
    required this.node,
    required this.storage,
    required this.volid,
    this.format,
    this.sizeBytes,
  });

  final String node;
  final String storage;
  final String volid;
  final String? format;
  final int? sizeBytes;

  String get displayName {
    final slash = volid.lastIndexOf('/');
    return slash >= 0 && slash + 1 < volid.length
        ? volid.substring(slash + 1)
        : volid;
  }

  factory LxcTemplate.fromApi(
    Map<String, dynamic> json, {
    required String node,
    required String storage,
  }) {
    final volid = asText(json['volid']);
    final prefix = '$storage:vztmpl/';
    if (volid == null || !volid.startsWith(prefix) || volid.length > 255) {
      throw const FormatException('Container template volume is invalid.');
    }
    final size = asInteger(json['size']) ?? asInteger(json['approximate-size']);
    if (size != null && size < 0) {
      throw const FormatException('Container template size is invalid.');
    }
    return LxcTemplate(
      node: node,
      storage: storage,
      volid: volid,
      format: asText(json['format']),
      sizeBytes: size,
    );
  }
}

class LxcCreateOptions {
  const LxcCreateOptions({
    required this.rootfsStorages,
    required this.templates,
    this.incomplete = false,
  });

  final List<String> rootfsStorages;
  final List<LxcTemplate> templates;
  final bool incomplete;

  bool supports(LxcCreateRequest request) =>
      rootfsStorages.contains(request.rootfsStorage) &&
      templates.any(
        (template) =>
            template.node == request.node &&
            template.volid == request.templateVolid,
      );
}

class LxcCreateRequest {
  const LxcCreateRequest({
    required this.node,
    required this.vmid,
    required this.hostname,
    required this.cores,
    required this.memoryMiB,
    required this.templateVolid,
    required this.rootfsStorage,
    this.onBoot = false,
  });

  final String node;
  final int vmid;
  final String hostname;
  final int cores;
  final int memoryMiB;
  final String templateVolid;
  final String rootfsStorage;
  final bool onBoot;

  String get templateStorage {
    final separator = templateVolid.indexOf(':');
    return separator <= 0 ? '' : templateVolid.substring(0, separator);
  }

  String? get validationError {
    final normalizedNode = node.trim();
    if (normalizedNode.isEmpty ||
        normalizedNode.length > 64 ||
        !RegExp(
          r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$',
        ).hasMatch(normalizedNode)) {
      return 'Select a valid destination node.';
    }
    if (vmid < 100 || vmid > 999999999) {
      return 'VMID must be between 100 and 999999999.';
    }
    final hostnameError = _guestProvisioningNameError(hostname);
    if (hostnameError != null) return hostnameError;
    if (cores < 1 || cores > 64) {
      return 'CPU cores must be between 1 and 64.';
    }
    if (memoryMiB < 128 || memoryMiB > 262144) {
      return 'Memory must be between 128 MiB and 262144 MiB.';
    }
    final normalizedStorage = rootfsStorage.trim();
    if (normalizedStorage.isEmpty ||
        normalizedStorage.length > 64 ||
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$',
        ).hasMatch(normalizedStorage)) {
      return 'Select a valid root filesystem storage.';
    }
    final normalizedTemplate = templateVolid.trim();
    if (normalizedTemplate.isEmpty ||
        normalizedTemplate.length > 255 ||
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}:vztmpl/\S+$',
        ).hasMatch(normalizedTemplate)) {
      return 'Select a valid container template.';
    }
    return null;
  }

  bool get isValid => validationError == null;

  LxcCreateRequest normalized() => LxcCreateRequest(
    node: node.trim(),
    vmid: vmid,
    hostname: hostname.trim(),
    cores: cores,
    memoryMiB: memoryMiB,
    templateVolid: templateVolid.trim(),
    rootfsStorage: rootfsStorage.trim(),
    onBoot: onBoot,
  );
}

class GuestMigrationRequest {
  const GuestMigrationRequest({required this.targetNode});

  final String targetNode;

  String? get validationError {
    final normalized = targetNode.trim();
    if (normalized.isEmpty ||
        normalized.length > 64 ||
        !RegExp(
          r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$',
        ).hasMatch(normalized)) {
      return 'Select a valid destination node.';
    }
    return null;
  }

  bool get isValid => validationError == null;

  GuestMigrationRequest normalized() =>
      GuestMigrationRequest(targetNode: targetNode.trim());
}

class GuestMigrationPreflight {
  const GuestMigrationPreflight({
    required this.running,
    required this.allowedNodes,
    this.localDiskCount = 0,
    this.localResources = const <String>[],
    this.incomplete = false,
  });

  final bool running;
  final List<String> allowedNodes;
  final int localDiskCount;
  final List<String> localResources;
  final bool incomplete;

  bool allowsTarget(String node) => allowedNodes.contains(node);

  factory GuestMigrationPreflight.fromApi(
    Map<String, dynamic> json, {
    required String kind,
  }) {
    if (kind != 'qemu' && kind != 'lxc') {
      throw const FormatException('Unsupported guest kind.');
    }
    final running = asFlag(json['running']);
    if (running == null) {
      throw const FormatException('Migration preflight is missing run state.');
    }

    var incomplete = false;
    final allowedKey = kind == 'qemu' ? 'allowed_nodes' : 'allowed-nodes';
    final rawAllowed = json[allowedKey];
    final allowed = <String>[];
    if (rawAllowed is! List) {
      incomplete = true;
    } else {
      for (final item in rawAllowed) {
        final value = asText(item)?.trim();
        if (value == null ||
            value.isEmpty ||
            value.length > 64 ||
            !RegExp(
              r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$',
            ).hasMatch(value)) {
          incomplete = true;
          continue;
        }
        if (!allowed.contains(value)) allowed.add(value);
      }
    }

    var localDiskCount = 0;
    final localResources = <String>[];
    if (kind == 'qemu') {
      final rawDisks = json['local_disks'];
      if (rawDisks is! List) {
        incomplete = true;
      } else {
        for (final item in rawDisks) {
          if (item is Map) {
            localDiskCount++;
          } else {
            incomplete = true;
          }
        }
      }
      final rawResources = json['local_resources'];
      if (rawResources is! List) {
        incomplete = true;
      } else {
        for (final item in rawResources) {
          final value = asText(item)?.trim();
          if (value == null || value.isEmpty) {
            incomplete = true;
            continue;
          }
          localResources.add(value);
        }
      }
    }

    allowed.sort();
    localResources.sort();
    return GuestMigrationPreflight(
      running: running,
      allowedNodes: List<String>.unmodifiable(allowed),
      localDiskCount: localDiskCount,
      localResources: List<String>.unmodifiable(localResources),
      incomplete: incomplete,
    );
  }
}

enum OperationOutcome { running, succeeded, failed, unknown }

class TrackedTask {
  const TrackedTask({
    required this.upid,
    required this.node,
    required this.title,
    required this.startedAt,
    required this.outcome,
    this.detail,
  });
  final String upid;
  final String node;
  final String title;
  final DateTime startedAt;
  final OperationOutcome outcome;
  final String? detail;

  TrackedTask withOutcome(OperationOutcome next, {String? detail}) =>
      TrackedTask(
        upid: upid,
        node: node,
        title: title,
        startedAt: startedAt,
        outcome: next,
        detail: detail,
      );
}

class ServerTaskStatus {
  const ServerTaskStatus({required this.status, this.exitStatus});
  final String status;
  final String? exitStatus;
  bool get isDone => status == 'stopped';
  bool get succeeded => isDone && exitStatus == 'OK';
}

// Transport diagnoses describe an observed request failure, not device state.
enum PveTransportFailure {
  dnsFailure,
  networkUnreachable,
  connectTimeout,
  responseTimeout,
  connectionLost,
}

class PveFailure implements Exception {
  const PveFailure(
    this.message, {
    this.status,
    this.mayHaveExecuted = false,
    this.transportFailure,
  });
  final String message;
  final int? status;
  final bool mayHaveExecuted;
  final PveTransportFailure? transportFailure;

  @override
  String toString() => message;
}

String formatBytes(int? bytes) {
  if (bytes == null || bytes < 0) return '—';
  final units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${index == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)} ${units[index]}';
}

String formatPercent(double? fraction) {
  if (fraction == null || !fraction.isFinite || fraction < 0) return '—';
  final display = fraction.clamp(0.0, 1.0).toDouble();
  return '${(display * 100).toStringAsFixed(1)}%';
}

String formatUptime(int? seconds) {
  if (seconds == null || seconds < 0) return '—';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '${seconds}s';
}

String formatAge(DateTime time, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.isNegative || diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} days ago';
}
