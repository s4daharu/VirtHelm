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
}
