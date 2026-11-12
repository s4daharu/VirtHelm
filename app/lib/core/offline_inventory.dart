import 'models.dart';

const maxOfflineInventoryNodes = 256;
const maxOfflineInventoryGuests = 5000;
const maxOfflineInventorySerializedBytes = 512 * 1024;

String? _safeOfflineIdentity(Object? value, {int maxLength = 128}) {
  if (value is! String) return null;
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > maxLength ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

String _offlineStatus(Object? value) {
  final normalized = _safeOfflineIdentity(value, maxLength: 32);
  return normalized ?? 'unknown';
}

/// Display-only stale node identity. No metrics, addresses or authorization.
class OfflineInventoryNode {
  const OfflineInventoryNode({required this.name, required this.status});

  final String name;
  final String status;

  Map<String, Object> toJson() => {'name': name, 'status': status};

  static OfflineInventoryNode? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> || raw.length != 2) return null;
    final name = _safeOfflineIdentity(raw['name']);
    if (name == null) return null;
    return OfflineInventoryNode(
      name: name,
      status: _offlineStatus(raw['status']),
    );
  }
}

/// Display-only stale guest identity. Deliberately excludes metrics, tags,
/// pools, storage, configuration, task data, credentials and raw API payloads.
class OfflineInventoryGuest {
  const OfflineInventoryGuest({
    required this.node,
    required this.vmid,
    required this.kind,
    required this.name,
    required this.status,
    required this.isTemplate,
  });

  final String node;
  final int vmid;
  final String kind;
  final String name;
  final String status;
  final bool isTemplate;

  bool get isRunning => status == 'running';
  bool get isStopped => status == 'stopped';

  Map<String, Object> toJson() => {
    'node': node,
    'vmid': vmid,
    'kind': kind,
    'name': name,
    'status': status,
    'template': isTemplate,
  };

  static OfflineInventoryGuest? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> || raw.length != 6) return null;
    final node = _safeOfflineIdentity(raw['node']);
    final name = _safeOfflineIdentity(raw['name']);
    final vmid = raw['vmid'];
    final kind = raw['kind'];
    final template = raw['template'];
    if (node == null ||
        name == null ||
        vmid is! int ||
        vmid < 1 ||
        vmid > 999999999 ||
        (kind != 'qemu' && kind != 'lxc') ||
        template is! bool) {
      return null;
    }
    return OfflineInventoryGuest(
      node: node,
      vmid: vmid,
      kind: kind as String,
      name: name,
      status: _offlineStatus(raw['status']),
      isTemplate: template,
    );
  }
}

/// Explicitly opted-in stale inventory cache. This is never converted into a
/// live [Inventory] and must never authorize mutations or detail reads.
class OfflineInventorySnapshot {
  const OfflineInventorySnapshot({
    required this.fetchedAt,
    required this.nodes,
    required this.guests,
  });

  static const maxAge = Duration(hours: 24);

  final DateTime fetchedAt;
  final List<OfflineInventoryNode> nodes;
  final List<OfflineInventoryGuest> guests;

  int get totalGuests => guests.where((guest) => !guest.isTemplate).length;
  int get runningGuests =>
      guests.where((guest) => !guest.isTemplate && guest.isRunning).length;
  int get stoppedGuests =>
      guests.where((guest) => !guest.isTemplate && guest.isStopped).length;
  int get onlineNodes => nodes.where((node) => node.status == 'online').length;

  static OfflineInventorySnapshot? fromInventory(Inventory inventory) {
    if (inventory.nodes.length > maxOfflineInventoryNodes ||
        inventory.guests.length > maxOfflineInventoryGuests ||
        inventory.malformedGuestRecords != 0) {
      return null;
    }
    final nodes = <OfflineInventoryNode>[];
    final nodeNames = <String>{};
    for (final node in inventory.nodes) {
      final name = _safeOfflineIdentity(node.name);
      if (name == null || !nodeNames.add(name)) return null;
      nodes.add(
        OfflineInventoryNode(name: name, status: _offlineStatus(node.status)),
      );
    }

    final guests = <OfflineInventoryGuest>[];
    final vmids = <int>{};
    for (final guest in inventory.guests) {
      final node = _safeOfflineIdentity(guest.node);
      final name = _safeOfflineIdentity(guest.name);
      if (node == null ||
          name == null ||
          guest.vmid < 1 ||
          guest.vmid > 999999999 ||
          (guest.kind != 'qemu' && guest.kind != 'lxc') ||
          !vmids.add(guest.vmid)) {
        return null;
      }
      guests.add(
        OfflineInventoryGuest(
          node: node,
          vmid: guest.vmid,
          kind: guest.kind,
          name: name,
          status: _offlineStatus(guest.status),
          isTemplate: guest.isTemplate,
        ),
      );
    }

    return OfflineInventorySnapshot(
      fetchedAt: inventory.fetchedAt.toUtc(),
      nodes: List<OfflineInventoryNode>.unmodifiable(nodes),
      guests: List<OfflineInventoryGuest>.unmodifiable(guests),
    );
  }

  Map<String, Object> toJson() => {
    'v': 1,
    'timestampMs': fetchedAt.millisecondsSinceEpoch,
    'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
    'guests': guests.map((guest) => guest.toJson()).toList(growable: false),
  };

  static OfflineInventorySnapshot? fromJson(Object? raw, {DateTime? now}) {
    if (raw is! Map<String, dynamic> || raw.length != 4 || raw['v'] != 1) {
      return null;
    }
    final timestamp = raw['timestampMs'];
    final rawNodes = raw['nodes'];
    final rawGuests = raw['guests'];
    if (timestamp is! int ||
        timestamp < 0 ||
        rawNodes is! List ||
        rawGuests is! List ||
        rawNodes.length > maxOfflineInventoryNodes ||
        rawGuests.length > maxOfflineInventoryGuests) {
      return null;
    }

    late final DateTime fetchedAt;
    try {
      fetchedAt = DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);
    } catch (_) {
      return null;
    }
    final age = (now ?? DateTime.now()).toUtc().difference(fetchedAt);
    if (age.isNegative || age > maxAge) return null;

    final nodes = <OfflineInventoryNode>[];
    final nodeNames = <String>{};
    for (final item in rawNodes) {
      final node = OfflineInventoryNode.fromJson(item);
      if (node == null || !nodeNames.add(node.name)) return null;
      nodes.add(node);
    }

    final guests = <OfflineInventoryGuest>[];
    final vmids = <int>{};
    for (final item in rawGuests) {
      final guest = OfflineInventoryGuest.fromJson(item);
      if (guest == null || !vmids.add(guest.vmid)) return null;
      guests.add(guest);
    }

    return OfflineInventorySnapshot(
      fetchedAt: fetchedAt,
      nodes: List<OfflineInventoryNode>.unmodifiable(nodes),
      guests: List<OfflineInventoryGuest>.unmodifiable(guests),
    );
  }
}
