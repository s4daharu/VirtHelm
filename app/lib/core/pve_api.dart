import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'models.dart';

abstract class PveGateway {
  Future<String> version();
  Future<Inventory> inventory();
  Future<ReadCollection<StoragePool>> storageOverview(List<String> nodes);
  Future<ReadCollection<RecentServerTask>> recentTasks(List<String> nodes);
  Future<String> guestStatus(Guest guest);
  Future<String> submit(Guest guest, GuestAction action);
  Future<ServerTaskStatus> taskStatus(TrackedTask task);
  void close();
}

typedef GatewayFactory =
    PveGateway Function(ConnectionProfile profile, ApiCredentials credentials);

/// A new Dio instance is created for each profile; credentials are origin-scoped.
/// Redirects are rejected so Authorization is never forwarded to another host.
class DioPveGateway implements PveGateway {
  DioPveGateway(
    ConnectionProfile profile,
    ApiCredentials credentials, {
    Dio? http,
  }) : _http = http ?? Dio() {
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

  static String _segment(String value) => Uri.encodeComponent(value);

  Future<dynamic> _request(
    String path, {
    bool mutation = false,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = mutation
          ? await _http.post<dynamic>(path)
          : await _http.get<dynamic>(path, queryParameters: queryParameters);
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
      final message =
          e.type == DioExceptionType.badCertificate ||
              e.error is HandshakeException
          ? 'TLS certificate validation failed. Verify the server hostname, certificate validity, and trusted CA. A trusted certificate is recommended.'
          : switch (code) {
              401 => 'Authentication failed. Check or rotate your API token.',
              403 => 'Permission denied by Proxmox. Check token ACLs.',
              404 => 'Resource not found. It may have moved or been removed.',
              null =>
                unknown
                    ? 'Connection lost. The action may have executed; inspect server tasks before retrying.'
                    : 'Could not reach this Proxmox server. Check network, VPN, and certificate trust.',
              _ =>
                code >= 300 && code < 400
                    ? 'The server tried to redirect the request. Redirects are blocked for security.${unknown ? ' The action outcome is unknown; inspect server tasks before retrying.' : ''}'
                    : unknown
                    ? 'Server error; the action outcome is unknown. Inspect server tasks before retrying.'
                    : 'Proxmox request failed (HTTP $code).',
            };
      throw PveFailure(message, status: code, mayHaveExecuted: unknown);
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
  void close() => _http.close(force: true);
}
