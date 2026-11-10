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
    'backup storage discovery keeps only active backup-capable storage',
    () async {
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
                  'data': [
                    {
                      'storage': 'backup-a',
                      'type': 'pbs',
                      'enabled': 1,
                      'active': 1,
                      'content': 'backup',
                    },
                    {
                      'storage': 'local',
                      'type': 'dir',
                      'enabled': 1,
                      'active': 1,
                      'content': 'iso,vztmpl,rootdir,images',
                    },
                    {
                      'storage': 'disabled-backup',
                      'type': 'dir',
                      'enabled': 0,
                      'active': 1,
                      'content': 'backup',
                    },
                    'malformed',
                  ],
                },
              ),
            );
          },
        ),
      );
      final gateway = DioPveGateway(profile, credentials, http: dio);
      addTearDown(gateway.close);

      final result = await gateway.backupStorages('pve1');

      expect(request.method, 'GET');
      expect(request.path, '/nodes/pve1/storage');
      expect(result, ['backup-a']);
    },
  );

  test('backup archive listing is exact-guest scoped and newest first', () async {
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
                'data': [
                  {
                    'content': 'backup',
                    'volid':
                        'backup-a:backup/vzdump-qemu-101-2026_11_10-10_00_00.vma.zst',
                    'vmid': 101,
                    'size': 1024,
                    'ctime': 1700000000,
                    'format': 'vma.zst',
                    'protected': 1,
                  },
                  {
                    'content': 'backup',
                    'volid': 'backup-a:backup/vm/101/2026-11-11T10:00:00Z',
                    'vmid': '101',
                    'size': 2048,
                    'ctime': 1800000000,
                  },
                  {
                    'content': 'backup',
                    'volid':
                        'backup-a:backup/vzdump-lxc-101-2026_11_10-10_00_00.tar.zst',
                    'vmid': 101,
                  },
                  {
                    'content': 'backup',
                    'volid':
                        'backup-a:backup/vzdump-qemu-202-2026_11_10-10_00_00.vma.zst',
                    'vmid': 202,
                  },
                  'malformed',
                ],
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final result = await gateway.guestBackupArchives(guest, 'backup-a');

    expect(request.method, 'GET');
    expect(request.path, '/nodes/pve1/storage/backup-a/content');
    expect(request.queryParameters, {'content': 'backup', 'vmid': 101});
    expect(result.storage, 'backup-a');
    expect(result.archives, hasLength(2));
    expect(result.ignoredRecords, 3);
    expect(result.truncated, isFalse);
    expect(result.latest?.volid, contains('backup/vm/101/'));
    expect(result.archives.last.format, 'vma.zst');
    expect(result.archives.last.protected, isTrue);
  });

  test('LXC PBS-style backup archive identity is accepted', () async {
    const guest = Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'lxc',
      name: 'CT',
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
                'data': [
                  {
                    'content': 'backup',
                    'volid': 'pbs:backup/ct/101/2026-11-11T10:00:00Z',
                    'vmid': 101,
                    'size': 4096,
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

    final result = await gateway.guestBackupArchives(guest, 'pbs');

    expect(result.archives, hasLength(1));
    expect(result.archives.single.kind, 'lxc');
    expect(result.archives.single.vmid, 101);
    expect(result.archives.single.sizeBytes, 4096);
  });

  test('invalid backup archive storage is rejected before I/O', () async {
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
              data: {'data': <dynamic>[]},
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    await expectLater(
      gateway.guestBackupArchives(guest, 'bad/storage'),
      throwsA(isA<FormatException>()),
    );
    expect(requests, 0);
  });

  test('QEMU backup posts only vmid storage and snapshot mode', () async {
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
                    'UPID:pve1:00000001:00000002:00000003:vzdump:101:test-user:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    final upid = await gateway.startGuestBackup(
      guest,
      const GuestBackupRequest(storage: 'backup-a'),
    );

    expect(upid, contains(':vzdump:101:'));
    expect(request.method, 'POST');
    expect(request.path, '/nodes/pve1/vzdump');
    expect(request.queryParameters, isEmpty);
    expect(request.data, {
      'vmid': 101,
      'storage': 'backup-a',
      'mode': 'snapshot',
    });
    expect((request.data as Map).containsKey('prune-backups'), isFalse);
    expect((request.data as Map).containsKey('script'), isFalse);
    expect((request.data as Map).containsKey('fleecing'), isFalse);
    expect((request.data as Map).containsKey('bwlimit'), isFalse);
    expect((request.data as Map).containsKey('performance'), isFalse);
    expect((request.data as Map).containsKey('ionice'), isFalse);
  });

  test('invalid backup storage is rejected before I/O', () async {
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
      gateway.startGuestBackup(
        guest,
        const GuestBackupRequest(storage: 'bad/storage'),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(requests, 0);
  });

  test('mismatched backup UPID is treated as an uncertain outcome', () async {
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
                    'UPID:pve2:00000001:00000002:00000003:vzdump:101:test-user:',
              },
            ),
          );
        },
      ),
    );
    final gateway = DioPveGateway(profile, credentials, http: dio);
    addTearDown(gateway.close);

    await expectLater(
      gateway.startGuestBackup(
        guest,
        const GuestBackupRequest(storage: 'backup-a'),
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
