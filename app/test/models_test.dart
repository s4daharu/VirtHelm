import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';

void main() {
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
    });
    test('rejects unsafe and ambiguous URLs', () {
      for (final url in [
        'http://pve.local:8006',
        'https://alice:password@pve.local:8006',
        'https://pve.local:8006/prefix',
        'https://pve.local:8006?token=secret',
        'https://pve.local:8006/#fragment',
        'https://',
      ]) {
        expect(
          () => normalizePveEndpoint(url),
          throwsFormatException,
          reason: url,
        );
      }
    });
  });

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
