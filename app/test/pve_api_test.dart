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
}
