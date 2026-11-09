import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/pve_api.dart';

const profile = ConnectionProfile(
  id: 'profile-1',
  name: 'Lab',
  endpoint: 'https://pve.invalid:8006',
);
const credentials = ApiCredentials(
  tokenId: 'test@pve!test',
  secret: 'x',
);

void main() {
  test('QEMU migration preflight parses allowed nodes and local blockers', () {
    final result = GuestMigrationPreflight.fromApi({
      'running': 1,
      'allowed_nodes': ['pve3', 'pve2'],
      'local_disks': [
        {'volid': 'local-lvm:vm-101-disk-0', 'size': 1024},
      ],
      'local_resources': ['hostpci0'],
    }, kind: 'qemu');

    expect(result.running, isTrue);
    expect(result.allowedNodes, ['pve2', 'pve3']);
    expect(result.localDiskCount, 1);
    expect(result.localResources, ['hostpci0']);
    expect(result.incomplete, isFalse);
    expect(result.allowsTarget('pve2'), isTrue);
  });

  test('LXC migration preflight uses the hyphenated allowed-node contract', () {
    final result = GuestMigrationPreflight.fromApi({
      'running': 0,
      'allowed-nodes': ['pve2'],
    }, kind: 'lxc');

    expect(result.running, isFalse);
    expect(result.allowedNodes, ['pve2']);
    expect(result.localDiskCount, 0);
    expect(result.localResources, isEmpty);
    expect(result.incomplete, isFalse);
  });

  test('QEMU migration uses GET preflight then one bounded live POST', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'qemu',
      name: 'Web',
      status: 'running',
    );
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.method == 'GET') {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': {
                    'running': 1,
                    'allowed_nodes': ['pve2'],
                    'local_disks': <dynamic>[],
                    'local_resources': <dynamic>[],
                  },
                },
              ),
            );
          } else {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data':
                      'UPID:pve1:00000001:00000002:00000003:qmigrate:101:test-user:',
                },
              ),
            );
          }
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final preflight = await gateway.migrationPreflight(guest, 'pve2');
    expect(preflight.allowsTarget('pve2'), isTrue);
    final upid = await gateway.migrateGuest(
      guest,
      const GuestMigrationRequest(targetNode: 'pve2'),
    );

    expect(upid, contains(':qmigrate:101:'));
    expect(requests, hasLength(2));
    expect(requests[0].method, 'GET');
    expect(requests[0].path, '/nodes/pve1/qemu/101/migrate');
    expect(requests[0].queryParameters, {'target': 'pve2'});
    expect(requests[1].method, 'POST');
    expect(requests[1].data, {'target': 'pve2', 'online': 1});
    expect((requests[1].data as Map).containsKey('force'), isFalse);
    expect((requests[1].data as Map).containsKey('targetstorage'), isFalse);
    expect((requests[1].data as Map).containsKey('migration_type'), isFalse);
  });

  test('running LXC migration uses restart rather than live migration', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 202,
      kind: 'lxc',
      name: 'API',
      status: 'running',
    );
    late RequestOptions posted;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          posted = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data':
                    'UPID:pve1:00000001:00000002:00000003:vzmigrate:202:test-user:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    await gateway.migrateGuest(
      guest,
      const GuestMigrationRequest(targetNode: 'pve2'),
    );

    expect(posted.method, 'POST');
    expect(posted.path, '/nodes/pve1/lxc/202/migrate');
    expect(posted.data, {'target': 'pve2', 'restart': 1});
    expect((posted.data as Map).containsKey('online'), isFalse);
    expect((posted.data as Map).containsKey('target-storage'), isFalse);
    expect((posted.data as Map).containsKey('force'), isFalse);
  });

  test('mismatched migration UPID is treated as an uncertain outcome', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 202,
      kind: 'lxc',
      name: 'API',
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
                    'UPID:pve1:00000001:00000002:00000003:qmigrate:202:test-user:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    await expectLater(
      gateway.migrateGuest(
        guest,
        const GuestMigrationRequest(targetNode: 'pve2'),
      ),
      throwsA(
        isA<PveFailure>()
            .having((error) => error.mayHaveExecuted, 'unknown outcome', isTrue)
            .having((error) => error.message, 'message', contains('mismatched')),
      ),
    );
  });
}
