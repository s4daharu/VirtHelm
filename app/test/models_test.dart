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
        'netin': 1048576,
        'netout': 2048,
        'diskread': 1073741824,
        'diskwrite': 0,
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
    expect(formatBytes(inv.guests.first.netIn), '1.0 MiB');
    expect(formatBytes(inv.guests.first.netOut), '2.0 KiB');
    expect(formatBytes(inv.guests.first.diskRead), '1.0 GiB');
    expect(formatBytes(inv.guests.first.diskWrite), '0 B');
    expect(inv.guests.last.netIn, isNull);
    expect(inv.guests.last.diskRead, isNull);
  });

  test(
    'guest tag and pool metadata is bounded without invalidating inventory',
    () {
      final inventory = Inventory.fromResources([
        {
          'type': 'qemu',
          'node': 'pve1',
          'vmid': 101,
          'name': 'Web',
          'status': 'running',
          'tags': ' production ; web ;production;;CaseSensitive ',
          'pool': ' Team A ',
        },
        {
          'type': 'lxc',
          'node': 'pve1',
          'vmid': 102,
          'tags': 42,
          'pool': 'bad\u0000pool',
        },
      ]);

      expect(inventory.malformedGuestRecords, 0);
      expect(inventory.guests.first.tags, [
        'production',
        'web',
        'CaseSensitive',
      ]);
      expect(inventory.guests.first.pool, 'Team A');
      expect(inventory.guests.last.tags, isEmpty);
      expect(inventory.guests.last.pool, isNull);
    },
  );

  test('guest configuration exposes only reviewed bounded fields', () {
    final qemu = GuestConfiguration.fromApi({
      'cores': 4,
      'memory': 4096,
      'cpu': 'x86-64-v2-AES',
      'scsi0': 'local-lvm:vm-101-disk-0,size=64G',
      'net0': 'virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0',
      'ipconfig0': 'ip=10.0.0.10/24,gw=10.0.0.1',
      'cipassword': 'super-secret',
      'sshkeys': 'ssh-ed25519 AAAA-private-context',
      'args': '-fw_cfg secret=do-not-show',
      'description': 'operator private note',
    }, kind: 'qemu');
    final visible = [
      ...qemu.compute,
      ...qemu.platform,
      ...qemu.storage,
      ...qemu.network,
    ].map((field) => '${field.label} ${field.value}').join(' ');

    expect(qemu.visibleFieldCount, 6);
    expect(qemu.withheldFields, 4);
    expect(qemu.malformedFields, 0);
    expect(visible, contains('CPU cores 4'));
    expect(visible, contains('scsi0'));
    expect(visible, contains('ip=10.0.0.10/24'));
    expect(visible, isNot(contains('super-secret')));
    expect(visible, isNot(contains('ssh-ed25519')));
    expect(visible, isNot(contains('do-not-show')));
    expect(visible, isNot(contains('operator private note')));

    final lxc = GuestConfiguration.fromApi({
      'cores': 2,
      'memory': 2048,
      'swap': 512,
      'hostname': 'ct-web',
      'rootfs': 'local-lvm:vm-202-disk-0,size=8G',
      'mp0': 'local:subvol-202-disk-1,mp=/srv',
      'net0': 'name=eth0,bridge=vmbr0,ip=dhcp',
      'password': 'hidden',
    }, kind: 'lxc');
    expect(lxc.visibleFieldCount, 7);
    expect(lxc.withheldFields, 1);
    expect(
      lxc.storage.map((field) => field.key),
      containsAll(['rootfs', 'mp0']),
    );
  });

  test('guest permission parsing keeps exact-path non-propagating grants', () {
    final permissions = GuestPermissionSnapshot.fromApi({
      '/vms/101': {
        'VM.Audit': 1,
        'VM.PowerMgmt': 0,
        'VM.Clone': true,
        'VM.Backup': 'false',
        'bad privilege': 1,
        'VM.BadFlag': {'unexpected': true},
      },
      '/vms/999': {'VM.Migrate': 1},
    }, vmid: 101);

    expect(permissions.has('VM.Audit'), isTrue);
    expect(permissions.has('VM.PowerMgmt'), isTrue);
    expect(permissions.has('VM.Clone'), isTrue);
    expect(permissions.has('VM.Backup'), isTrue);
    expect(permissions.has('VM.Migrate'), isFalse);
    expect(permissions.malformedPrivileges, 2);
    expect(permissions.truncated, isFalse);
  });

  test('node RRD samples reject invalid values without inventing metrics', () {
    final valid = NodeMetricPoint.fromApi({
      'time': 1700000000,
      'cpu': 0.25,
      'mem': 512,
      'maxmem': 1024,
    });
    expect(valid.cpuFraction, 0.25);
    expect(valid.memoryFraction, 0.5);

    expect(
      () => NodeMetricPoint.fromApi({
        'time': 1700000000,
        'cpu': 1.5,
        'mem': 2048,
        'maxmem': 1024,
      }),
      throwsFormatException,
    );
    expect(
      () => NodeMetricPoint.fromApi({'time': -1, 'cpu': 0.2}),
      throwsFormatException,
    );
  });

  test('storage RRD samples retain capacity without inventing ratios', () {
    final valid = StorageMetricPoint.fromApi({
      'time': 1700000000,
      'used': 512,
      'total': 1024,
    });
    expect(valid.usedBytes, 512);
    expect(valid.totalBytes, 1024);
    expect(valid.usageFraction, 0.5);

    final usedOnly = StorageMetricPoint.fromApi({
      'time': 1700000060,
      'used': 768.4,
      'total': 0,
    });
    expect(usedOnly.usedBytes, 768);
    expect(usedOnly.totalBytes, isNull);
    expect(usedOnly.usageFraction, isNull);

    final overCapacity = StorageMetricPoint.fromApi({
      'time': 1700000120,
      'used': 2048,
      'total': 1024,
    });
    expect(overCapacity.usageFraction, isNull);

    expect(
      () => StorageMetricPoint.fromApi({'time': -1, 'used': 10, 'total': 20}),
      throwsFormatException,
    );
    expect(
      () => StorageMetricPoint.fromApi({
        'time': 1700000000,
        'used': -1,
        'total': 0,
      }),
      throwsFormatException,
    );
  });

  test('missing or malformed guest I/O counters never become zero', () {
    final guest = Guest.fromResource({
      'type': 'lxc',
      'node': 'pve1',
      'vmid': 102,
      'netin': -1,
      'netout': '2048',
      'diskread': 1.5,
      'diskwrite': double.nan,
    });
    expect(guest.netIn, isNull);
    expect(guest.netOut, isNull);
    expect(guest.diskRead, isNull);
    expect(guest.diskWrite, isNull);
    expect(formatBytes(guest.netIn), '—');

    final counters = Guest.fromResource({
      'type': 'qemu',
      'node': 'pve2',
      'vmid': 201,
      'netin': 0,
      'netout': 1048576.0,
      'diskread': double.infinity,
    });
    expect(counters.netIn, 0);
    expect(counters.netOut, 1048576);
    expect(counters.diskRead, isNull);
    expect(counters.diskWrite, isNull);
  });

  test('guest RRD samples reject invalid values without inventing metrics', () {
    final point = GuestMetricPoint.fromApi({
      'time': 1700000000,
      'cpu': 0.25,
      'mem': 512,
      'maxmem': 1024,
    });
    expect(point.cpuFraction, 0.25);
    expect(point.memoryFraction, 0.5);
    expect(point.timestamp.isUtc, isTrue);

    final cpuOnly = GuestMetricPoint.fromApi({
      'time': 1700000060,
      'cpu': 0.5,
      'mem': '512',
      'maxmem': 1024,
    });
    expect(cpuOnly.cpuFraction, 0.5);
    expect(cpuOnly.memoryFraction, isNull);

    for (final json in [
      {'time': -1, 'cpu': 0.2},
      {'time': 1700000000, 'cpu': 1.5},
      {'time': 1700000000, 'mem': 2048, 'maxmem': 1024},
      {'time': 1700000000, 'cpu': double.nan},
    ]) {
      expect(
        () => GuestMetricPoint.fromApi(Map<String, dynamic>.from(json)),
        throwsFormatException,
      );
    }
  });

  test('task log parsing bounds long lines and rejects malformed rows', () {
    final row = TaskLogEntry.fromApi({
      'n': 8,
      't': List.filled(600, 'x').join(),
    });
    expect(row.number, 8);
    expect(row.text.length, 501);
    expect(row.text.endsWith('…'), isTrue);
    expect(
      () => TaskLogEntry.fromApi({'n': -1, 't': 'bad'}),
      throwsFormatException,
    );
    expect(
      () => TaskLogEntry.fromApi({'n': 1, 't': 42}),
      throwsFormatException,
    );
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
    RecentServerTask from(Map<String, Object?> data) {
      final payload = <String, dynamic>{'upid': upid, ...data};
      return RecentServerTask.fromApi(payload, node: 'pve1');
    }

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

  test('backup validation confidence stays evidence-limited', () {
    const archive = GuestBackupArchive(
      node: 'pve1',
      storage: 'backup',
      volid: 'backup:backup/vzdump-qemu-101-2026_11_11-10_00_00.vma.zst',
      kind: 'qemu',
      vmid: 101,
      sizeBytes: 1024,
    );
    final succeeded = RecentServerTask(
      upid: 'UPID:pve1:1:2:3:vzdump:101:user@pve:',
      node: 'pve1',
      operation: 'vzdump',
      resourceId: '101',
      status: 'stopped',
      exitStatus: 'OK',
      endedAt: DateTime.utc(2026, 11, 11, 10),
    );

    final notAssessed = GuestBackupValidationAssessment.evaluate(
      archives: null,
      backupTasks: [succeeded],
    );
    expect(
      notAssessed.confidence,
      BackupValidationConfidence.notAssessed,
    );
    expect(notAssessed.taskEvidence, BackupTaskEvidence.succeeded);
    expect(notAssessed.hasVisibleArchive, isFalse);

    final empty = GuestBackupValidationAssessment.evaluate(
      archives: const GuestBackupArchiveInventory(
        storage: 'backup',
        archives: [],
      ),
      backupTasks: [succeeded],
    );
    expect(empty.confidence, BackupValidationConfidence.insufficient);
    expect(empty.visibleArchiveCount, 0);
    expect(empty.headline, 'Insufficient evidence');

    final visible = GuestBackupValidationAssessment.evaluate(
      archives: const GuestBackupArchiveInventory(
        storage: 'backup',
        archives: [archive],
        ignoredRecords: 2,
        truncated: true,
      ),
      backupTasks: [succeeded],
    );
    expect(visible.confidence, BackupValidationConfidence.partial);
    expect(visible.headline, 'Partial evidence');
    expect(visible.latestArchive, same(archive));
    expect(visible.visibleArchiveCount, 1);
    expect(visible.ignoredArchiveRows, 2);
    expect(visible.archiveListTruncated, isTrue);
  });

  test('backup validation uses the newest task without upgrading confidence', () {
    final olderSuccess = RecentServerTask(
      upid: 'UPID:pve1:1:2:3:vzdump:101:user@pve:',
      node: 'pve1',
      operation: 'vzdump',
      resourceId: '101',
      status: 'stopped',
      exitStatus: 'OK',
      endedAt: DateTime.utc(2026, 11, 10, 10),
    );
    final newerFailure = RecentServerTask(
      upid: 'UPID:pve1:4:5:6:vzdump:101:user@pve:',
      node: 'pve1',
      operation: 'vzdump',
      resourceId: '101',
      status: 'stopped',
      exitStatus: 'ERROR',
      endedAt: DateTime.utc(2026, 11, 11, 10),
    );

    final result = GuestBackupValidationAssessment.evaluate(
      archives: const GuestBackupArchiveInventory(
        storage: 'backup',
        archives: [
          GuestBackupArchive(
            node: 'pve1',
            storage: 'backup',
            volid:
                'backup:backup/vzdump-qemu-101-2026_11_09-10_00_00.vma.zst',
            kind: 'qemu',
            vmid: 101,
          ),
        ],
      ),
      backupTasks: [olderSuccess, newerFailure],
    );

    expect(result.confidence, BackupValidationConfidence.partial);
    expect(result.taskEvidence, BackupTaskEvidence.failed);
    expect(result.latestBackupTask, same(newerFailure));
  });

  test('template marker is parsed and blocks every power action', () {
    final template = Guest.fromResource({
      'type': 'qemu',
      'node': 'pve1',
      'vmid': 900,
      'name': 'Ubuntu template',
      'status': 'stopped',
      'template': 1,
    });
    expect(template.isTemplate, isTrue);
    for (final action in GuestAction.values) {
      expect(action.allowedFor(template), isFalse);
    }

    final regular = Guest.fromResource({
      'type': 'lxc',
      'node': 'pve1',
      'vmid': 901,
      'status': 'stopped',
      'template': '0',
    });
    expect(regular.isTemplate, isFalse);
    expect(GuestAction.start.allowedFor(regular), isTrue);
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

  test('template clone request validates VMID and DNS-safe name', () {
    expect(
      const GuestCloneRequest(
        newVmid: 901,
        name: ' ubuntu-copy ',
      ).normalized().name,
      'ubuntu-copy',
    );
    expect(
      const GuestCloneRequest(newVmid: 901, name: 'ubuntu-copy').isValid,
      isTrue,
    );
    for (final request in [
      const GuestCloneRequest(newVmid: 99, name: 'valid'),
      const GuestCloneRequest(newVmid: 1000000000, name: 'valid'),
      const GuestCloneRequest(newVmid: 901, name: ''),
      const GuestCloneRequest(newVmid: 901, name: '-bad'),
      const GuestCloneRequest(newVmid: 901, name: 'bad-'),
      const GuestCloneRequest(newVmid: 901, name: 'bad name'),
    ]) {
      expect(
        request.isValid,
        isFalse,
        reason: '${request.newVmid}/${request.name}',
      );
      expect(request.validationError, isNotNull);
    }
  });

  test('QEMU create request validates constrained shell inputs', () {
    const valid = QemuCreateRequest(
      node: ' pve1 ',
      vmid: 901,
      name: ' app-vm ',
      cores: 4,
      memoryMiB: 4096,
      onBoot: true,
    );
    expect(valid.isValid, isTrue);
    final normalized = valid.normalized();
    expect(normalized.node, 'pve1');
    expect(normalized.name, 'app-vm');
    expect(normalized.vmid, 901);
    expect(normalized.cores, 4);
    expect(normalized.memoryMiB, 4096);
    expect(normalized.onBoot, isTrue);

    for (final request in [
      const QemuCreateRequest(
        node: '',
        vmid: 901,
        name: 'valid',
        cores: 2,
        memoryMiB: 2048,
      ),
      const QemuCreateRequest(
        node: 'pve1',
        vmid: 99,
        name: 'valid',
        cores: 2,
        memoryMiB: 2048,
      ),
      const QemuCreateRequest(
        node: 'pve1',
        vmid: 901,
        name: 'bad name',
        cores: 2,
        memoryMiB: 2048,
      ),
      const QemuCreateRequest(
        node: 'pve1',
        vmid: 901,
        name: 'valid',
        cores: 0,
        memoryMiB: 2048,
      ),
      const QemuCreateRequest(
        node: 'pve1',
        vmid: 901,
        name: 'valid',
        cores: 2,
        memoryMiB: 127,
      ),
    ]) {
      expect(request.isValid, isFalse);
      expect(request.validationError, isNotNull);
    }
  });

  test('QEMU create rejects unsafe node paths and all out-of-range inputs', () {
    QemuCreateRequest request({
      String node = 'pve1',
      int vmid = 901,
      String name = 'valid',
      int cores = 2,
      int memory = 2048,
    }) => QemuCreateRequest(
      node: node,
      vmid: vmid,
      name: name,
      cores: cores,
      memoryMiB: memory,
    );
    for (final node in [
      '.',
      '..',
      '../pve1',
      'pve1/other',
      'pve 1',
      'pve1\nqemu',
      'pve1?x=y',
      'pve1#fragment',
      'x' * 65,
    ]) {
      expect(request(node: node).isValid, isFalse, reason: node);
    }
    for (final value in [
      request(vmid: 1000000000),
      request(cores: 65),
      request(memory: 262145),
      request(name: 'x' * 64),
      request(name: '-bad'),
      request(name: 'bad-'),
      request(name: ' '),
    ]) {
      expect(value.isValid, isFalse);
    }
    expect(request(vmid: 100, cores: 1, memory: 128).isValid, isTrue);
    expect(
      request(
        vmid: 999999999,
        cores: 64,
        memory: 262144,
        name: 'x' * 63,
      ).isValid,
      isTrue,
    );
  });
}
