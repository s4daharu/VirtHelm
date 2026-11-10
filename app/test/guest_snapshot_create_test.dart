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
  test(
    'QEMU snapshot creation posts only snapname and validates qmsnapshot UPID',
    () async {
      const guest = Guest(
        node: 'pve1',
        vmid: 101,
        kind: 'qemu',
        name: 'Web',
        status: 'running',
      );
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
                      'UPID:pve1:00000001:00000002:00000003:qmsnapshot:101:test-user:',
                },
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);

      final upid = await gateway.createGuestSnapshot(
        guest,
        const GuestSnapshotCreateRequest(name: 'before-upgrade'),
      );

      expect(upid, contains(':qmsnapshot:101:'));
      expect(request.method, 'POST');
      expect(request.path, '/nodes/pve1/qemu/101/snapshot');
      expect(request.queryParameters, isEmpty);
      expect(request.data, {'snapname': 'before-upgrade'});
      expect((request.data as Map).containsKey('vmstate'), isFalse);
      expect((request.data as Map).containsKey('description'), isFalse);
    },
  );

  test('LXC snapshot creation accepts vzsnapshot UPID', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 202,
      kind: 'lxc',
      name: 'API',
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
              data: {
                'data':
                    'UPID:pve1:00000001:00000002:00000003:vzsnapshot:202:test-user:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final upid = await gateway.createGuestSnapshot(
      guest,
      const GuestSnapshotCreateRequest(name: 'safe_point'),
    );

    expect(upid, contains(':vzsnapshot:202:'));
    expect(requests, 1);
  });

  test('invalid snapshot name is rejected before I/O', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'qemu',
      name: 'Web',
      status: 'running',
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
      gateway.createGuestSnapshot(
        guest,
        const GuestSnapshotCreateRequest(name: 'bad name'),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(requests, 0);
  });

  test('mismatched snapshot worker is treated as an uncertain outcome', () async {
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
                    'UPID:pve1:00000001:00000002:00000003:vzsnapshot:101:test-user:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    await expectLater(
      gateway.createGuestSnapshot(
        guest,
        const GuestSnapshotCreateRequest(name: 'before-upgrade'),
      ),
      throwsA(
        isA<PveFailure>()
            .having((error) => error.mayHaveExecuted, 'unknown outcome', isTrue)
            .having(
              (error) => error.message,
              'message',
              contains('mismatched'),
            ),
      ),
    );
  });
}
