import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/pve_api.dart';

const _profile = ConnectionProfile(
  id: 'profile-lxc',
  name: 'Lab',
  endpoint: 'https://pve.local:8006',
);
const _credentials = ApiCredentials(
  tokenId: 'operator@pve!virthelm',
  secret: 'secret-value',
);

void main() {
  test('LXC create request enforces bounded unprivileged inputs', () {
    const request = LxcCreateRequest(
      node: 'pve1',
      vmid: 321,
      hostname: 'app-ct',
      cores: 2,
      memoryMiB: 512,
      templateVolid: 'local:vztmpl/debian-13.tar.zst',
      rootfsStorage: 'local-lvm',
    );
    expect(request.validationError, isNull);
    expect(request.templateStorage, 'local');
    expect(
      LxcCreateRequest(
        node: request.node,
        vmid: request.vmid,
        hostname: request.hostname,
        cores: request.cores,
        memoryMiB: request.memoryMiB,
        templateVolid: 'local:iso/not-a-template.iso',
        rootfsStorage: request.rootfsStorage,
      ).validationError,
      contains('template'),
    );
  });

  test('LXC discovery returns active rootdir storage and existing vztmpl', () async {
    final dio = Dio();
    final seen = <String>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          seen.add(options.path);
          dynamic data;
          if (options.path.endsWith('/nodes/pve1/storage')) {
            data = {
              'data': [
                {
                  'storage': 'local',
                  'type': 'dir',
                  'active': 1,
                  'enabled': 1,
                  'content': 'iso,vztmpl,backup',
                },
                {
                  'storage': 'local-lvm',
                  'type': 'lvmthin',
                  'active': 1,
                  'enabled': 1,
                  'content': 'images,rootdir',
                },
                {
                  'storage': 'offline',
                  'type': 'dir',
                  'active': 0,
                  'enabled': 1,
                  'content': 'rootdir,vztmpl',
                },
              ],
            };
          } else if (options.path.endsWith('/nodes/pve1/storage/local/content')) {
            expect(options.queryParameters['content'], 'vztmpl');
            data = {
              'data': [
                {
                  'volid': 'local:vztmpl/debian-13.tar.zst',
                  'format': 'tgz',
                  'size': 1024,
                },
              ],
            };
          } else {
            fail('Unexpected request: ${options.path}');
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: data,
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(_profile, _credentials, http: dio);
    addTearDown(gateway.close);

    final options = await gateway.lxcCreateOptions('pve1');

    expect(options.incomplete, isFalse);
    expect(options.rootfsStorages, ['local-lvm']);
    expect(options.templates, hasLength(1));
    expect(options.templates.single.volid, 'local:vztmpl/debian-13.tar.zst');
    expect(seen, hasLength(2));
  });

  test('LXC create sends only the reviewed fields and validates vzcreate UPID', () async {
    final dio = Dio();
    var posts = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          posts++;
          expect(options.method, 'POST');
          expect(options.path, endsWith('/nodes/pve1/lxc'));
          final data = Map<String, dynamic>.from(options.data as Map);
          expect(
            data,
            {
              'vmid': 321,
              'hostname': 'app-ct',
              'cores': 2,
              'memory': 512,
              'onboot': 0,
              'ostemplate': 'local:vztmpl/debian-13.tar.zst',
              'storage': 'local-lvm',
              'unprivileged': 1,
            },
          );
          expect(data, isNot(contains('password')));
          expect(data, isNot(contains('ssh-public-keys')));
          expect(data, isNot(contains('net0')));
          expect(data, isNot(contains('start')));
          expect(data, isNot(contains('pool')));
          expect(data, isNot(contains('restore')));
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': 'UPID:pve1:00000001:00000002:00000003:vzcreate:321:operator@pve:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(_profile, _credentials, http: dio);
    addTearDown(gateway.close);

    final upid = await gateway.createLxc(
      const LxcCreateRequest(
        node: 'pve1',
        vmid: 321,
        hostname: 'app-ct',
        cores: 2,
        memoryMiB: 512,
        templateVolid: 'local:vztmpl/debian-13.tar.zst',
        rootfsStorage: 'local-lvm',
      ),
    );

    expect(posts, 1);
    expect(upid, contains(':vzcreate:321:'));
  });

  test('LXC create treats a mismatched task as an uncertain mutation', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': 'UPID:pve1:00000001:00000002:00000003:qmcreate:321:operator@pve:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(_profile, _credentials, http: dio);
    addTearDown(gateway.close);

    await expectLater(
      gateway.createLxc(
        const LxcCreateRequest(
          node: 'pve1',
          vmid: 321,
          hostname: 'app-ct',
          cores: 2,
          memoryMiB: 512,
          templateVolid: 'local:vztmpl/debian-13.tar.zst',
          rootfsStorage: 'local-lvm',
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
  });
}
