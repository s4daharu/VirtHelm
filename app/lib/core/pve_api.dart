import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'models.dart';

abstract class GuestPermissionGateway {
  Future<GuestPermissionSnapshot> guestPermissions(Guest guest);
}

abstract class GuestCloneGateway {
  Future<int> nextFreeVmid();
  Future<void> assertVmidAvailable(int vmid);
  Future<GuestPermissionSnapshot> permissionsForVmid(int vmid);
  Future<String> cloneTemplate(Guest source, GuestCloneRequest request);
}

abstract class PveGateway {
  Future<String> version();
  Future<Inventory> inventory();
  Future<ReadCollection<StoragePool>> storageOverview(List<String> nodes);
  Future<ReadCollection<RecentServerTask>> recentTasks(List<String> nodes);
  Future<String> guestStatus(Guest guest);
  Future<String> submit(Guest guest, GuestAction action);
  Future<ServerTaskStatus> taskStatus(TrackedTask task);
  Future<TaskLogResult> taskLog(String node, String upid, {int start = 0});
  Future<GuestSnapshotInventory> guestSnapshots(Guest guest);
  Future<GuestConfiguration> guestConfiguration(Guest guest);
  Future<GuestMetricSeries> guestMetrics(
    Guest guest,
    GuestMetricTimeframe timeframe,
  );
  Future<NodeMetricSeries> nodeMetrics(
    String node,
    NodeMetricTimeframe timeframe,
  );
  Future<StorageMetricSeries> storageMetrics(
    StoragePool storage,
    StorageMetricTimeframe timeframe,
  );
  void close();
}

typedef GatewayFactory =
    PveGateway Function(ConnectionProfile profile, ApiCredentials credentials);

/// A new Dio instance is created for each profile; credentials are origin-scoped.
/// Redirects are rejected so Authorization is never forwarded to another host.
class DioPveGateway
    implements PveGateway, GuestPermissionGateway, GuestCloneGateway {
  DioPveGateway(
    ConnectionProfile profile,
    ApiCredentials credentials, {
    Dio? http,
    Future<void> Function(Duration)? retryWait,
    Random? retryRandom,
  }) : _http = http ?? Dio(),
       _retryWait = retryWait ?? _defaultRetryWait,
       _retryRandom = retryRandom ?? Random() {
    if (!credentials.isValid) {
      throw const FormatException('Invalid token identifier or secret.');
    }
    // Revalidate even if a profile came from corrupted preferences.
    if (normalizePveEndpoint(profile.endpoint) != profile.endpoint) {
      throw const FormatException('Invalid stored endpoint.');
    }
    if (profile.allowInvalidCertificates) {
      final origin = Uri.parse(profile.endpoint);
      // Never use HttpOverrides: the exception belongs to this profile's
      // client and exact host/port, not other connections or redirects.
      _http.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (certificate, host, port) =>
              host == origin.host && port == origin.port;
          return client;
        },
      );
    }
    final options = _http.options;
    options.baseUrl = '${profile.endpoint}/api2/json';
    options.connectTimeout = const Duration(seconds: 10);
    options.receiveTimeout = const Duration(seconds: 25);
    options.sendTimeout = const Duration(seconds: 15);
    options.followRedirects = false;
    options.maxRedirects = 0;
    options.headers['Authorization'] = credentials.header;
    options.validateStatus = (status) =>
        status != null && status >= 200 && status < 300;
  }

  final Dio _http;
  final Future<void> Function(Duration) _retryWait;
  final Random _retryRandom;
  bool _closed = false;

  static Future<void> _defaultRetryWait(Duration delay) =>
      Future<void>.delayed(delay);

  // Only retry idempotent reads on transport timeouts or temporary HTTP
  // failures. Never retry certificate, auth, permission or redirect failures.
  static bool _shouldRetryRead(DioException error) {
    if (error.type == DioExceptionType.badCertificate ||
        error.error is TlsException) {
      return false;
    }
    final status = error.response?.statusCode;
    if (status != null) {
      return status == 408 || status == 429 || (status >= 500 && status <= 599);
    }
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }

  // Only identify transport failures from typed Dio/Socket errors. Do not
  // display raw OS error text: it can include the server's hostname or IP.
  // An unreachable route is not proof that the Android device is offline.
  static PveTransportFailure? _transportFailure(DioException error) {
    if (error.response != null ||
        error.type == DioExceptionType.badCertificate ||
        error.error is TlsException) {
      return null;
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return PveTransportFailure.connectTimeout;
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return PveTransportFailure.responseTimeout;
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        final cause = error.error;
        if (cause is SocketException) {
          final code = cause.osError?.errorCode;
          final detail = cause.message.toLowerCase();
          if (code == -2 ||
              code == -3 ||
              detail.contains('failed host lookup')) {
            return PveTransportFailure.dnsFailure;
          }
          if (code == 101 ||
              code == 113 ||
              detail.contains('network is unreachable') ||
              detail.contains('no route to host')) {
            return PveTransportFailure.networkUnreachable;
          }
          return PveTransportFailure.connectionLost;
        }
        if (error.type == DioExceptionType.connectionError) {
          return PveTransportFailure.connectionLost;
        }
        return null;
      default:
        return null;
    }
  }

  Future<Response<dynamic>> _sendRequest(
    String path, {
    required bool mutation,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? mutationData,
  }) async {
    if (_closed) throw const PveFailure('Connection closed.');
    if (mutation) {
      return _http.post<dynamic>(
        path,
        data: mutationData,
        options: mutationData == null
            ? null
            : Options(contentType: Headers.formUrlEncodedContentType),
      );
    }

    // At most three GET attempts, with a bounded exponential backoff + jitter.
    // A closed profile gateway must not issue a delayed follow-up request.
    for (var attempt = 0; ; attempt++) {
      if (_closed) throw const PveFailure('Connection closed.');
      try {
        return await _http.get<dynamic>(path, queryParameters: queryParameters);
      } on DioException catch (error) {
        if (_closed || attempt >= 2 || !_shouldRetryRead(error)) rethrow;
        await _retryWait(
          Duration(
            milliseconds: 200 * (1 << attempt) + _retryRandom.nextInt(100),
          ),
        );
      }
    }
  }

  static String _segment(String value) => Uri.encodeComponent(value);

  Future<dynamic> _request(
    String path, {
    bool mutation = false,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? mutationData,
  }) async {
    try {
      final response = await _sendRequest(
        path,
        mutation: mutation,
        queryParameters: queryParameters,
        mutationData: mutationData,
      );
      final raw = response.data;
      if (raw is! Map || !raw.containsKey('data')) {
        throw PveFailure(
          mutation
              ? 'Unexpected Proxmox API response. The action outcome is unknown; inspect server tasks before retrying.'
              : 'Unexpected Proxmox API response.',
          mayHaveExecuted: mutation,
        );
      }
      return raw['data'];
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final unknown =
          mutation &&
          (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.unknown ||
              e.type == DioExceptionType.cancel ||
              code == 408 ||
              (code != null && (code >= 500 || (code >= 300 && code < 400))));
      final transportFailure = _transportFailure(e);
      final message =
          e.type == DioExceptionType.badCertificate || e.error is TlsException
          ? 'TLS certificate validation failed. Verify the server hostname, certificate validity, and trusted CA. A trusted certificate is recommended.'
          : switch (code) {
              401 => 'Authentication failed. Check or rotate your API token.',
              403 => 'Permission denied by Proxmox. Check token ACLs.',
              404 => 'Resource not found. It may have moved or been removed.',
              null =>
                unknown
                    ? 'Connection lost. The action may have executed; inspect server tasks before retrying.'
                    : switch (transportFailure) {
                        PveTransportFailure.dnsFailure =>
                          'DNS lookup failed. Check the server address and DNS or VPN settings.',
                        PveTransportFailure.networkUnreachable =>
                          'Network unavailable to the server. Check Wi-Fi, mobile data, and VPN.',
                        PveTransportFailure.connectTimeout =>
                          'Connection timed out. Check the server, network, or VPN.',
                        PveTransportFailure.responseTimeout =>
                          'Server response timed out. Check connectivity and refresh.',
                        PveTransportFailure.connectionLost =>
                          'Could not connect to Proxmox. Check the server, network, or VPN.',
                        null =>
                          'Could not reach this Proxmox server. Check network, VPN, and certificate trust.',
                      },
              _ =>
                code >= 300 && code < 400
                    ? 'The server tried to redirect the request. Redirects are blocked for security.${unknown ? ' The action outcome is unknown; inspect server tasks before retrying.' : ''}'
                    : unknown
                    ? 'Server error; the action outcome is unknown. Inspect server tasks before retrying.'
                    : 'Proxmox request failed (HTTP $code).',
            };
      throw PveFailure(
        message,
        status: code,
        mayHaveExecuted: unknown,
        transportFailure: transportFailure,
      );
    }
  }

  @override
  Future<String> version() async {
    final value = await _request('/version');
    if (value is! Map) {
      throw const PveFailure('Unexpected server version response.');
    }
    final version = asText(value['version']);
    if (version == null) {
      throw const PveFailure('Server did not provide a version.');
    }
    try {
      return normalizeServerVersion(version);
    } on FormatException {
      throw const PveFailure('Server returned an invalid version.');
    }
  }

  @override
  Future<Inventory> inventory() async {
    final value = await _request('/cluster/resources');
    if (value is! List) {
      throw const PveFailure('Unexpected cluster resources response.');
    }
    return Inventory.fromResources(value);
  }

  @override
  Future<ReadCollection<StoragePool>> storageOverview(
    List<String> nodes,
  ) async {
    final values = <StoragePool>[];
    var denied = 0;
    var failed = 0;
    var malformed = 0;
    for (final node in nodes) {
      try {
        final raw = await _request('/nodes/${_segment(node)}/storage');
        if (raw is! List) {
          failed++;
          continue;
        }
        for (final entry in raw) {
          if (entry is! Map) {
            malformed++;
            continue;
          }
          try {
            values.add(
              StoragePool.fromApi(Map<String, dynamic>.from(entry), node: node),
            );
          } on FormatException {
            malformed++;
          } on TypeError {
            // A malformed map key must not discard other valid rows.
            malformed++;
          }
        }
      } on PveFailure catch (error) {
        if (error.status == 401) rethrow;
        if (error.status == 403) {
          denied++;
        } else {
          failed++;
        }
      }
    }
    values.sort((a, b) {
      final nodeOrder = a.node.compareTo(b.node);
      return nodeOrder == 0 ? a.id.compareTo(b.id) : nodeOrder;
    });
    return ReadCollection(
      values: values,
      permissionDeniedNodes: denied,
      failedNodes: failed,
      malformedRecords: malformed,
    );
  }

  @override
  Future<ReadCollection<RecentServerTask>> recentTasks(
    List<String> nodes,
  ) async {
    final values = <RecentServerTask>[];
    var denied = 0;
    var failed = 0;
    var malformed = 0;
    for (final node in nodes) {
      try {
        final raw = await _request(
          '/nodes/${_segment(node)}/tasks',
          queryParameters: const {'limit': 20, 'source': 'all'},
        );
        if (raw is! List) {
          failed++;
          continue;
        }
        for (final entry in raw) {
          if (entry is! Map) {
            malformed++;
            continue;
          }
          try {
            values.add(
              RecentServerTask.fromApi(
                Map<String, dynamic>.from(entry),
                node: node,
              ),
            );
          } on FormatException {
            malformed++;
          } on TypeError {
            // A malformed map key must not discard other valid rows.
            malformed++;
          }
        }
      } on PveFailure catch (error) {
        if (error.status == 401) rethrow;
        if (error.status == 403) {
          denied++;
        } else {
          failed++;
        }
      }
    }
    values.sort((a, b) {
      final left = a.startedAt?.millisecondsSinceEpoch ?? 0;
      final right = b.startedAt?.millisecondsSinceEpoch ?? 0;
      return right.compareTo(left);
    });
    return ReadCollection(
      values: values.take(60).toList(growable: false),
      permissionDeniedNodes: denied,
      failedNodes: failed,
      malformedRecords: malformed,
    );
  }

  String _guestPath(Guest guest) {
    if (guest.kind != 'qemu' && guest.kind != 'lxc') {
      throw const FormatException('Unsupported guest kind.');
    }
    if (guest.vmid < 1 || guest.node.isEmpty) {
      throw const FormatException('Invalid guest identity.');
    }
    return '/nodes/${_segment(guest.node)}/${guest.kind}/${guest.vmid}';
  }

  @override
  Future<String> guestStatus(Guest guest) async {
    final value = await _request('${_guestPath(guest)}/status/current');
    if (value is! Map) {
      throw const PveFailure('Unexpected guest status response.');
    }
    return asText(value['status']) ?? 'unknown';
  }

  @override
  Future<String> submit(Guest guest, GuestAction action) async {
    final value = await _request(
      '${_guestPath(guest)}/status/${action.apiAction}',
      mutation: true,
    );
    if (value is! String || !value.startsWith('UPID:')) {
      throw const PveFailure(
        'Server returned an unexpected task identifier. Check task history.',
        mayHaveExecuted: true,
      );
    }
    return value;
  }

  @override
  Future<ServerTaskStatus> taskStatus(TrackedTask task) async {
    final value = await _request(
      '/nodes/${_segment(task.node)}/tasks/${_segment(task.upid)}/status',
    );
    if (value is! Map) {
      throw const PveFailure('Unexpected task status response.');
    }
    return ServerTaskStatus(
      status: asText(value['status']) ?? 'unknown',
      exitStatus: asText(value['exitstatus']),
    );
  }

  @override
  Future<TaskLogResult> taskLog(
    String node,
    String upid, {
    int start = 0,
  }) async {
    if (start < 0 || start > 400 || start % 100 != 0) {
      throw const FormatException('Invalid task log page.');
    }
    if (node.isEmpty || !upid.startsWith('UPID:')) {
      throw const FormatException('Invalid task identity.');
    }
    final raw = await _request(
      '/nodes/${_segment(node)}/tasks/${_segment(upid)}/log',
      queryParameters: {'start': start, 'limit': 100},
    );
    if (raw is! List) {
      throw const PveFailure('Unexpected task log response.');
    }
    final entries = <TaskLogEntry>[];
    var malformed = 0;
    for (final row in raw.take(100)) {
      if (row is! Map) {
        malformed++;
        continue;
      }
      try {
        entries.add(TaskLogEntry.fromApi(Map<String, dynamic>.from(row)));
      } on FormatException {
        malformed++;
      } on TypeError {
        malformed++;
      }
    }
    entries.sort((a, b) => a.number.compareTo(b.number));
    return TaskLogResult(
      entries: List<TaskLogEntry>.unmodifiable(entries),
      malformedRecords: malformed,
    );
  }

  @override
  Future<GuestSnapshotInventory> guestSnapshots(Guest guest) async {
    final raw = await _request('${_guestPath(guest)}/snapshot');
    if (raw is! List) {
      throw const PveFailure('Unexpected guest snapshot response.');
    }

    const snapshotLimit = 500;
    final snapshots = <GuestSnapshot>[];
    var malformed = 0;
    for (final row in raw.take(snapshotLimit)) {
      if (row is! Map) {
        malformed++;
        continue;
      }
      try {
        snapshots.add(GuestSnapshot.fromApi(Map<String, dynamic>.from(row)));
      } on FormatException {
        malformed++;
      } on TypeError {
        malformed++;
      }
    }
    snapshots.sort((a, b) {
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      final aTime = a.createdAt;
      final bTime = b.createdAt;
      if (aTime != null && bTime != null) return bTime.compareTo(aTime);
      if (aTime != null) return -1;
      if (bTime != null) return 1;
      return a.name.compareTo(b.name);
    });
    return GuestSnapshotInventory(
      snapshots: List<GuestSnapshot>.unmodifiable(snapshots),
      malformedRecords: malformed,
      truncated: raw.length > snapshotLimit,
    );
  }

  @override
  Future<GuestConfiguration> guestConfiguration(Guest guest) async {
    final raw = await _request('${_guestPath(guest)}/config');
    if (raw is! Map) {
      throw const PveFailure('Unexpected guest configuration response.');
    }
    try {
      return GuestConfiguration.fromApi(
        Map<String, dynamic>.from(raw),
        kind: guest.kind,
      );
    } on FormatException {
      throw const PveFailure('Unexpected guest configuration response.');
    } on TypeError {
      throw const PveFailure('Unexpected guest configuration response.');
    }
  }

  @override
  Future<GuestPermissionSnapshot> guestPermissions(Guest guest) =>
      permissionsForVmid(guest.vmid);

  @override
  Future<GuestPermissionSnapshot> permissionsForVmid(int vmid) async {
    if (vmid < 1 || vmid > 999999999) {
      throw const FormatException('Invalid VMID.');
    }
    final raw = await _request(
      '/access/permissions',
      queryParameters: {'path': '/vms/$vmid'},
    );
    if (raw is! Map) {
      throw const PveFailure('Unexpected guest permission response.');
    }
    try {
      return GuestPermissionSnapshot.fromApi(
        Map<String, dynamic>.from(raw),
        vmid: vmid,
      );
    } on FormatException {
      throw const PveFailure('Unexpected guest permission response.');
    } on TypeError {
      throw const PveFailure('Unexpected guest permission response.');
    }
  }

  @override
  Future<int> nextFreeVmid() async {
    final raw = await _request('/cluster/nextid');
    final value = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (value == null || value < 100 || value > 999999999) {
      throw const PveFailure('Unexpected next-VMID response.');
    }
    return value;
  }

  @override
  Future<void> assertVmidAvailable(int vmid) async {
    if (vmid < 100 || vmid > 999999999) {
      throw const FormatException('Invalid destination VMID.');
    }
    final raw = await _request(
      '/cluster/nextid',
      queryParameters: {'vmid': vmid},
    );
    final value = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (value != vmid) {
      throw const PveFailure(
        'Destination VMID could not be confirmed as available.',
      );
    }
  }

  @override
  Future<String> cloneTemplate(Guest source, GuestCloneRequest request) async {
    if (!source.isTemplate) {
      throw const FormatException('Clone source must be a template.');
    }
    final normalized = request.normalized();
    final validationError = normalized.validationError;
    if (validationError != null) {
      throw FormatException(validationError);
    }
    final nameField = source.kind == 'lxc' ? 'hostname' : 'name';
    final value = await _request(
      '${_guestPath(source)}/clone',
      mutation: true,
      mutationData: {
        'newid': normalized.newVmid,
        'full': 1,
        nameField: normalized.name,
      },
    );
    if (value is! String || !value.startsWith('UPID:')) {
      throw const PveFailure(
        'Server returned an unexpected clone task identifier. Check task history.',
        mayHaveExecuted: true,
      );
    }
    return value;
  }

  @override
  Future<GuestMetricSeries> guestMetrics(
    Guest guest,
    GuestMetricTimeframe timeframe,
  ) async {
    final raw = await _request(
      '${_guestPath(guest)}/rrddata',
      queryParameters: {'timeframe': timeframe.apiValue, 'cf': 'AVERAGE'},
    );
    if (raw is! List) {
      throw const PveFailure('Unexpected guest performance response.');
    }

    const pointLimit = 1500;
    final points = <GuestMetricPoint>[];
    var malformed = 0;
    for (final row in raw.take(pointLimit)) {
      if (row is! Map) {
        malformed++;
        continue;
      }
      try {
        points.add(GuestMetricPoint.fromApi(Map<String, dynamic>.from(row)));
      } on FormatException {
        malformed++;
      } on TypeError {
        malformed++;
      }
    }
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return GuestMetricSeries(
      points: List<GuestMetricPoint>.unmodifiable(points),
      malformedRecords: malformed,
      truncated: raw.length > pointLimit,
    );
  }

  @override
  Future<NodeMetricSeries> nodeMetrics(
    String node,
    NodeMetricTimeframe timeframe,
  ) async {
    final normalizedNode = node.trim();
    if (normalizedNode.isEmpty || normalizedNode.length > 200) {
      throw const FormatException('Invalid node identity.');
    }
    final raw = await _request(
      '/nodes/${_segment(normalizedNode)}/rrddata',
      queryParameters: {'timeframe': timeframe.apiValue, 'cf': 'AVERAGE'},
    );
    if (raw is! List) {
      throw const PveFailure('Unexpected node performance response.');
    }

    const pointLimit = 1500;
    final points = <NodeMetricPoint>[];
    var malformed = 0;
    for (final row in raw.take(pointLimit)) {
      if (row is! Map) {
        malformed++;
        continue;
      }
      try {
        points.add(NodeMetricPoint.fromApi(Map<String, dynamic>.from(row)));
      } on FormatException {
        malformed++;
      } on TypeError {
        malformed++;
      }
    }
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return NodeMetricSeries(
      points: List<NodeMetricPoint>.unmodifiable(points),
      malformedRecords: malformed,
      truncated: raw.length > pointLimit,
    );
  }

  @override
  Future<StorageMetricSeries> storageMetrics(
    StoragePool storage,
    StorageMetricTimeframe timeframe,
  ) async {
    final normalizedNode = storage.node.trim();
    final normalizedStorage = storage.id.trim();
    if (normalizedNode.isEmpty ||
        normalizedNode.length > 200 ||
        normalizedStorage.isEmpty ||
        normalizedStorage.length > 200) {
      throw const FormatException('Invalid storage identity.');
    }
    final raw = await _request(
      '/nodes/${_segment(normalizedNode)}/storage/'
      '${_segment(normalizedStorage)}/rrddata',
      queryParameters: {'timeframe': timeframe.apiValue, 'cf': 'AVERAGE'},
    );
    if (raw is! List) {
      throw const PveFailure('Unexpected storage performance response.');
    }

    const pointLimit = 1500;
    final points = <StorageMetricPoint>[];
    var malformed = 0;
    for (final row in raw.take(pointLimit)) {
      if (row is! Map) {
        malformed++;
        continue;
      }
      try {
        points.add(StorageMetricPoint.fromApi(Map<String, dynamic>.from(row)));
      } on FormatException {
        malformed++;
      } on TypeError {
        malformed++;
      }
    }
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return StorageMetricSeries(
      points: List<StorageMetricPoint>.unmodifiable(points),
      malformedRecords: malformed,
      truncated: raw.length > pointLimit,
    );
  }

  @override
  void close() {
    _closed = true;
    _http.close(force: true);
  }
}
