import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';

void main() {
  test(
    'certificate bypass defaults off and round-trips only explicit opt-in',
    () {
      final profile = ConnectionProfile.create(
        name: 'Lab',
        address: 'https://pve.example',
      );
      expect(profile.allowInvalidCertificates, isFalse);
      for (final value in [null, false, 'true', 1]) {
        final json = profile.toJson()..remove('allowInvalidCertificates');
        if (value != null) json['allowInvalidCertificates'] = value;
        expect(
          ConnectionProfile.fromJson(json).allowInvalidCertificates,
          isFalse,
        );
      }
      final insecure = ConnectionProfile.create(
        name: 'Lab',
        address: 'https://pve.example',
        allowInvalidCertificates: true,
      );
      expect(
        ConnectionProfile.fromJson(insecure.toJson()).allowInvalidCertificates,
        isTrue,
      );
      expect(
        () => ConnectionProfile.create(
          name: 'Lab',
          address: 'http://pve.example',
          allowInvalidCertificates: true,
        ),
        throwsFormatException,
      );
    },
  );

  test('server version metadata round-trips and rejects invalid values', () {
    final profile = ConnectionProfile.create(
      name: 'Lab',
      address: 'https://pve.example',
    ).withServerVersion(' 9.2.4 ');

    expect(profile.lastServerVersion, '9.2.4');
    expect(
      ConnectionProfile.fromJson(profile.toJson()).lastServerVersion,
      '9.2.4',
    );

    for (final value in [42, '', List.filled(81, 'x').join()]) {
      final json = profile.toJson();
      json['lastServerVersion'] = value;
      expect(ConnectionProfile.fromJson(json).lastServerVersion, isNull);
    }
    expect(() => normalizeServerVersion('   '), throwsFormatException);
  });

  group('Proxmox URL safety', () {
    test('canonicalizes direct HTTPS endpoint', () {
      expect(
        normalizePveEndpoint('https://pve.local'),
        'https://pve.local:8006',
      );
      expect(
        normalizePveEndpoint('https://pve.local:8443/api2/json'),
        'https://pve.local:8443',
      );
      for (final url in [
        'https://pve.example:443',
        'https://[::1]:443',
        'https://[::1]:8006',
      ]) {
        expect(normalizePveEndpoint(url), url);
        expect(normalizePveEndpoint(normalizePveEndpoint(url)), url);
      }
      expect(normalizePveEndpoint('https://[::1]'), 'https://[::1]:8006');
    });
    test('rejects unsafe and ambiguous URLs', () {
      for (final url in [
        'http://pve.local:8006',
        'https://alice:password@pve.local:8006',
        'https://pve.local:8006/prefix',
        'https://pve.local:8006?token=secret',
        'https://pve.local:8006/#fragment',
        'https://',
        'https://pve.local:',
        'https://pve.local:0',
        'https://pve.local:65536',
      ]) {
        expect(
          () => normalizePveEndpoint(url),
          throwsFormatException,
          reason: url,
        );
      }
    });
  });

  test(
    'malformed identities and non-finite numbers never become valid guests',
    () {
      for (final vmid in [0, -1, 101.5, double.nan, double.infinity, '101']) {
        final inventory = Inventory.fromResources([
          {'type': 'qemu', 'node': 'pve1', 'vmid': vmid},
        ]);
        expect(inventory.guests, isEmpty);
        expect(inventory.malformedGuestRecords, 1);
      }
      expect(
        Inventory.fromResources([null, 'broken']).malformedGuestRecords,
        2,
      );
      expect(asInteger(101.0), 101);
      expect(asDouble(double.infinity), isNull);
      expect(asFlag(double.nan), isNull);
      expect(asUnixSeconds(8640000000001), isNull);
      expect(asUnixSeconds(-1), isNull);
    },
  );

  test('parses sparse mixed node and guest inventory', () {
    final inv = Inventory.fromResources([
      {
        'type': 'node',
        'node': 'pve1',
        'status': 'online',
        'cpu': 0.5,
        'uptime': 90061,
      },
      {
        'type': 'qemu',
        'node': 'pve1',
        'vmid': 101,
        'name': 'Web',
        'status': 'running',
        'cpu': 0.25,
        'mem': 1073741824,
        'maxmem': 2147483648,
        'uptime': 3661,
      },
      {'type': 'lxc', 'node': 'pve1', 'vmid': 102, 'status': 'stopped'},
      {'type': 'storage', 'storage': 'local'},
      {'type': 'qemu', 'name': 'bad record'},
    ]);
    expect(inv.nodes.length, 1);
    expect(inv.guests.length, 2);
    expect(inv.malformedGuestRecords, 1);
    expect(inv.guests.first.name, 'Web');
    expect(inv.guests.last.name, 'lxc 102');
    expect(formatPercent(inv.guests.first.cpu), '25.0%');
    expect(formatPercent(2), '100.0%');
    expect(formatPercent(-0.1), '—');
    expect(formatBytes(inv.guests.first.mem), '1.0 GiB');
    expect(formatBytes(null), '—');
    expect(formatUptime(inv.nodes.single.uptime), '1d 1h');
    expect(formatUptime(inv.guests.first.uptime), '1h 1m');
  });

  test('task success requires stopped state with OK exit code', () {
    expect(const ServerTaskStatus(status: 'running').succeeded, isFalse);
    expect(const ServerTaskStatus(status: 'stopped').succeeded, isFalse);
    expect(
      const ServerTaskStatus(status: 'stopped', exitStatus: 'OK').succeeded,
      isTrue,
    );
    expect(
      const ServerTaskStatus(status: 'stopped', exitStatus: 'ERROR').succeeded,
      isFalse,
    );
  });

  test(
    'parses storage flags, content and capacity without guessing missing data',
    () {
      final pool = StoragePool.fromApi({
        'storage': 'local-lvm',
        'type': 'lvmthin',
        'enabled': 1,
        'active': 1,
        'shared': 0,
        'content': 'images,rootdir',
        'used': 536870912,
        'total': 1073741824,
        'avail': 536870912,
      }, node: 'pve1');
      expect(pool.id, 'local-lvm');
      expect(pool.stateLabel, 'active');
      expect(pool.contentTypes, ['images', 'rootdir']);
      expect(pool.usageFraction, 0.5);
      expect(pool.shared, isFalse);
    },
  );

  test('parses archived and active node task-list semantics', () {
    final done = RecentServerTask.fromApi({
      'upid': 'UPID:pve1:0001:0002:0003:qmstart:101:user@pve:',
      'node': 'pve1',
      'type': 'qmstart',
      'id': 101,
      'status': 'OK',
      'starttime': 1700000000,
      'endtime': 1700000003,
    }, node: 'fallback');
    expect(done.operationLabel, 'Start VM');
    expect(done.resourceId, '101');
    expect(done.status, 'stopped');
    expect(done.exitStatus, 'OK');
    expect(done.stateLabel, 'succeeded');
    expect(
      done.startedAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
    );

    final running = RecentServerTask.fromApi({
      'upid': 'UPID:pve1:0001:0002:0003:qmstart:101:user@pve:',
      'type': 'qmstart',
      'status': 'RUNNING',
      'starttime': 1700000000,
    }, node: 'pve1');
    expect(running.status, 'running');
    expect(running.exitStatus, isNull);
    expect(running.stateLabel, 'running');
  });

  test('task history respects separate exit status and unknown results', () {
    const upid = 'UPID:pve1:0001:0002:0003:qmstart:101:user@pve:';
    RecentServerTask from(Map<String, Object?> data) =>
        RecentServerTask.fromApi({
          'upid': upid,
          ...data,
        }, node: 'pve1');

    final successful = from({'status': 'stopped', 'exitstatus': 'OK'});
    expect(successful.isDone, isTrue);
    expect(successful.exitStatus, 'OK');
    expect(successful.stateLabel, 'succeeded');

    final failed = from({'status': 'stopped', 'exitstatus': 'Error'});
    expect(failed.stateLabel, 'failed');
    expect(failed.exitStatus, 'Error');

    final uncertain = from({'status': 'stopped'});
    expect(uncertain.isDone, isTrue);
    expect(uncertain.exitStatus, isNull);
    expect(uncertain.stateLabel, 'unknown');

    final active = from({'status': 'RUNNING', 'exitstatus': 'OK'});
    expect(active.stateLabel, 'running');
    expect(active.exitStatus, isNull);

    final missing = from({});
    expect(missing.stateLabel, 'unknown');
    expect(missing.isDone, isFalse);

    final explicitlyUnknown = from({'status': 'unknown'});
    expect(explicitlyUnknown.stateLabel, 'unknown');
    expect(explicitlyUnknown.isDone, isFalse);
  });

  test('token is properly formatted and can be encoded locally', () {
    const creds = ApiCredentials(tokenId: 'operator@pve!mobile', secret: 'xyz');
    expect(creds.isValid, isTrue);
    expect(
      ApiCredentials.decode(creds.encode()).header,
      'PVEAPIToken=operator@pve!mobile=xyz',
    );
    expect(const ApiCredentials(tokenId: 'root', secret: 'x').isValid, isFalse);
    expect(
      const ApiCredentials(
        tokenId: 'operator@pve!mobile',
        secret: ' secret ',
      ).isValid,
      isFalse,
    );
  });

  test('action policy prevents start on running and stop on stopped', () {
    const guest = Guest(
      node: 'pve1',
      vmid: 100,
      kind: 'qemu',
      name: 'a',
      status: 'running',
    );
    expect(GuestAction.start.allowedFor(guest), isFalse);
    expect(GuestAction.shutdown.allowedFor(guest), isTrue);
  });
}
