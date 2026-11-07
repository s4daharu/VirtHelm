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

class Guest {
  const Guest({
    required this.node,
    required this.vmid,
    required this.kind,
    required this.name,
    required this.status,
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
    return Guest(
      node: node,
      vmid: vmid,
      kind: kind!,
      name: rawName != null && rawName.trim().isNotEmpty
          ? rawName
          : '$kind $vmid',
      status: asText(json['status']) ?? 'unknown',
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
          guests.add(Guest.fromResource(entry));
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
      this == GuestAction.start ? guest.isStopped : guest.isRunning;
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
