import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';

void main() {
  group('Proxmox URL safety', () {
    test('canonicalizes direct HTTPS endpoint', () {
      expect(normalizePveEndpoint('https://pve.local'), 'https://pve.local:8006');
      expect(normalizePveEndpoint('https://pve.local:8443/api2/json'),
          'https://pve.local:8443');
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
        expect(() => normalizePveEndpoint(url), throwsFormatException,
            reason: url);
      }
    });
  });

  test('parses sparse mixed node and guest inventory', () {
    final inv = Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'online', 'cpu': 0.5},
      {'type': 'qemu', 'node': 'pve1', 'vmid': 101, 'name': 'Web',
       'status': 'running', 'cpu': 0.25, 'mem': 1073741824,
       'maxmem': 2147483648},
      {'type': 'lxc', 'node': 'pve1', 'vmid': 102, 'status': 'stopped'},
      {'type': 'storage', 'storage': 'local'},
      {'type': 'qemu', 'name': 'bad record'},
    ]);
    expect(inv.nodes.length, 1);
    expect(inv.guests.length, 2);
    expect(inv.guests.first.name, 'Web');
    expect(inv.guests.last.name, 'lxc 102');
    expect(formatPercent(inv.guests.first.cpu), '25.0%');
    expect(formatBytes(inv.guests.first.mem), '1.0 GiB');
    expect(formatBytes(null), '—');
  });

  test('task success requires stopped state with OK exit code', () {
    expect(const ServerTaskStatus(status: 'running').succeeded, isFalse);
    expect(const ServerTaskStatus(status: 'stopped').succeeded, isFalse);
    expect(const ServerTaskStatus(status: 'stopped', exitStatus: 'OK').succeeded,
        isTrue);
    expect(const ServerTaskStatus(status: 'stopped', exitStatus: 'ERROR').succeeded,
        isFalse);
  });

  test('token is properly formatted and can be encoded locally', () {
    const creds = ApiCredentials(tokenId: 'operator@pve!mobile', secret: 'xyz');
    expect(creds.isValid, isTrue);
    expect(ApiCredentials.decode(creds.encode()).header,
        'PVEAPIToken=operator@pve!mobile=xyz');
    expect(const ApiCredentials(tokenId: 'root', secret: 'x').isValid, isFalse);
  });

  test('action policy prevents start on running and stop on stopped', () {
    const guest = Guest(node: 'pve1', vmid: 100, kind: 'qemu',
        name: 'a', status: 'running');
    expect(GuestAction.start.allowedFor(guest), isFalse);
    expect(GuestAction.shutdown.allowedFor(guest), isTrue);
  });
}
