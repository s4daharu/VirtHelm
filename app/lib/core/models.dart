import 'dart:convert';
import 'dart:math';

/// Profile metadata is deliberately separate from encrypted API credentials.
class ConnectionProfile {
  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.endpoint,
  });

  final String id;
  final String name;
  final String endpoint;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'endpoint': endpoint,
      };

  factory ConnectionProfile.fromJson(Map<String, dynamic> json) =>
      ConnectionProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        endpoint: json['endpoint'] as String,
      );

  static ConnectionProfile create({required String name, required String address}) {
    final id = '${DateTime.now().microsecondsSinceEpoch}_'
        '${Random.secure().nextInt(0x7fffffff)}';
    if (name.trim().isEmpty) {
      throw const FormatException('Enter a profile name.');
    }
    return ConnectionProfile(
      id: id,
      name: name.trim(),
      endpoint: normalizePveEndpoint(address),
    );
  }
}

/// First milestone only supports a direct PVE host:port (not reverse-proxy paths).
/// No HTTP, URL-embedded credentials, redirects, query strings, or fragments.
String normalizePveEndpoint(String input) {
  final uri = Uri.tryParse(input.trim());
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
  final port = uri.hasPort ? uri.port : 8006;
  if (port <= 0 || port > 65535) {
    throw const FormatException('Invalid server port.');
  }
  return Uri(scheme: 'https', host: uri.host, port: port)
      .toString()
      .replaceFirst(RegExp(r'/$'), '');
}

class ApiCredentials {
  const ApiCredentials({required this.tokenId, required this.secret});
  final String tokenId;
  final String secret;

  String get header => 'PVEAPIToken=$tokenId=$secret';

  bool get isValid =>
      RegExp(r'^[^\s!@]+@[^\s!@]+![^\s!=]+$').hasMatch(tokenId) &&
      secret.trim().isNotEmpty;

  String encode() => jsonEncode({'id': tokenId, 'secret': secret});

  factory ApiCredentials.decode(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return ApiCredentials(
      tokenId: map['id'] as String,
      secret: map['secret'] as String,
    );
  }
}

int? asInteger(Object? value) => value is num ? value.toInt() : null;
double? asDouble(Object? value) => value is num ? value.toDouble() : null;
String? asText(Object? value) => value is String ? value : null;

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

  bool get isRunning => status == 'running';
  bool get isStopped => status == 'stopped';

  factory Guest.fromResource(Map<String, dynamic> json) {
    final kind = asText(json['type']);
    if (kind != 'qemu' && kind != 'lxc') {
      throw const FormatException('Unexpected guest kind.');
    }
    final vmid = asInteger(json['vmid']);
    final node = asText(json['node']);
    if (vmid == null || node == null || node.isEmpty) {
      throw const FormatException('Guest is missing node or VMID.');
    }
    final rawName = asText(json['name']);
    return Guest(
      node: node,
      vmid: vmid,
      kind: kind!,
      name: rawName != null && rawName.trim().isNotEmpty ? rawName : '$kind $vmid',
      status: asText(json['status']) ?? 'unknown',
      cpu: asDouble(json['cpu']),
      mem: asInteger(json['mem']),
      maxMem: asInteger(json['maxmem']),
      disk: asInteger(json['disk']),
      maxDisk: asInteger(json['maxdisk']),
    );
  }
}

class Node {
  const Node({required this.name, required this.status, this.cpu, this.mem, this.maxMem});
  final String name;
  final String status;
  final double? cpu;
  final int? mem;
  final int? maxMem;

  factory Node.fromResource(Map<String, dynamic> json) => Node(
        name: asText(json['node']) ?? asText(json['id']) ?? 'Unknown',
        status: asText(json['status']) ?? 'unknown',
        cpu: asDouble(json['cpu']),
        mem: asInteger(json['mem']),
        maxMem: asInteger(json['maxmem']),
      );
}

class Inventory {
  const Inventory({required this.nodes, required this.guests, required this.fetchedAt});
  final List<Node> nodes;
  final List<Guest> guests;
  final DateTime fetchedAt;

  factory Inventory.fromResources(List<dynamic> values, {DateTime? fetchedAt}) {
    final nodes = <Node>[];
    final guests = <Guest>[];
    for (final entry in values) {
      if (entry is! Map<String, dynamic>) continue;
      final kind = entry['type'];
      if (kind == 'node') {
        nodes.add(Node.fromResource(entry));
      } else if (kind == 'qemu' || kind == 'lxc') {
        try {
          guests.add(Guest.fromResource(entry));
        } on FormatException {
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

  TrackedTask withOutcome(OperationOutcome next, {String? detail}) => TrackedTask(
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

class PveFailure implements Exception {
  const PveFailure(this.message, {this.status, this.mayHaveExecuted = false});
  final String message;
  final int? status;
  final bool mayHaveExecuted;

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

String formatPercent(double? fraction) => fraction == null || !fraction.isFinite
    ? '—'
    : '${(fraction * 100).toStringAsFixed(1)}%';
