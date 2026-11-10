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
  test('QEMU deletion uses one DELETE and validates qmdestroy UPID', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'qemu',
      name: 'Web',
      status: 'stopped',
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
                    'UPID:pve1:00000001:00000002:00000003:qmdestroy:101:test-user:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final upid = await gateway.deleteGuest(guest);

    expect(upid, contains(':qmdestroy:101:'));
    expect(request.method, 'DELETE');
    expect(request.path, '/nodes/pve1/qemu/101');
    expect(request.queryParameters, isEmpty);
    expect(request.data, isNull);
  });

  test(
    'LXC deletion requires stopped state and accepts vzdestroy UPID',
    () async {
      const running = Guest(
        node: 'pve1',
        vmid: 202,
        kind: 'lxc',
        name: 'API',
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
                data: {
                  'data':
                      'UPID:pve1:00000001:00000002:00000003:vzdestroy:202:test-user:',
                },
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);

      await expectLater(
        gateway.deleteGuest(running),
        throwsA(isA<FormatException>()),
      );
      expect(requests, 0);

      final upid = await gateway.deleteGuest(
        const Guest(
          node: 'pve1',
          vmid: 202,
          kind: 'lxc',
          name: 'API',
          status: 'stopped',
        ),
      );
      expect(upid, contains(':vzdestroy:202:'));
      expect(requests, 1);
    },
  );

  test('mismatched deletion worker is treated as an uncertain outcome', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'qemu',
      name: 'Web',
      status: 'stopped',
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
                    'UPID:pve1:00000001:00000002:00000003:vzdestroy:101:test-user:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    await expectLater(
      gateway.deleteGuest(guest),
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
