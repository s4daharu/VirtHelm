import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/pve_api.dart';

const profile = ConnectionProfile(
  id: 'profile-1',
  name: 'Lab',
  endpoint: 'https://pve.invalid:8006',
);
const credentials = ApiCredentials(tokenId: 'test@pve!test', secret: 'x');

void main() {
  test('QEMU snapshot deletion uses one DELETE and qmdelsnapshot UPID', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'qemu',
      name: 'Web',
      status: 'running',
    );
    const snapshot = GuestSnapshot(name: 'before-upgrade');
    late RequestOptions request;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data':
                    'UPID:pve1:00000001:00000002:00000003:qmdelsnapshot:101:test-user:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final upid = await gateway.deleteGuestSnapshot(guest, snapshot);

    expect(upid, contains(':qmdelsnapshot:101:'));
    expect(request.method, 'DELETE');
    expect(request.path, '/nodes/pve1/qemu/101/snapshot/before-upgrade');
    expect(request.data, isNull);
    expect(request.queryParameters, isEmpty);
  });

  test('LXC snapshot rollback posts no start or force fields', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 202,
      kind: 'lxc',
      name: 'API',
      status: 'stopped',
    );
    const snapshot = GuestSnapshot(name: 'safe_point');
    late RequestOptions request;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data':
                    'UPID:pve1:00000001:00000002:00000003:vzrollback:202:test-user:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final upid = await gateway.rollbackGuestSnapshot(guest, snapshot);

    expect(upid, contains(':vzrollback:202:'));
    expect(request.method, 'POST');
    expect(request.path, '/nodes/pve1/lxc/202/snapshot/safe_point/rollback');
    expect(request.data, isNull);
    expect(request.queryParameters, isEmpty);
  });

  test('rollback refuses a running guest and a RAM-state snapshot', () async {
    const running = Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'qemu',
      name: 'Web',
      status: 'running',
    );
    const stopped = Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'qemu',
      name: 'Web',
      status: 'stopped',
    );
    var requests = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {'data': 'unused'},
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    await expectLater(
      gateway.rollbackGuestSnapshot(
        running,
        const GuestSnapshot(name: 'before-upgrade'),
      ),
      throwsFormatException,
    );
    await expectLater(
      gateway.rollbackGuestSnapshot(
        stopped,
        const GuestSnapshot(name: 'before-upgrade', includesMemory: true),
      ),
      throwsFormatException,
    );
    expect(requests, 0);
  });

  test('snapshot mutation rejects reserved and unsafe target names', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'qemu',
      name: 'Web',
      status: 'stopped',
    );
    var requests = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {'data': 'unused'},
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    for (final name in [
      'current',
      'bad name',
      '../escape',
      '1starts-with-digit',
    ]) {
      final snapshot = GuestSnapshot(name: name);
      await expectLater(
        gateway.rollbackGuestSnapshot(guest, snapshot),
        throwsFormatException,
        reason: name,
      );
      await expectLater(
        gateway.deleteGuestSnapshot(guest, snapshot),
        throwsFormatException,
        reason: name,
      );
    }
    expect(requests, 0);
  });

  test('mismatched snapshot delete worker is uncertain', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'qemu',
      name: 'Web',
      status: 'running',
    );
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data':
                    'UPID:pve1:00000001:00000002:00000003:qmsnapshot:101:test-user:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    await expectLater(
      gateway.deleteGuestSnapshot(
        guest,
        const GuestSnapshot(name: 'before-upgrade'),
      ),
      throwsA(
        isA<PveFailure>()
            .having((error) => error.mayHaveExecuted, 'mayHaveExecuted', isTrue)
            .having(
              (error) => error.message,
              'message',
              contains('mismatched snapshot delete'),
            ),
      ),
    );
  });
}
