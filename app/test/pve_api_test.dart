import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/pve_api.dart';

const profile = ConnectionProfile(
  id: 'profile-1',
  name: 'Lab',
  endpoint: 'https://pve.local:8006',
);
const credentials = ApiCredentials(
  tokenId: 'operator@pve!virthelm',
  secret: 'secret-value',
);

void main() {
  const guest = Guest(
    node: 'pve1',
    vmid: 101,
    kind: 'qemu',
    name: 'Web',
    status: 'running',
  );

  test(
    'malformed successful POST responses preserve unknown-outcome lockout',
    () async {
      for (final body in [
        null,
        'not JSON',
        <String, dynamic>{},
        {'data': null},
      ]) {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: body,
                ),
              );
            },
          ),
        );
        final gateway = DioPveGateway(profile, credentials, http: dio);
        addTearDown(gateway.close);
        await expectLater(
          gateway.submit(guest, GuestAction.shutdown),
          throwsA(
            isA<PveFailure>().having(
              (failure) => failure.mayHaveExecuted,
              'mayHaveExecuted',
              isTrue,
            ),
          ),
        );
      }
    },
  );

  test(
    'ambiguous Dio failures and redirects are unsafe to retry after POST',
    () async {
      for (final spec in [
        (DioExceptionType.unknown, null),
        (DioExceptionType.unknown, 200),
        (DioExceptionType.cancel, null),
        (DioExceptionType.badResponse, 408),
        (DioExceptionType.badResponse, 302),
        (DioExceptionType.badResponse, 503),
      ]) {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: spec.$1,
                  response: spec.$2 == null
                      ? null
                      : Response<dynamic>(
                          requestOptions: options,
                          statusCode: spec.$2,
                        ),
                ),
              );
            },
          ),
        );
        final gateway = DioPveGateway(profile, credentials, http: dio);
        addTearDown(gateway.close);
        await expectLater(
          gateway.submit(guest, GuestAction.shutdown),
          throwsA(
            isA<PveFailure>().having(
              (failure) => failure.mayHaveExecuted,
              'mayHaveExecuted',
              isTrue,
            ),
          ),
        );
      }
    },
  );

  test(
    'explicit auth rejection is not reported as an executed mutation',
    () async {
      for (final status in [401, 403]) {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: status,
                  ),
                ),
              );
            },
          ),
        );
        final gateway = DioPveGateway(profile, credentials, http: dio);
        addTearDown(gateway.close);
        await expectLater(
          gateway.submit(guest, GuestAction.shutdown),
          throwsA(
            isA<PveFailure>().having(
              (failure) => failure.mayHaveExecuted,
              'mayHaveExecuted',
              isFalse,
            ),
          ),
        );
      }
    },
  );

  test(
    'invalid supplemental records are reported rather than silently dropped',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': [null, 'invalid', <String, dynamic>{}],
                },
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);
      expect((await gateway.storageOverview(['pve1'])).malformedRecords, 3);
      expect((await gateway.recentTasks(['pve1'])).malformedRecords, 3);
    },
  );

  test(
    'gateway applies origin, authorization and redirect security to injected Dio',
    () async {
      final dio = Dio();
      late RequestOptions request;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': {'version': '9.2.21'},
                },
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);

      expect(await gateway.version(), '9.2.21');
      expect(
        request.uri.toString(),
        'https://pve.local:8006/api2/json/version',
      );
      expect(
        request.headers['Authorization'],
        'PVEAPIToken=operator@pve!virthelm=secret-value',
      );
      expect(dio.options.followRedirects, isFalse);
      expect(dio.options.maxRedirects, 0);
      expect(dio.options.validateStatus(200), isTrue);
      expect(dio.options.validateStatus(302), isFalse);
    },
  );

  test('version endpoint rejects missing or blank versions', () async {
    for (final value in [null, '', '   ']) {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': {'version': value},
                },
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);
      await expectLater(
        gateway.version(),
        throwsA(
          isA<PveFailure>().having(
            (failure) => failure.message,
            'message',
            contains('version'),
          ),
        ),
      );
    }
  });

  test('guest RRD history uses bounded GET parameters and parsing', () async {
    final dio = Dio();
    late RequestOptions request;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': [
                  {'time': 1700000060, 'cpu': 0.3, 'mem': 768, 'maxmem': 1024},
                  'bad',
                  {'time': 1700000000, 'cpu': 0.1, 'mem': 512, 'maxmem': 1024},
                  {'time': -1, 'cpu': 0.4},
                ],
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final series = await gateway.guestMetrics(guest, GuestMetricTimeframe.week);
    expect(request.method, 'GET');
    expect(request.path, '/nodes/pve1/qemu/101/rrddata');
    expect(request.queryParameters['timeframe'], 'week');
    expect(request.queryParameters['cf'], 'AVERAGE');
    expect(series.points.length, 2);
    expect(series.points.first.cpuFraction, 0.1);
    expect(series.points.last.memoryFraction, 0.75);
    expect(series.malformedRecords, 2);
    expect(series.truncated, isFalse);
  });

  test('guest snapshot inventory uses bounded read-only parsing', () async {
    final dio = Dio();
    late RequestOptions request;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': [
                  {'name': 'current', 'description': 'Current config'},
                  {
                    'name': 'before-upgrade',
                    'snaptime': 1700000060,
                    'parent': 'baseline',
                    'description': 'Before package update',
                    'vmstate': 1,
                  },
                  'bad',
                  {'name': '', 'snaptime': 1700000000},
                ],
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final result = await gateway.guestSnapshots(guest);
    expect(request.method, 'GET');
    expect(request.path, '/nodes/pve1/qemu/101/snapshot');
    expect(result.snapshots.length, 2);
    expect(result.snapshots.first.isCurrent, isTrue);
    expect(result.snapshots.last.name, 'before-upgrade');
    expect(result.snapshots.last.parent, 'baseline');
    expect(result.snapshots.last.includesMemory, isTrue);
    expect(result.malformedRecords, 2);
    expect(result.truncated, isFalse);
  });

  test('guest configuration GET returns only allowlisted fields', () async {
    final dio = Dio();
    late RequestOptions request;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'cores': 4,
                  'memory': 4096,
                  'scsi0': 'local-lvm:vm-101-disk-0,size=64G',
                  'net0': 'virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0',
                  'cipassword': 'server-secret',
                  'args': '-fw_cfg password=server-secret',
                },
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final result = await gateway.guestConfiguration(guest);
    expect(request.method, 'GET');
    expect(request.path, '/nodes/pve1/qemu/101/config');
    expect(result.visibleFieldCount, 4);
    expect(result.withheldFields, 2);
    final visible = [
      ...result.compute,
      ...result.platform,
      ...result.storage,
      ...result.network,
    ].map((field) => field.value).join(' ');
    expect(visible, isNot(contains('server-secret')));
  });

  test('guest permission hints use exact self-permission GET path', () async {
    final dio = Dio();
    late RequestOptions request;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  '/vms/101': {
                    'VM.Audit': 1,
                    'VM.PowerMgmt': 0,
                    'VM.Snapshot': 1,
                  },
                },
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final result = await gateway.guestPermissions(guest);
    expect(request.method, 'GET');
    expect(request.path, '/access/permissions');
    expect(request.queryParameters['path'], '/vms/101');
    expect(result.has('VM.Audit'), isTrue);
    expect(result.has('VM.PowerMgmt'), isTrue);
    expect(result.has('VM.Snapshot'), isTrue);
  });

  test('node RRD history uses bounded GET parameters and parsing', () async {
    final dio = Dio();
    late RequestOptions request;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': [
                  {'time': 1700000060, 'cpu': 0.4, 'mem': 1536, 'maxmem': 2048},
                  'bad',
                  {'time': 1700000000, 'cpu': 0.2, 'mem': 1024, 'maxmem': 2048},
                  {'time': 1700000120, 'cpu': 2.0, 'mem': -1, 'maxmem': 2048},
                ],
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final series = await gateway.nodeMetrics('pve1', NodeMetricTimeframe.week);
    expect(request.method, 'GET');
    expect(request.path, '/nodes/pve1/rrddata');
    expect(request.queryParameters['timeframe'], 'week');
    expect(request.queryParameters['cf'], 'AVERAGE');
    expect(series.points.length, 2);
    expect(series.points.first.cpuFraction, 0.2);
    expect(series.points.last.memoryFraction, 0.75);
    expect(series.malformedRecords, 2);
    expect(series.truncated, isFalse);
  });

  test('storage RRD history uses bounded GET parameters and parsing', () async {
    final dio = Dio();
    late RequestOptions request;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': [
                  {'time': 1700000060, 'used': 768.4, 'total': 1024.0},
                  'bad',
                  {'time': 1700000000, 'used': 512, 'total': 1024},
                  {'time': -1, 'used': 256, 'total': 1024},
                ],
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final series = await gateway.storageMetrics(
      const StoragePool(node: 'pve1', id: 'local', type: 'dir'),
      StorageMetricTimeframe.day,
    );
    expect(request.method, 'GET');
    expect(request.path, '/nodes/pve1/storage/local/rrddata');
    expect(request.queryParameters['timeframe'], 'day');
    expect(request.queryParameters['cf'], 'AVERAGE');
    expect(series.points.length, 2);
    expect(series.points.first.usageFraction, 0.5);
    expect(series.points.last.usedBytes, 768);
    expect(series.malformedRecords, 2);
    expect(series.truncated, isFalse);
  });

  test(
    'task log uses bounded read-only URL and tolerates malformed rows',
    () async {
      final dio = Dio();
      late RequestOptions request;
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            request = options;
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': [
                    {'n': 2, 't': 'second'},
                    'bad',
                    {'n': -1, 't': 'invalid'},
                    {'n': 1, 't': 'first'},
                  ],
                },
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);
      const upid = 'UPID:pve1:1:2:3:qmstart:101:user@pve:';
      final log = await gateway.taskLog('pve1', upid);
      expect(calls, 1);
      expect(request.method, 'GET');
      expect(request.path, contains(Uri.encodeComponent(upid)));
      expect(request.queryParameters['start'], 0);
      expect(request.queryParameters['limit'], 100);
      expect(log.entries.map((line) => line.text), ['first', 'second']);
      expect(log.malformedRecords, 2);
    },
  );

  test('task log paging rejects invalid offsets before network I/O', () async {
    final dio = Dio();
    var requests = 0;
    late RequestOptions pageRequest;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          pageRequest = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': [
                  {'n': 101, 't': 'later line'},
                ],
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);
    const upid = 'UPID:pve1:1:2:3:qmstart:101:user@pve:';
    final page = await gateway.taskLog('pve1', upid, start: 100);
    expect(page.entries.single.text, 'later line');
    expect(pageRequest.method, 'GET');
    expect(pageRequest.queryParameters['start'], 100);
    expect(pageRequest.queryParameters['limit'], 100);
    for (final invalid in [-1, 1, 99, 401, 500]) {
      await expectLater(
        gateway.taskLog('pve1', upid, start: invalid),
        throwsFormatException,
      );
    }
    expect(requests, 1);
  });

  test('task log forbidden response never triggers retries', () async {
    final dio = Dio();
    var calls = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 403,
              ),
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);
    await expectLater(
      gateway.taskLog('pve1', 'UPID:pve1:1:2:3:qmstart:101:user@pve:'),
      throwsA(isA<PveFailure>().having((e) => e.status, 'status', 403)),
    );
    expect(calls, 1);
  });

  test(
    'node task history asks for active plus archived tasks and normalizes status',
    () async {
      final dio = Dio();
      late RequestOptions request;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': [
                    {
                      'upid': 'UPID:pve1:1:2:3:qmstart:101:user@pve:',
                      'node': 'pve1',
                      'type': 'qmstart',
                      'id': '101',
                      'status': 'RUNNING',
                      'starttime': 1700000010,
                    },
                    {
                      'upid': 'UPID:pve1:1:2:3:qmshutdown:102:user@pve:',
                      'node': 'pve1',
                      'type': 'qmshutdown',
                      'id': '102',
                      'status': 'OK',
                      'starttime': 1700000000,
                      'endtime': 1700000005,
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);

      final result = await gateway.recentTasks(['pve1']);
      expect(request.queryParameters['limit'], 20);
      expect(request.queryParameters['source'], 'all');
      expect(result.values.first.stateLabel, 'running');
      expect(result.values.last.stateLabel, 'succeeded');
      expect(result.values.last.exitStatus, 'OK');
    },
  );

  test(
    'storage overview keeps successful nodes when another node is forbidden',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('/pve2/storage')) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 403,
                  ),
                ),
              );
              return;
            }
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': [
                    {
                      'storage': 'local',
                      'type': 'dir',
                      'active': 1,
                      'enabled': 1,
                      'used': 512,
                      'total': 1024,
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);

      final result = await gateway.storageOverview(['pve1', 'pve2']);
      expect(result.values.single.node, 'pve1');
      expect(result.permissionDeniedNodes, 1);
      expect(result.complete, isFalse);
    },
  );

  test('certificate failures produce explicit fail-closed guidance', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badCertificate,
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    await expectLater(
      gateway.version(),
      throwsA(
        isA<PveFailure>().having(
          (failure) => failure.message,
          'message',
          contains('TLS certificate validation failed'),
        ),
      ),
    );
  });

  test('guest lifecycle submission uses one encoded POST path', () async {
    final dio = Dio();
    var posts = 0;
    late RequestOptions request;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          if (options.method == 'POST') posts++;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {'data': 'UPID:pve1:1:2:3:qmshutdown:101:user@pve:'},
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);
    const guest = Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'qemu',
      name: 'Web',
      status: 'running',
    );

    final upid = await gateway.submit(guest, GuestAction.shutdown);
    expect(upid, startsWith('UPID:'));
    expect(posts, 1);
    expect(request.uri.path, '/api2/json/nodes/pve1/qemu/101/status/shutdown');
  });

  test('invalid map keys do not discard valid supplemental rows', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final storage = options.path.endsWith('/storage');
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': [
                  <Object, Object>{1: 'malformed-key'},
                  if (storage)
                    {'storage': 'local', 'type': 'dir'}
                  else
                    {
                      'upid': 'UPID:pve1:1:2:3:qmstart:101:user@pve:',
                      'status': 'RUNNING',
                    },
                ],
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final storage = await gateway.storageOverview(['pve1']);
    expect(storage.values.single.id, 'local');
    expect(storage.malformedRecords, 1);
    expect(storage.failedNodes, 0);
    final tasks = await gateway.recentTasks(['pve1']);
    expect(tasks.values.single.stateLabel, 'running');
    expect(tasks.malformedRecords, 1);
    expect(tasks.failedNodes, 0);
  });

  test(
    'transient GET failures retry at most twice with bounded jitter',
    () async {
      final dio = Dio();
      var requests = 0;
      final delays = <Duration>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            if (requests == 1) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 503,
                  ),
                ),
              );
            } else if (requests == 2) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
            } else {
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {'version': '9.2.21'},
                  },
                ),
              );
            }
          },
        ),
      );
      final gateway = DioPveGateway(
        profile,
        credentials,
        http: dio,
        retryWait: (delay) async {
          delays.add(delay);
        },
      );
      addTearDown(gateway.close);

      expect(await gateway.version(), '9.2.21');
      expect(requests, 3);
      expect(delays, hasLength(2));
      expect(delays[0].inMilliseconds, inInclusiveRange(200, 299));
      expect(delays[1].inMilliseconds, inInclusiveRange(400, 499));
    },
  );

  test('repeated transient GET failures stop after three attempts', () async {
    final dio = Dio();
    var requests = 0;
    var waits = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout,
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(
      profile,
      credentials,
      http: dio,
      retryWait: (_) async {
        waits++;
      },
    );
    addTearDown(gateway.close);

    await expectLater(gateway.version(), throwsA(isA<PveFailure>()));
    expect(requests, 3);
    expect(waits, 2);
  });

  test(
    'auth, permission, missing resource and redirect GETs do not retry',
    () async {
      for (final status in [301, 401, 403, 404]) {
        final dio = Dio();
        var requests = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: status,
                  ),
                ),
              );
            },
          ),
        );
        final gateway = DioPveGateway(
          profile,
          credentials,
          http: dio,
          retryWait: (_) async {
            fail('Permanent GET failure should not be retried.');
          },
        );
        addTearDown(gateway.close);

        await expectLater(gateway.version(), throwsA(isA<PveFailure>()));
        expect(requests, 1);
      }
    },
  );

  test(
    'TLS and malformed successful GET responses are never retried',
    () async {
      for (final certificateFailure in [true, false]) {
        final dio = Dio();
        var requests = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              if (certificateFailure) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badCertificate,
                  ),
                );
              } else {
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'unexpected': 'envelope'},
                  ),
                );
              }
            },
          ),
        );
        final gateway = DioPveGateway(
          profile,
          credentials,
          http: dio,
          retryWait: (_) async {
            fail('TLS and malformed payloads must not be retried.');
          },
        );
        addTearDown(gateway.close);

        await expectLater(gateway.version(), throwsA(isA<PveFailure>()));
        expect(requests, 1);
      }
    },
  );

  test('transient POST failure is never automatically retried', () async {
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 503,
              ),
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(
      profile,
      credentials,
      http: dio,
      retryWait: (_) async {
        fail('Guest mutation must not be retried.');
      },
    );
    addTearDown(gateway.close);

    await expectLater(
      gateway.submit(guest, GuestAction.shutdown),
      throwsA(
        isA<PveFailure>().having(
          (failure) => failure.mayHaveExecuted,
          'mayHaveExecuted',
          isTrue,
        ),
      ),
    );
    expect(requests, 1);
  });

  test('closing the gateway during backoff prevents another GET', () async {
    final dio = Dio();
    var requests = 0;
    final waiting = Completer<void>();
    final resume = Completer<void>();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(
      profile,
      credentials,
      http: dio,
      retryWait: (_) {
        waiting.complete();
        return resume.future;
      },
    );

    final pending = gateway.version();
    await waiting.future;
    gateway.close();
    resume.complete();

    await expectLater(
      pending,
      throwsA(
        isA<PveFailure>().having(
          (failure) => failure.message,
          'message',
          'Connection closed.',
        ),
      ),
    );
    expect(requests, 1);
  });

  test(
    'TLS handshake errors wrapped as connection errors never retry',
    () async {
      final dio = Dio();
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: TlsException('untrusted certificate'),
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(
        profile,
        credentials,
        http: dio,
        retryWait: (_) async {
          fail('TLS transport failure must not be retried.');
        },
      );
      addTearDown(gateway.close);

      await expectLater(
        gateway.version(),
        throwsA(
          isA<PveFailure>().having(
            (failure) => failure.message,
            'message',
            contains('TLS certificate validation failed'),
          ),
        ),
      );
      expect(requests, 1);
    },
  );

  test('GET transport diagnoses show safe, distinct guidance', () async {
    Future<void> verify(
      DioExceptionType type,
      Object? cause,
      PveTransportFailure expected,
      String guidance,
    ) async {
      final dio = Dio();
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(
              DioException(requestOptions: options, type: type, error: cause),
            );
          },
        ),
      );
      final gateway = DioPveGateway(
        profile,
        credentials,
        http: dio,
        retryWait: (_) async {},
      );
      addTearDown(gateway.close);

      await expectLater(
        gateway.version(),
        throwsA(
          isA<PveFailure>()
              .having(
                (failure) => failure.transportFailure,
                'transportFailure',
                expected,
              )
              .having(
                (failure) => failure.message,
                'message',
                contains(guidance),
              ),
        ),
      );
      expect(requests, type == DioExceptionType.unknown ? 1 : 3);
    }

    await verify(
      DioExceptionType.connectionError,
      const SocketException('Failed host lookup: internal.example'),
      PveTransportFailure.dnsFailure,
      'DNS lookup failed',
    );
    await verify(
      DioExceptionType.connectionError,
      const SocketException('Network is unreachable'),
      PveTransportFailure.networkUnreachable,
      'Network unavailable',
    );
    await verify(
      DioExceptionType.connectionError,
      const SocketException('Connection refused'),
      PveTransportFailure.connectionLost,
      'Could not connect',
    );
    await verify(
      DioExceptionType.connectionTimeout,
      null,
      PveTransportFailure.connectTimeout,
      'Connection timed out',
    );
    await verify(
      DioExceptionType.sendTimeout,
      null,
      PveTransportFailure.responseTimeout,
      'Server response timed out',
    );
    await verify(
      DioExceptionType.receiveTimeout,
      null,
      PveTransportFailure.responseTimeout,
      'Server response timed out',
    );
    await verify(
      DioExceptionType.unknown,
      const SocketException('Failed host lookup: internal.example'),
      PveTransportFailure.dnsFailure,
      'DNS lookup failed',
    );
  });

  test('transport diagnosis never exposes the raw socket error', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.unknown,
              error: const SocketException(
                'Failed host lookup: secret.internal.example',
              ),
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    try {
      await gateway.version();
      fail('Expected a DNS failure.');
    } on PveFailure catch (error) {
      expect(error.transportFailure, PveTransportFailure.dnsFailure);
      expect(error.message, isNot(contains('secret.internal.example')));
      expect(error.status, isNull);
      expect(error.mayHaveExecuted, isFalse);
    }
  });

  test(
    'classified POST transport loss stays uncertain and single-shot',
    () async {
      final dio = Dio();
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: const SocketException('Network is unreachable'),
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(
        profile,
        credentials,
        http: dio,
        retryWait: (_) async {
          fail('No retries are allowed for POST.');
        },
      );
      addTearDown(gateway.close);

      await expectLater(
        gateway.submit(guest, GuestAction.shutdown),
        throwsA(
          isA<PveFailure>()
              .having(
                (failure) => failure.transportFailure,
                'transportFailure',
                PveTransportFailure.networkUnreachable,
              )
              .having(
                (failure) => failure.mayHaveExecuted,
                'mayHaveExecuted',
                isTrue,
              ),
        ),
      );
      expect(requests, 1);
    },
  );

  test(
    'template clone API uses nextid, exact ACL paths, and one full QEMU POST',
    () async {
      final dio = Dio();
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            dynamic data;
            if (options.path.endsWith('/cluster/nextid')) {
              data = options.queryParameters.containsKey('vmid') ? 901 : '901';
            } else if (options.path.endsWith('/access/permissions')) {
              final path = options.queryParameters['path'];
              data = {
                path: {
                  if (path == '/vms/900') 'VM.Clone': 1,
                  if (path == '/vms/901') 'VM.Allocate': 1,
                },
              };
            } else if (options.path.endsWith('/clone')) {
              data = 'UPID:pve1:1:2:3:qmclone:900:user@pve:';
            } else {
              fail('Unexpected request: ${options.path}');
            }
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {'data': data},
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);
      const source = Guest(
        node: 'pve1',
        vmid: 900,
        kind: 'qemu',
        name: 'ubuntu-template',
        status: 'stopped',
        isTemplate: true,
      );

      expect(await gateway.nextFreeVmid(), 901);
      expect((await gateway.permissionsForVmid(900)).has('VM.Clone'), isTrue);
      expect(
        (await gateway.permissionsForVmid(901)).has('VM.Allocate'),
        isTrue,
      );
      await gateway.assertVmidAvailable(901);
      final upid = await gateway.cloneTemplate(
        source,
        const GuestCloneRequest(newVmid: 901, name: 'ubuntu-copy'),
      );

      expect(upid, startsWith('UPID:'));
      final posts = requests
          .where((request) => request.method == 'POST')
          .toList();
      expect(posts, hasLength(1));
      final post = posts.single;
      expect(post.uri.path, '/api2/json/nodes/pve1/qemu/900/clone');
      expect(post.data, isA<Map<String, dynamic>>());
      final body = Map<String, dynamic>.from(post.data as Map);
      expect(body['newid'], 901);
      expect(body['full'], 1);
      expect(body['name'], 'ubuntu-copy');
      expect(body.containsKey('hostname'), isFalse);
      expect(
        requests.where(
          (request) =>
              request.path.endsWith('/cluster/nextid') &&
              request.queryParameters['vmid'] == 901,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'LXC template clone sends hostname and never retries an ambiguous POST',
    () async {
      final dio = Dio();
      var posts = 0;
      late RequestOptions request;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            posts++;
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 503,
                ),
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(
        profile,
        credentials,
        http: dio,
        retryWait: (_) async => fail('Clone POST must not be retried.'),
      );
      addTearDown(gateway.close);
      const source = Guest(
        node: 'pve1',
        vmid: 900,
        kind: 'lxc',
        name: 'debian-template',
        status: 'stopped',
        isTemplate: true,
      );

      await expectLater(
        gateway.cloneTemplate(
          source,
          const GuestCloneRequest(newVmid: 902, name: 'debian-copy'),
        ),
        throwsA(
          isA<PveFailure>().having(
            (failure) => failure.mayHaveExecuted,
            'mayHaveExecuted',
            isTrue,
          ),
        ),
      );
      expect(posts, 1);
      expect(request.uri.path, '/api2/json/nodes/pve1/lxc/900/clone');
      final body = Map<String, dynamic>.from(request.data as Map);
      expect(body['hostname'], 'debian-copy');
      expect(body.containsKey('name'), isFalse);
      expect(body['full'], 1);
    },
  );

  test('QEMU create API sends only the reviewed shell fields', () async {
    final dio = Dio();
    late RequestOptions request;
    var posts = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          posts++;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {'data': 'UPID:pve1:1:2:3:qmcreate:901:user@pve:'},
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final upid = await gateway.createQemu(
      const QemuCreateRequest(
        node: 'pve1',
        vmid: 901,
        name: 'app-vm',
        cores: 4,
        memoryMiB: 4096,
        onBoot: true,
      ),
    );

    expect(upid, startsWith('UPID:'));
    expect(posts, 1);
    expect(request.method, 'POST');
    expect(request.uri.path, '/api2/json/nodes/pve1/qemu');
    final body = Map<String, dynamic>.from(request.data as Map);
    expect(body, {
      'vmid': 901,
      'name': 'app-vm',
      'cores': 4,
      'memory': 4096,
      'onboot': 1,
    });
    for (final forbidden in [
      'storage',
      'scsi0',
      'ide2',
      'net0',
      'start',
      'pool',
      'ha-managed',
      'archive',
    ]) {
      expect(body.containsKey(forbidden), isFalse, reason: forbidden);
    }
  });

  test(
    'QEMU create POST is never retried after an ambiguous server failure',
    () async {
      final dio = Dio();
      var posts = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            posts++;
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 503,
                ),
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(
        profile,
        credentials,
        http: dio,
        retryWait: (_) async => fail('QEMU create POST must not be retried.'),
      );
      addTearDown(gateway.close);

      await expectLater(
        gateway.createQemu(
          const QemuCreateRequest(
            node: 'pve1',
            vmid: 901,
            name: 'app-vm',
            cores: 2,
            memoryMiB: 2048,
          ),
        ),
        throwsA(
          isA<PveFailure>().having(
            (failure) => failure.mayHaveExecuted,
            'mayHaveExecuted',
            isTrue,
          ),
        ),
      );
      expect(posts, 1);
    },
  );

  test(
    'QEMU create normalizes fields and rejects invalid inputs before I/O',
    () async {
      final dio = Dio();
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {'data': 'UPID:pve1:1:2:3:qmcreate:901:user@pve:'},
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);
      await gateway.createQemu(
        const QemuCreateRequest(
          node: ' pve1 ',
          vmid: 901,
          name: ' trimmed ',
          cores: 2,
          memoryMiB: 2048,
        ),
      );
      expect(requests.single.uri.path, '/api2/json/nodes/pve1/qemu');
      expect((requests.single.data as Map)['name'], 'trimmed');
      expect((requests.single.data as Map)['onboot'], 0);
      expect(requests.single.contentType, Headers.formUrlEncodedContentType);
      for (final node in ['../pve1', '', 'pve1/qemu']) {
        await expectLater(
          gateway.createQemu(
            QemuCreateRequest(
              node: node,
              vmid: 901,
              name: 'valid',
              cores: 2,
              memoryMiB: 2048,
            ),
          ),
          throwsFormatException,
        );
      }
      expect(requests, hasLength(1));
    },
  );

  test('QEMU create malformed or mismatched UPIDs remain ambiguous', () async {
    for (final body in [
      null,
      'not JSON',
      <String, dynamic>{},
      {'data': null},
      {'data': 'UPID:'},
      {'data': 'UPID:pve2:1:2:3:qmcreate:901:user@pve:'},
      {'data': 'UPID:pve1:1:2:3:qmcreate:902:user@pve:'},
      {'data': 'UPID:pve1:1:2:3:qmstart:901:user@pve:'},
    ]) {
      final dio = Dio();
      var posts = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            posts++;
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: body,
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);
      await expectLater(
        gateway.createQemu(
          const QemuCreateRequest(
            node: 'pve1',
            vmid: 901,
            name: 'valid',
            cores: 2,
            memoryMiB: 2048,
          ),
        ),
        throwsA(
          isA<PveFailure>().having(
            (e) => e.mayHaveExecuted,
            'ambiguous',
            isTrue,
          ),
        ),
      );
      expect(posts, 1);
    }
  });

  test(
    'QEMU create never retries auth denials redirects or timeouts',
    () async {
      for (final code in [401, 403, 302, 408, null]) {
        final dio = Dio();
        var posts = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              posts++;
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: code == null
                      ? DioExceptionType.receiveTimeout
                      : DioExceptionType.badResponse,
                  response: code == null
                      ? null
                      : Response<dynamic>(
                          requestOptions: options,
                          statusCode: code,
                        ),
                ),
              );
            },
          ),
        );
        final gateway = DioPveGateway(
          profile,
          credentials,
          http: dio,
          retryWait: (_) async => fail('Create POST must never retry'),
        );
        addTearDown(gateway.close);
        await expectLater(
          gateway.createQemu(
            const QemuCreateRequest(
              node: 'pve1',
              vmid: 901,
              name: 'valid',
              cores: 2,
              memoryMiB: 2048,
            ),
          ),
          throwsA(
            isA<PveFailure>().having(
              (e) => e.mayHaveExecuted,
              'ambiguous',
              code == 401 || code == 403 ? isFalse : isTrue,
            ),
          ),
        );
        expect(posts, 1);
      }
    },
  );
}
