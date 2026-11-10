import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'components.dart';
import 'template_clone_page.dart';
import 'theme.dart';

class GuestPage extends StatefulWidget {
  const GuestPage({
    super.key,
    required this.controller,
    required this.guest,
    required this.profileId,
    required this.generation,
  });
  final AppController controller;
  final Guest guest;
  final String profileId;
  final int generation;

  @override
  State<GuestPage> createState() => _GuestPageState();
}

class _GuestPageState extends State<GuestPage> {
  bool submitting = false;
  bool loadingMetrics = false;
  GuestMetricTimeframe metricTimeframe = GuestMetricTimeframe.hour;
  GuestMetricSeries? metricSeries;
  String? metricError;
  bool loadingSnapshots = false;
  GuestSnapshotInventory? snapshotInventory;
  String? snapshotError;
  DateTime? snapshotsLoadedAt;
  bool loadingBackupArchives = false;
  GuestBackupArchiveInventory? backupArchiveInventory;
  String? backupArchiveError;
  DateTime? backupArchivesLoadedAt;
  String? selectedBackupArchiveStorage;
  bool loadingConfiguration = false;
  GuestConfiguration? configuration;
  String? configurationError;
  DateTime? configurationLoadedAt;
  bool loadingPermissions = false;
  GuestPermissionSnapshot? permissionSnapshot;
  String? permissionError;
  DateTime? permissionsLoadedAt;

  bool get _currentSession =>
      widget.controller.active?.id == widget.profileId &&
      widget.controller.connectionGeneration == widget.generation;

  Guest? currentGuest() {
    if (!_currentSession) return null;
    final inv = widget.controller.inventory;
    if (inv == null) return null;
    for (final guest in inv.guests) {
      if (guest.vmid == widget.guest.vmid &&
          guest.node == widget.guest.node &&
          guest.kind == widget.guest.kind) {
        return guest;
      }
    }
    return null;
  }

  Future<void> loadMetrics() async {
    final guest = currentGuest();
    if (loadingMetrics || !_currentSession || guest == null) return;
    setState(() {
      loadingMetrics = true;
      metricError = null;
    });
    try {
      final result = await widget.controller.inspectGuestMetrics(
        profileId: widget.profileId,
        generation: widget.generation,
        guest: guest,
        timeframe: metricTimeframe,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        metricSeries = result;
        if (result == null) {
          metricError =
              'Guest performance data is no longer current. Refresh and reopen this guest.';
        }
      });
    } on PveFailure catch (error) {
      if (!mounted || !_currentSession) return;
      setState(() {
        metricSeries = null;
        metricError = error.message;
      });
    } catch (_) {
      if (!mounted || !_currentSession) return;
      setState(() {
        metricSeries = null;
        metricError = 'Could not load guest performance history.';
      });
    } finally {
      if (mounted && _currentSession) {
        setState(() => loadingMetrics = false);
      }
    }
  }

  void selectMetricTimeframe(GuestMetricTimeframe value) {
    if (value == metricTimeframe) return;
    setState(() {
      metricTimeframe = value;
      metricSeries = null;
      metricError = null;
    });
  }

  Future<void> loadConfiguration() async {
    final guest = currentGuest();
    if (loadingConfiguration || !_currentSession || guest == null) return;
    setState(() {
      loadingConfiguration = true;
      configurationError = null;
    });
    try {
      final result = await widget.controller.inspectGuestConfiguration(
        profileId: widget.profileId,
        generation: widget.generation,
        guest: guest,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        configuration = result;
        configurationLoadedAt = result == null ? null : DateTime.now();
        if (result == null) {
          configurationError =
              'Guest configuration is no longer current. Refresh and reopen this guest.';
        }
      });
    } on PveFailure catch (error) {
      if (!mounted || !_currentSession) return;
      setState(() {
        configuration = null;
        configurationLoadedAt = null;
        configurationError = error.message;
      });
    } catch (_) {
      if (!mounted || !_currentSession) return;
      setState(() {
        configuration = null;
        configurationLoadedAt = null;
        configurationError = 'Could not load guest configuration.';
      });
    } finally {
      if (mounted && _currentSession) {
        setState(() => loadingConfiguration = false);
      }
    }
  }

  Future<void> loadPermissions() async {
    final guest = currentGuest();
    if (loadingPermissions || !_currentSession || guest == null) return;
    setState(() {
      loadingPermissions = true;
      permissionError = null;
    });
    try {
      final result = await widget.controller.inspectGuestPermissions(
        profileId: widget.profileId,
        generation: widget.generation,
        guest: guest,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        permissionSnapshot = result;
        permissionsLoadedAt = result == null ? null : DateTime.now();
        if (result == null) {
          permissionError =
              'Guest permission data is no longer current. Refresh and reopen this guest.';
        }
      });
    } on PveFailure catch (error) {
      if (!mounted || !_currentSession) return;
      setState(() {
        permissionSnapshot = null;
        permissionsLoadedAt = null;
        permissionError = error.message;
      });
    } catch (_) {
      if (!mounted || !_currentSession) return;
      setState(() {
        permissionSnapshot = null;
        permissionsLoadedAt = null;
        permissionError = 'Could not load guest permission hints.';
      });
    } finally {
      if (mounted && _currentSession) {
        setState(() => loadingPermissions = false);
      }
    }
  }

  Future<void> loadSnapshots() async {
    final guest = currentGuest();
    if (loadingSnapshots || !_currentSession || guest == null) return;
    setState(() {
      loadingSnapshots = true;
      snapshotError = null;
    });
    try {
      final result = await widget.controller.inspectGuestSnapshots(
        profileId: widget.profileId,
        generation: widget.generation,
        guest: guest,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        snapshotInventory = result;
        snapshotsLoadedAt = result == null ? null : DateTime.now();
        if (result == null) {
          snapshotError =
              'Snapshot inventory is no longer current. Refresh and reopen this guest.';
        }
      });
    } on PveFailure catch (error) {
      if (!mounted || !_currentSession) return;
      setState(() {
        snapshotInventory = null;
        snapshotsLoadedAt = null;
        snapshotError = error.message;
      });
    } catch (_) {
      if (!mounted || !_currentSession) return;
      setState(() {
        snapshotInventory = null;
        snapshotsLoadedAt = null;
        snapshotError = 'Could not load guest snapshots.';
      });
    } finally {
      if (mounted && _currentSession) {
        setState(() => loadingSnapshots = false);
      }
    }
  }

  Future<void> loadBackupArchives() async {
    final guest = currentGuest();
    if (loadingBackupArchives || !_currentSession || guest == null) return;
    final storages = _backupStorageIds(guest);
    var storage = selectedBackupArchiveStorage;
    if (storage == null || !storages.contains(storage)) {
      storage = storages.length == 1 ? storages.single : null;
    }
    if (storage == null) {
      setState(() {
        backupArchiveInventory = null;
        backupArchivesLoadedAt = null;
        backupArchiveError =
            'Choose one backup storage before loading archives.';
      });
      return;
    }

    setState(() {
      loadingBackupArchives = true;
      selectedBackupArchiveStorage = storage;
      backupArchiveError = null;
    });
    try {
      final result = await widget.controller.inspectGuestBackupArchives(
        profileId: widget.profileId,
        generation: widget.generation,
        guest: guest,
        storage: storage,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        backupArchiveInventory = result;
        backupArchivesLoadedAt = result == null ? null : DateTime.now();
        if (result == null) {
          backupArchiveError =
              'Backup archive data is no longer current. Refresh and reopen this guest.';
        }
      });
    } on PveFailure catch (error) {
      if (!mounted || !_currentSession) return;
      setState(() {
        backupArchiveInventory = null;
        backupArchivesLoadedAt = null;
        backupArchiveError = error.message;
      });
    } catch (_) {
      if (!mounted || !_currentSession) return;
      setState(() {
        backupArchiveInventory = null;
        backupArchivesLoadedAt = null;
        backupArchiveError = 'Could not load backup archives.';
      });
    } finally {
      if (mounted && _currentSession) {
        setState(() => loadingBackupArchives = false);
      }
    }
  }

  Future<void> _openSnapshotCreate(Guest source) async {
    if (!_currentSession || submitting || source.isTemplate) return;
    if (!source.isRunning && !source.isStopped) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refresh the guest before taking a snapshot.'),
        ),
      );
      return;
    }

    final nameController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final request = GuestSnapshotCreateRequest(
            name: nameController.text,
          ).normalized();
          final validationError = request.validationError;
          return AlertDialog(
            title: Text('Snapshot ${source.name}?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${source.node} • ${source.kind.toUpperCase()} ${source.vmid}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Snapshots are not backups. This create-only flow captures guest disk/configuration snapshot state supported by Proxmox. VirtHelm does not request QEMU RAM-state capture.',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Immediately before one POST, VirtHelm revalidates the exact guest and state, VM.Snapshot privilege, and a fresh complete snapshot list for name collisions. The mutation is never retried automatically.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('guest-snapshot-name'),
                    controller: nameController,
                    autofocus: true,
                    maxLength: 64,
                    decoration: InputDecoration(
                      labelText: 'Snapshot name',
                      hintText: 'before-upgrade',
                      border: const OutlineInputBorder(),
                      errorText: nameController.text.isEmpty
                          ? null
                          : validationError,
                      helperText:
                          'Letters, numbers, underscores, and hyphens only.',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('guest-snapshot-create-submit'),
                onPressed:
                    validationError == null && nameController.text.isNotEmpty
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('Create snapshot'),
              ),
            ],
          );
        },
      ),
    );
    final snapshotName = nameController.text;
    nameController.dispose();
    if (!mounted || !_currentSession || confirmed != true) return;

    setState(() => submitting = true);
    try {
      await widget.controller.runGuestSnapshotCreate(
        source,
        GuestSnapshotCreateRequest(name: snapshotName),
        profileId: widget.profileId,
        generation: widget.generation,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        snapshotInventory = null;
        snapshotsLoadedAt = null;
        snapshotError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Snapshot task submitted. Check Tasks, then refresh snapshots after completion.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted || !_currentSession) return;
      final message = error is PveFailure
          ? error.message
          : 'Could not submit snapshot.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted && _currentSession) setState(() => submitting = false);
    }
  }

  List<String> _backupStorageIds(Guest? guest) {
    if (guest == null || !_currentSession) return const <String>[];
    final result = widget.controller.storages
        .where(
          (storage) =>
              storage.node == guest.node &&
              storage.enabled == true &&
              storage.active == true &&
              storage.contentTypes.contains('backup'),
        )
        .map((storage) => storage.id)
        .toSet()
        .toList();
    result.sort();
    return result;
  }

  Future<void> _openBackup(Guest source) async {
    if (!_currentSession || submitting || source.isTemplate) return;
    if (!source.isRunning && !source.isStopped) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refresh the guest before starting a backup.'),
        ),
      );
      return;
    }
    final storages = _backupStorageIds(source);
    if (storages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No active backup-capable storage is visible on this guest node.',
          ),
        ),
      );
      return;
    }

    String? selectedStorage = storages.length == 1 ? storages.single : null;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Back up ${source.name}?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${source.node} • ${source.kind.toUpperCase()} ${source.vmid}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'VirtHelm will start one Proxmox vzdump task in snapshot mode for this guest and selected storage. It does not request pruning, retention changes, hooks, fleecing, bandwidth, performance, or ionice tuning.',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'A successful task is not proof that the produced archive is verified or restorable. Restore remains unavailable in this guarded slice.',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Immediately before one POST, VirtHelm revalidates the exact guest and state, VM.Backup privilege, active backup-capable storage, and Datastore.AllocateSpace on that storage. The mutation is never retried automatically.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('guest-backup-storage'),
                    initialValue: selectedStorage,
                    decoration: const InputDecoration(
                      labelText: 'Backup storage',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final storage in storages)
                        DropdownMenuItem(value: storage, child: Text(storage)),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selectedStorage = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('guest-backup-submit'),
                onPressed: selectedStorage == null
                    ? null
                    : () => Navigator.of(dialogContext).pop(true),
                child: const Text('Start backup'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted ||
        !_currentSession ||
        confirmed != true ||
        selectedStorage == null) {
      return;
    }

    setState(() => submitting = true);
    try {
      await widget.controller.runGuestBackup(
        source,
        GuestBackupRequest(storage: selectedStorage!),
        profileId: widget.profileId,
        generation: widget.generation,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        selectedBackupArchiveStorage = selectedStorage;
        backupArchiveInventory = null;
        backupArchivesLoadedAt = null;
        backupArchiveError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup task submitted. Check Tasks and load the storage archive list after completion.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted || !_currentSession) return;
      final message = error is PveFailure
          ? error.message
          : 'Could not submit backup.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted && _currentSession) setState(() => submitting = false);
    }
  }

  List<RecentServerTask> _backupTasks(Guest? guest) {
    if (guest == null || !_currentSession) return const <RecentServerTask>[];
    final vmid = guest.vmid.toString();
    final matches = widget.controller.serverTasks
        .where(
          (task) =>
              task.operation.toLowerCase() == 'vzdump' &&
              task.resourceId == vmid,
        )
        .toList(growable: false);
    matches.sort((a, b) {
      final aTime =
          a.endedAt ??
          a.startedAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final bTime =
          b.endedAt ??
          b.startedAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return bTime.compareTo(aTime);
    });
    return matches.take(8).toList(growable: false);
  }

  String _snapshotSubtitle(GuestSnapshot snapshot) {
    final lines = <String>[];
    if (snapshot.isCurrent) {
      lines.add('Current configuration reported by Proxmox.');
    } else if (snapshot.createdAt != null) {
      lines.add('Created ${formatAge(snapshot.createdAt!)}');
    } else {
      lines.add('Creation time unavailable');
    }
    if (snapshot.parent != null) lines.add('Parent: ${snapshot.parent}');
    if (snapshot.includesMemory == true) lines.add('Includes VM memory state');
    if (snapshot.description != null) lines.add(snapshot.description!);
    return lines.join('\n');
  }

  String _backupTaskSubtitle(RecentServerTask task) {
    final when = task.endedAt ?? task.startedAt;
    final parts = <String>[task.node];
    if (when != null) parts.add(formatAge(when));
    if (task.exitStatus != null && task.exitStatus!.trim().isNotEmpty) {
      parts.add('Exit: ${task.exitStatus}');
    }
    return parts.join(' • ');
  }

  String _backupArchiveSubtitle(GuestBackupArchive archive) {
    final parts = <String>[archive.storage];
    if (archive.createdAt != null) {
      parts.add('Created ${formatAge(archive.createdAt!)}');
    } else {
      parts.add('Creation time unavailable');
    }
    if (archive.sizeBytes != null) {
      parts.add(formatBytes(archive.sizeBytes));
    }
    if (archive.format != null) {
      parts.add(archive.format!);
    }
    if (archive.protected == true) {
      parts.add('Protected flag reported by PVE');
    }
    return parts.join(' • ');
  }

  String _backupValidationArchiveText(
    GuestBackupValidationAssessment assessment,
  ) {
    final archive = assessment.latestArchive;
    if (!assessment.archiveReadCompleted) {
      return 'Not loaded. Load backup archives for the selected storage.';
    }
    if (archive == null) {
      return 'No matching backup archive is currently visible.';
    }
    final parts = <String>[
      '${assessment.visibleArchiveCount} matching archive'
          '${assessment.visibleArchiveCount == 1 ? '' : 's'} visible',
      'exact ${archive.kind.toUpperCase()} ${archive.vmid} identity',
    ];
    if (archive.createdAt != null) {
      parts.add('latest created ${formatAge(archive.createdAt!)}');
    }
    if (archive.sizeBytes != null) {
      parts.add(formatBytes(archive.sizeBytes));
    }
    if (assessment.ignoredArchiveRows > 0) {
      parts.add('${assessment.ignoredArchiveRows} unusable row(s) ignored');
    }
    if (assessment.archiveListTruncated) {
      parts.add('response truncated locally');
    }
    return parts.join(' • ');
  }

  String _backupValidationTaskText(
    GuestBackupValidationAssessment assessment,
  ) {
    final task = assessment.latestBackupTask;
    if (task == null) {
      return 'No vzdump task for this VMID is visible in the current recent-task window.';
    }
    final when = task.endedAt ?? task.startedAt;
    final state = switch (assessment.taskEvidence) {
      BackupTaskEvidence.none => 'not visible',
      BackupTaskEvidence.running => 'running',
      BackupTaskEvidence.succeeded => 'succeeded',
      BackupTaskEvidence.failed => 'failed',
      BackupTaskEvidence.unknown => 'unknown',
    };
    return when == null ? 'Latest visible task: $state.' : 'Latest visible task: $state • ${formatAge(when)}.';
  }

  Future<void> execute(Guest guest, GuestAction action) async {
    if (submitting || !_currentSession) return;
    final isForce = action == GuestAction.stop;
    final tlsWarning =
        widget.controller.active?.allowInvalidCertificates == true
        ? '\n\nINSECURE: server certificate verification is disabled.'
        : '';
    final target =
        'Target: ${widget.controller.active?.name ?? 'Unknown connection'} / '
        '${guest.node} / ${guest.kind.toUpperCase()} ${guest.vmid}.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          if (!_currentSession) {
            return AlertDialog(
              title: const Text('Connection changed'),
              content: const Text(
                'Guest details are no longer current. Reopen this guest '
                'from the active connection.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Dismiss'),
                ),
              ],
            );
          }
          return AlertDialog(
            title: Text('${action.label} ${guest.name}?'),
            content: SingleChildScrollView(
              child: Text(
                (isForce
                        ? '$target\n\nForce stop immediately terminates this guest '
                              'without a graceful shutdown and can cause data loss. '
                              'Check the connection, node, VMID, and running services.'
                        : '$target\n\nProxmox will run this operation asynchronously.') +
                    tlsWarning,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(isForce ? 'Force stop' : 'Confirm'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !mounted || !_currentSession) return;
    setState(() => submitting = true);
    try {
      await widget.controller.runAction(
        guest,
        action,
        profileId: widget.profileId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task submitted. Check Tasks for its final result.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is PveFailure ? e.message : 'Could not submit action.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _openTemplateClone(Guest source) async {
    if (!_currentSession || submitting) return;
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TemplateClonePage(
          controller: widget.controller,
          source: source,
          profileId: widget.profileId,
          generation: widget.generation,
        ),
      ),
    );
    if (!mounted || !_currentSession || submitted != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Clone task submitted. Check Tasks for its final result.',
        ),
      ),
    );
  }

  List<Node> _migrationTargets(Guest guest) {
    final inv = widget.controller.inventory;
    if (inv == null) return const <Node>[];
    final targets =
        inv.nodes
            .where((node) => node.name != guest.node && node.status == 'online')
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return targets;
  }

  String _migrationImpact(Guest guest) {
    if (guest.kind == 'lxc' && guest.isRunning) {
      return 'Restart migration will stop the container, move it, and start it on the destination. Downtime is expected.';
    }
    if (guest.kind == 'qemu' && guest.isRunning) {
      return 'VirtHelm will request live QEMU migration. This guarded slice allows only server-preflighted guests on shared storage with no local host resources.';
    }
    return 'The guest is stopped, so VirtHelm will request an offline migration.';
  }

  Future<void> _openMigration(Guest source) async {
    if (!_currentSession || submitting) return;
    final targets = _migrationTargets(source);
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other online destination node is available.'),
        ),
      );
      return;
    }

    final target = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Choose destination node'),
        children: [
          for (final node in targets)
            SimpleDialogOption(
              key: Key('guest-migration-target-${node.name}'),
              onPressed: () => Navigator.of(dialogContext).pop(node.name),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dns_rounded),
                title: Text(node.name),
                subtitle: const Text('Online'),
              ),
            ),
        ],
      ),
    );
    if (!mounted || !_currentSession || target == null) return;

    final confirmation = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final matches = confirmation.text.trim() == source.vmid.toString();
          return AlertDialog(
            title: Text('Migrate ${source.name}?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${source.node} → $target',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(_migrationImpact(source)),
                  const SizedBox(height: 12),
                  const Text(
                    'The destination, guest state, VM.Migrate privilege, and server migration preflight are revalidated immediately before one POST. VirtHelm never retries a migration POST automatically.',
                  ),
                  if (source.kind == 'lxc') ...[
                    const SizedBox(height: 8),
                    const Text(
                      'LXC storage transfer and final authorization remain Proxmox-authoritative; storage remapping and force options are not exposed.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Type VMID ${source.vmid} to confirm.',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('guest-migration-confirmation'),
                    controller: confirmation,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'VMID confirmation',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('guest-migration-submit'),
                onPressed: matches
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('Migrate'),
              ),
            ],
          );
        },
      ),
    );
    confirmation.dispose();
    if (!mounted || !_currentSession || confirmed != true) return;

    setState(() => submitting = true);
    try {
      await widget.controller.runGuestMigration(
        source,
        GuestMigrationRequest(targetNode: target),
        profileId: widget.profileId,
        generation: widget.generation,
      );
      if (!mounted || !_currentSession) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Migration task submitted. Check Tasks for its final result.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        final message = error is PveFailure
            ? error.message
            : 'Could not submit migration.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _openDeletion(Guest source) async {
    if (!_currentSession ||
        submitting ||
        !source.isStopped ||
        source.isTemplate) {
      return;
    }
    final expected = 'DELETE ${source.name} ${source.vmid}';
    final confirmation = TextEditingController();
    var backupAcknowledged = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final matches = confirmation.text.trim() == expected;
          return AlertDialog(
            title: Text('Permanently delete ${source.name}?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${source.kind.toUpperCase()} • ${source.node} • VMID ${source.vmid}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This permanently destroys the guest and the used/owned volumes Proxmox associates with it. '
                    'Snapshots are not backups. VirtHelm does not expose skip-lock, purge, or unreferenced-disk deletion options in this guarded slice.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The guest must remain stopped. The exact guest identity, clean inventory, and VM.Allocate privilege are revalidated immediately before exactly one DELETE request. VirtHelm never retries a deletion mutation automatically.',
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    key: const Key('guest-delete-backup-ack'),
                    contentPadding: EdgeInsets.zero,
                    value: backupAcknowledged,
                    onChanged: (value) => setDialogState(
                      () => backupAcknowledged = value ?? false,
                    ),
                    title: const Text(
                      'I verified any required recoverable backup outside this confirmation.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Type exactly: $expected',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('guest-delete-confirmation'),
                    controller: confirmation,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Destructive confirmation',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('guest-delete-submit'),
                onPressed: matches && backupAcknowledged
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('Delete permanently'),
              ),
            ],
          );
        },
      ),
    );
    confirmation.dispose();
    if (!mounted || !_currentSession || confirmed != true) return;

    setState(() => submitting = true);
    try {
      await widget.controller.runGuestDeletion(
        source,
        profileId: widget.profileId,
        generation: widget.generation,
      );
      if (!mounted || !_currentSession) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Deletion task submitted. Check Tasks for its final result.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        final message = error is PveFailure
            ? error.message
            : 'Could not submit deletion.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  GuestAction _primaryAction(Guest? guest) {
    if (guest == null) return GuestAction.start;
    return guest.isStopped ? GuestAction.start : GuestAction.shutdown;
  }

  IconData _actionIcon(GuestAction action) => switch (action) {
    GuestAction.start => Icons.play_arrow_rounded,
    GuestAction.shutdown => Icons.power_settings_new_rounded,
    GuestAction.reboot => Icons.restart_alt_rounded,
    GuestAction.stop => Icons.warning_amber_rounded,
  };

  String? _guardReason(Guest? guest, bool operationBlocked) {
    if (guest == null) {
      return 'Guest is not present in the current inventory.';
    }
    if (guest.isTemplate) {
      return 'Template power actions are unavailable. Use the reviewed clone wizard for a full same-node clone.';
    }
    if (operationBlocked) {
      return 'An operation is pending or its outcome is uncertain. Check server Tasks before another action.';
    }
    if (!widget.controller.isInventoryFresh) {
      return 'STALE / OFFLINE — actions are disabled until a fresh refresh.';
    }
    if (!widget.controller.isInventoryWriteSafe) {
      return widget.controller.inventoryWarning ??
          'Inventory verification is incomplete — actions disabled.';
    }
    if (widget.controller.refreshing) {
      return 'Refreshing inventory — actions are temporarily disabled.';
    }
    return null;
  }

  Widget _tabList({required Key key, required List<Widget> children}) =>
      RefreshIndicator(
        onRefresh: widget.controller.refresh,
        child: ListView(
          key: key,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
          children: children,
        ),
      );

  Widget _identityHeading(
    Guest? guest,
    ColorScheme scheme, {
    required bool includeStatus,
  }) => Row(
    children: [
      CircleAvatar(
        radius: 26,
        backgroundColor: scheme.primaryContainer,
        child: Icon(
          widget.guest.kind == 'qemu'
              ? Icons.computer_rounded
              : Icons.view_in_ar_rounded,
          color: scheme.onPrimaryContainer,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              guest?.name ?? widget.guest.name,
              style: Theme.of(context).textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${widget.guest.kind.toUpperCase()} • VMID ${widget.guest.vmid}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      if (includeStatus) StatusChip(status: guest?.status ?? 'unavailable'),
    ],
  );

  Widget _identityCard(Guest? guest, ColorScheme scheme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (MediaQuery.textScalerOf(context).scale(12) > 16) ...[
            _identityHeading(guest, scheme, includeStatus: false),
            const SizedBox(height: 10),
            StatusChip(status: guest?.status ?? 'unavailable'),
          ] else
            _identityHeading(guest, scheme, includeStatus: true),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(
                icon: Icons.dns_outlined,
                label: 'Node: ${widget.guest.node}',
              ),
              if (guest?.isTemplate == true)
                const _InfoPill(
                  icon: Icons.copy_all_outlined,
                  label: 'Template',
                ),
              if (guest?.pool != null)
                _InfoPill(
                  icon: Icons.folder_outlined,
                  label: 'Pool: ${guest!.pool}',
                ),
              if (guest != null && guest.tags.isNotEmpty)
                _InfoPill(
                  icon: Icons.sell_outlined,
                  label: 'Tags: ${guest.tags.join(', ')}',
                ),
            ],
          ),
          if (widget.controller.inventory != null) ...[
            const SizedBox(height: 10),
            Text(
              'Last refreshed ${formatAge(widget.controller.inventory!.fetchedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (!widget.controller.isInventoryFresh) ...[
            const SizedBox(height: 10),
            Text(
              'STALE / OFFLINE — operations disabled until a fresh refresh.',
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (!widget.controller.isInventoryWriteSafe) ...[
            const SizedBox(height: 10),
            Text(
              widget.controller.inventoryWarning ??
                  'Inventory verification is incomplete — operations disabled.',
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (guest != null &&
              widget.controller.isGuestActionBlocked(guest)) ...[
            const SizedBox(height: 10),
            Text(
              'An operation is pending or its outcome is uncertain. '
              'Check server Tasks before attempting another action.',
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (guest == null) ...[
            const SizedBox(height: 8),
            const Text(
              'The guest is not present at its previous node. It may have moved.',
            ),
          ],
        ],
      ),
    ),
  );

  Widget _overviewTab(Guest? guest, ColorScheme scheme) => _tabList(
    key: const Key('guest-overview-list'),
    children: [
      _identityCard(guest, scheme),
      const SizedBox(height: 22),
      Text('Live utilization', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      MetricBar(
        label: 'CPU',
        value: formatPercent(guest?.cpu),
        fraction: guest?.cpu,
        icon: Icons.memory_rounded,
      ),
      const SizedBox(height: 8),
      MetricBar(
        label: 'Memory',
        value: '${formatBytes(guest?.mem)} / ${formatBytes(guest?.maxMem)}',
        fraction:
            guest != null &&
                guest.maxMem != null &&
                guest.maxMem! > 0 &&
                guest.mem != null
            ? guest.mem! / guest.maxMem!
            : null,
        icon: Icons.storage_rounded,
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          title: const Text('Disk usage'),
          subtitle: Text(
            '${formatBytes(guest?.disk)} / ${formatBytes(guest?.maxDisk)}',
          ),
          leading: const Icon(Icons.disc_full_outlined),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          title: const Text('Uptime'),
          subtitle: Text(formatUptime(guest?.uptime)),
          leading: const Icon(Icons.schedule_rounded),
        ),
      ),
      const SizedBox(height: 22),
      Text(
        guest?.isTemplate == true
            ? 'This is a template discovered from the current cluster inventory. '
                  'Power actions are disabled; the reviewed clone wizard is available below while create-from-scratch remains gated.'
            : 'Power actions are available below. Each operation is checked '
                  'against fresh server state and tracked as a task.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 14),
      Text(
        'Read-only reviewed configuration fields are available in the '
        'Configuration tab. Console, snapshot changes, migrations, and '
        'configuration editing remain gated behind additional validated workflows.',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _metricsTab() {
    final points = metricSeries?.points ?? const <GuestMetricPoint>[];
    final cpuPoints = points
        .where((point) => point.cpuFraction != null)
        .toList(growable: false);
    final memoryPoints = points
        .where((point) => point.memoryFraction != null)
        .toList(growable: false);
    final cpuHistory = normalizedSamples(
      cpuPoints.map((point) => point.cpuFraction),
    );
    final memoryHistory = normalizedSamples(
      memoryPoints.map((point) => point.memoryFraction),
    );
    return _tabList(
      key: const Key('guest-metrics-list'),
      children: [
        Text(
          'Performance history',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Read-only Proxmox RRD averages loaded only when requested. '
          'History stays in this screen and is not cached.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final timeframe in GuestMetricTimeframe.values)
              ChoiceChip(
                label: Text(timeframe.label),
                selected: metricTimeframe == timeframe,
                onSelected: currentGuest() == null || loadingMetrics
                    ? null
                    : (_) => selectMetricTimeframe(timeframe),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: currentGuest() == null || loadingMetrics
                ? null
                : loadMetrics,
            icon: loadingMetrics
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.show_chart_rounded),
            label: Text(
              metricSeries == null ? 'Load history' : 'Refresh history',
            ),
          ),
        ),
        if (metricError != null) ...[
          const SizedBox(height: 10),
          Text(
            metricError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (metricSeries != null) ...[
          const SizedBox(height: 10),
          Text(
            '${metricSeries!.points.length} usable samples'
            '${metricSeries!.malformedRecords > 0 ? ' • ${metricSeries!.malformedRecords} malformed ignored' : ''}'
            '${metricSeries!.truncated ? ' • response truncated locally' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SparklineCard(
            title: 'CPU average',
            icon: Icons.memory_rounded,
            values: cpuHistory,
            timestamps: cpuPoints.map((point) => point.timestamp).toList(),
            summary: fractionRangeSummary(cpuHistory),
            axisLabel: 'CPU usage (%)',
            timeframeLabel: metricTimeframe.label,
          ),
          const SizedBox(height: 8),
          SparklineCard(
            title: 'Memory average',
            icon: Icons.storage_rounded,
            values: memoryHistory,
            timestamps: memoryPoints.map((point) => point.timestamp).toList(),
            summary: fractionRangeSummary(memoryHistory),
            axisLabel: 'Memory usage (%)',
            timeframeLabel: metricTimeframe.label,
          ),
        ],
      ],
    );
  }

  Widget _configurationSection(
    String title,
    IconData icon,
    List<GuestConfigurationField> fields,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(field.value),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _permissionTile({
    required GuestPermissionSnapshot snapshot,
    required String privilege,
    required String label,
    required IconData icon,
  }) {
    final granted = snapshot.has(privilege);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        key: ValueKey('guest-permission-$privilege'),
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(privilege),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              granted ? Icons.check_circle_outline : Icons.block_outlined,
              size: 18,
              color: granted ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(granted ? 'Granted' : 'Not granted'),
          ],
        ),
      ),
    );
  }

  Widget _accessTab(Guest? guest) {
    final visible = guest == null ? null : permissionSnapshot;
    final scheme = Theme.of(context).colorScheme;
    const knownPrivileges = <String>{
      'VM.Audit',
      'VM.PowerMgmt',
      'VM.Backup',
      'VM.Snapshot',
      'VM.Snapshot.Rollback',
      'VM.Clone',
      'VM.Migrate',
      'VM.Config.CPU',
      'VM.Config.Memory',
      'VM.Config.Disk',
      'VM.Config.Network',
      'VM.Config.Options',
    };
    final otherCount = visible == null
        ? 0
        : visible.privileges
              .where((item) => !knownPrivileges.contains(item))
              .length;

    return _tabList(
      key: const Key('guest-access-list'),
      children: [
        Text('Effective access', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          guest == null
              ? 'Permission hints are unavailable because this guest is no longer in the live inventory.'
              : 'Loaded on demand from Proxmox for the exact /vms/${guest.vmid} ACL path. '
                    'These are capability hints only: Proxmox authorization and '
                    'VirtHelm live mutation preflight remain authoritative.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('guest-load-permissions'),
            onPressed: guest == null || loadingPermissions
                ? null
                : loadPermissions,
            icon: loadingPermissions
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.admin_panel_settings_outlined),
            label: Text(
              visible == null
                  ? 'Load permission hints'
                  : 'Refresh permission hints',
            ),
          ),
        ),
        if (guest != null && permissionError != null) ...[
          const SizedBox(height: 10),
          Text(permissionError!, style: TextStyle(color: scheme.error)),
        ],
        if (visible != null) ...[
          const SizedBox(height: 10),
          Text(
            '${visible.privileges.length} effective privileges reported'
            '${visible.malformedPrivileges > 0 ? ' • ${visible.malformedPrivileges} malformed ignored' : ''}'
            '${visible.truncated ? ' • privilege list truncated locally' : ''}'
            '${otherCount > 0 ? ' • $otherCount other privileges not shown' : ''}'
            '${permissionsLoadedAt != null ? ' • loaded ${formatAge(permissionsLoadedAt!)}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Current operator capabilities',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Audit',
            label: 'Inspect guest',
            icon: Icons.visibility_outlined,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.PowerMgmt',
            label: 'Power controls',
            icon: Icons.power_settings_new_rounded,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Backup',
            label: 'Back up / restore',
            icon: Icons.backup_outlined,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Snapshot',
            label: 'Create / delete snapshots',
            icon: Icons.camera_outlined,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Snapshot.Rollback',
            label: 'Rollback snapshots',
            icon: Icons.restore_rounded,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Clone',
            label: 'Clone guest',
            icon: Icons.copy_all_outlined,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Migrate',
            label: 'Migrate guest',
            icon: Icons.drive_file_move_outline,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Allocate',
            label: 'Delete guest / allocate VMID',
            icon: Icons.delete_forever_outlined,
          ),
          const SizedBox(height: 8),
          Text(
            'Configuration privileges',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Config.CPU',
            label: 'Configure CPU',
            icon: Icons.memory_rounded,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Config.Memory',
            label: 'Configure memory',
            icon: Icons.developer_board_outlined,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Config.Disk',
            label: 'Configure disks',
            icon: Icons.storage_rounded,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Config.Network',
            label: 'Configure network',
            icon: Icons.hub_outlined,
          ),
          _permissionTile(
            snapshot: visible,
            privilege: 'VM.Config.Options',
            label: 'Configure other options',
            icon: Icons.tune_rounded,
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'A granted privilege does not enable an unimplemented M4 operation, '
          'prove that every required companion privilege is present, or replace '
          'server-side ACL checks.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _configurationTab(Guest? guest) {
    final visibleConfiguration = guest == null ? null : configuration;
    final scheme = Theme.of(context).colorScheme;
    final sections = <Widget>[];
    if (visibleConfiguration != null) {
      if (visibleConfiguration.compute.isNotEmpty) {
        sections.add(
          _configurationSection(
            'Compute',
            Icons.memory_rounded,
            visibleConfiguration.compute,
          ),
        );
      }
      if (visibleConfiguration.platform.isNotEmpty) {
        sections.add(
          _configurationSection(
            'Platform & boot',
            Icons.settings_suggest_outlined,
            visibleConfiguration.platform,
          ),
        );
      }
      if (visibleConfiguration.storage.isNotEmpty) {
        sections.add(
          _configurationSection(
            'Storage',
            Icons.storage_rounded,
            visibleConfiguration.storage,
          ),
        );
      }
      if (visibleConfiguration.network.isNotEmpty) {
        sections.add(
          _configurationSection(
            'Network',
            Icons.hub_outlined,
            visibleConfiguration.network,
          ),
        );
      }
    }

    return _tabList(
      key: const Key('guest-configuration-list'),
      children: [
        Text(
          'Guest configuration',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Loaded only when requested and never persisted. VirtHelm displays '
          'only reviewed allowlisted fields; passwords, SSH keys, arbitrary '
          'arguments, hooks, descriptions, and unknown keys are not rendered.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('guest-load-configuration'),
            onPressed: guest == null || loadingConfiguration
                ? null
                : loadConfiguration,
            icon: loadingConfiguration
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.tune_rounded),
            label: Text(
              visibleConfiguration == null
                  ? 'Load configuration'
                  : 'Refresh configuration',
            ),
          ),
        ),
        if (guest != null && configurationError != null) ...[
          const SizedBox(height: 10),
          Text(configurationError!, style: TextStyle(color: scheme.error)),
        ],
        if (visibleConfiguration != null) ...[
          const SizedBox(height: 10),
          Text(
            '${visibleConfiguration.visibleFieldCount} reviewed fields'
            '${visibleConfiguration.withheldFields > 0 ? ' • ${visibleConfiguration.withheldFields} withheld/unsupported' : ''}'
            '${visibleConfiguration.malformedFields > 0 ? ' • ${visibleConfiguration.malformedFields} malformed ignored' : ''}'
            '${visibleConfiguration.truncated ? ' • device lists truncated locally' : ''}'
            '${configurationLoadedAt != null ? ' • loaded ${formatAge(configurationLoadedAt!)}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (visibleConfiguration.visibleFieldCount == 0) ...[
            const SizedBox(height: 8),
            const Card(
              child: ListTile(
                leading: Icon(Icons.visibility_off_outlined),
                title: Text('No reviewed fields available'),
                subtitle: Text(
                  'The server response contained no configuration fields '
                  'currently approved for display.',
                ),
              ),
            ),
          ],
          for (final section in sections) ...[
            const SizedBox(height: 8),
            section,
          ],
        ],
        const SizedBox(height: 14),
        Text(
          'Configuration editing remains disabled. Guarded same-cluster migration is available from the action bar. Empty QEMU VM '
          'creation and template cloning are available only through their '
          'separately guarded provisioning workflows; storage/network/media '
          'configuration and LXC creation remain gated.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _ioTab(Guest? guest) => _tabList(
    key: const Key('guest-io-list'),
    children: [
      Text('Guest I/O counters', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      Text(
        'Cumulative bytes reported since the guest started, '
        'not live transfer rates. Counters may reset or be unavailable.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          title: const Text('Network traffic'),
          subtitle: Text(
            'Received: ${formatBytes(guest?.netIn)}\n'
            'Sent: ${formatBytes(guest?.netOut)}',
          ),
          leading: const Icon(Icons.swap_vert_rounded),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          title: const Text('Disk I/O'),
          subtitle: Text(
            'Read: ${formatBytes(guest?.diskRead)}\n'
            'Written: ${formatBytes(guest?.diskWrite)}',
          ),
          leading: const Icon(Icons.storage_rounded),
        ),
      ),
    ],
  );

  Widget _recoveryTab(Guest? guest) {
    final visibleSnapshots = guest == null ? null : snapshotInventory;
    final snapshots = visibleSnapshots?.snapshots ?? const <GuestSnapshot>[];
    final recoveryPoints = snapshots.where((item) => !item.isCurrent).length;
    final backupTasks = _backupTasks(guest);
    final backupStorages = _backupStorageIds(guest);
    final effectiveBackupArchiveStorage =
        selectedBackupArchiveStorage != null &&
            backupStorages.contains(selectedBackupArchiveStorage)
        ? selectedBackupArchiveStorage
        : backupStorages.length == 1
        ? backupStorages.single
        : null;
    final visibleBackupArchives =
        guest != null &&
            backupArchiveInventory?.storage == effectiveBackupArchiveStorage
        ? backupArchiveInventory
        : null;
    final backupArchives =
        visibleBackupArchives?.archives ?? const <GuestBackupArchive>[];
    final backupValidation = GuestBackupValidationAssessment.evaluate(
      archives: visibleBackupArchives,
      backupTasks: backupTasks,
    );
    final scheme = Theme.of(context).colorScheme;
    final snapshotCreateAllowed =
        guest != null &&
        !guest.isTemplate &&
        (guest.isRunning || guest.isStopped) &&
        widget.controller.isInventoryWriteSafe &&
        !widget.controller.refreshing &&
        !widget.controller.isGuestActionBlocked(guest) &&
        !loadingSnapshots &&
        !submitting;
    final backupAllowed =
        guest != null &&
        !guest.isTemplate &&
        (guest.isRunning || guest.isStopped) &&
        backupStorages.isNotEmpty &&
        widget.controller.isInventoryWriteSafe &&
        !widget.controller.refreshing &&
        !widget.controller.isGuestActionBlocked(guest) &&
        !submitting;
    return _tabList(
      key: const Key('guest-recovery-list'),
      children: [
        Text(
          'Recovery visibility',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Snapshots are not backups. Snapshot inventory and exact-guest backup '
          'archive visibility are loaded only when requested. Guarded create-only '
          'snapshots and one-off vzdump backup submission are available; snapshot '
          'rollback/delete, archive integrity verification, and restore remain unavailable.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const Key('guest-load-snapshots'),
                onPressed: guest == null || loadingSnapshots
                    ? null
                    : loadSnapshots,
                icon: loadingSnapshots
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restore_rounded),
                label: Text(
                  snapshotInventory == null
                      ? 'Load snapshots'
                      : 'Refresh snapshots',
                ),
              ),
              FilledButton.icon(
                key: const Key('guest-create-snapshot'),
                onPressed: snapshotCreateAllowed
                    ? () => _openSnapshotCreate(guest)
                    : null,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Create snapshot'),
              ),
              FilledButton.icon(
                key: const Key('guest-start-backup'),
                onPressed: backupAllowed ? () => _openBackup(guest) : null,
                icon: const Icon(Icons.backup_outlined),
                label: const Text('Start backup'),
              ),
            ],
          ),
        ),
        if (guest != null && snapshotError != null) ...[
          const SizedBox(height: 10),
          Text(snapshotError!, style: TextStyle(color: scheme.error)),
        ],
        if (visibleSnapshots != null) ...[
          const SizedBox(height: 10),
          Text(
            '$recoveryPoints snapshot${recoveryPoints == 1 ? '' : 's'}'
            '${visibleSnapshots.malformedRecords > 0 ? ' • ${visibleSnapshots.malformedRecords} malformed ignored' : ''}'
            '${visibleSnapshots.truncated ? ' • response truncated locally' : ''}'
            '${snapshotsLoadedAt != null ? ' • loaded ${formatAge(snapshotsLoadedAt!)}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (snapshots.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.restore_page_outlined),
                title: Text('No snapshots reported'),
                subtitle: Text(
                  'Proxmox did not return any snapshot entries for this guest.',
                ),
              ),
            ),
          for (final snapshot in snapshots)
            Card(
              child: ListTile(
                leading: Icon(
                  snapshot.isCurrent
                      ? Icons.radio_button_checked_rounded
                      : Icons.restore_page_rounded,
                ),
                title: Text(
                  snapshot.isCurrent ? 'Current state' : snapshot.name,
                ),
                subtitle: Text(_snapshotSubtitle(snapshot)),
              ),
            ),
        ],
        const SizedBox(height: 22),
        Text('Backup archives', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Read-only storage content for this exact VMID and QEMU/LXC type. '
          'A visible archive is stronger evidence than task history alone, but '
          'VirtHelm does not inspect archive contents, verify integrity, or test restore.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        if (backupStorages.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.inventory_2_outlined),
              title: Text('No backup storage available'),
              subtitle: Text(
                'No enabled, active storage advertising backup content is visible '
                'on this guest node.',
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: DropdownButton<String>(
                  key: const Key('guest-backup-archive-storage'),
                  value: effectiveBackupArchiveStorage,
                  hint: const Text('Choose backup storage'),
                  isExpanded: true,
                  items: [
                    for (final storage in backupStorages)
                      DropdownMenuItem(value: storage, child: Text(storage)),
                  ],
                  onChanged: loadingBackupArchives
                      ? null
                      : (value) {
                          setState(() {
                            selectedBackupArchiveStorage = value;
                            backupArchiveInventory = null;
                            backupArchivesLoadedAt = null;
                            backupArchiveError = null;
                          });
                        },
                ),
              ),
              FilledButton.tonalIcon(
                key: const Key('guest-load-backup-archives'),
                onPressed:
                    guest == null ||
                        effectiveBackupArchiveStorage == null ||
                        loadingBackupArchives
                    ? null
                    : loadBackupArchives,
                icon: loadingBackupArchives
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.inventory_2_outlined),
                label: Text(
                  visibleBackupArchives == null
                      ? 'Load archives'
                      : 'Refresh archives',
                ),
              ),
            ],
          ),
        if (guest != null && backupArchiveError != null) ...[
          const SizedBox(height: 10),
          Text(backupArchiveError!, style: TextStyle(color: scheme.error)),
        ],
        if (visibleBackupArchives != null) ...[
          const SizedBox(height: 10),
          Text(
            '${backupArchives.length} archive${backupArchives.length == 1 ? '' : 's'}'
            ' on ${visibleBackupArchives.storage}'
            '${visibleBackupArchives.ignoredRecords > 0 ? ' • ${visibleBackupArchives.ignoredRecords} unusable row(s) ignored' : ''}'
            '${visibleBackupArchives.truncated ? ' • response truncated locally' : ''}'
            '${backupArchivesLoadedAt != null ? ' • loaded ${formatAge(backupArchivesLoadedAt!)}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (backupArchives.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.inventory_2_outlined),
                title: Text('No backup archive reported'),
                subtitle: Text(
                  'PVE did not report backup content matching this guest on the selected storage.',
                ),
              ),
            ),
          for (var index = 0; index < backupArchives.length; index++)
            Card(
              child: ListTile(
                leading: Icon(
                  index == 0
                      ? Icons.inventory_2_rounded
                      : Icons.inventory_2_outlined,
                ),
                title: Text(
                  index == 0
                      ? 'Latest • ${backupArchives[index].displayName}'
                      : backupArchives[index].displayName,
                ),
                subtitle: Text(_backupArchiveSubtitle(backupArchives[index])),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Archive visibility is not a checksum, PBS verification result, '
            'restore test, or recoverability guarantee.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 22),
        Card(
          key: const Key('guest-backup-validation-confidence'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.fact_check_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Backup validation confidence',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            backupValidation.headline,
                            key: const Key('guest-backup-validation-headline'),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  backupValidation.confidence ==
                          BackupValidationConfidence.partial
                      ? 'VirtHelm has partial operational evidence because a matching archive is visible. '
                            'Confidence cannot become verified from PVE archive visibility or task history alone.'
                      : backupValidation.confidence ==
                            BackupValidationConfidence.insufficient
                      ? 'The selected storage was checked, but no matching archive is visible. '
                            'Recent task success cannot upgrade this result.'
                      : 'Archive visibility has not been loaded for the selected storage, so backup validation is not assessed.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Archive visibility and identity'),
                  subtitle: Text(_backupValidationArchiveText(backupValidation)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.task_alt_outlined),
                  title: const Text('Recent backup task evidence'),
                  subtitle: Text(_backupValidationTaskText(backupValidation)),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.verified_outlined),
                  title: Text('Integrity verification'),
                  subtitle: Text(
                    'Unavailable in this PVE-only workflow. No PBS verification result or checksum validation is consumed.',
                  ),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.settings_backup_restore_outlined),
                  title: Text('Restore test'),
                  subtitle: Text(
                    'Unavailable. VirtHelm has not performed or recorded a tested restore for this archive.',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This card is evidence classification only. It is not a recoverability guarantee and never authorizes restore.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Recent backup tasks',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Recent Proxmox vzdump task outcomes for this VMID only. A successful '
          'task does not by itself prove a matching archive is still visible, '
          'verified, or restorable; load archive visibility separately.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (widget.controller.serverTaskMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            'Recent task history is incomplete: '
            '${widget.controller.serverTaskMessage}',
            style: TextStyle(color: scheme.error),
          ),
        ],
        const SizedBox(height: 8),
        if (backupTasks.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.backup_outlined),
              title: Text('No recent backup task visible'),
              subtitle: Text(
                'The current recent-task window does not contain a vzdump task '
                'for this guest.',
              ),
            ),
          ),
        for (final task in backupTasks)
          Card(
            child: ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: Text('Backup task • ${task.stateLabel}'),
              subtitle: Text(_backupTaskSubtitle(task)),
            ),
          ),
      ],
    );
  }

  Widget _actionBar(
    Guest? guest,
    bool allowed,
    String? guardReason,
    ColorScheme scheme,
  ) {
    final primary = _primaryAction(guest);
    final canSubmit = allowed && guest != null && primary.allowedFor(guest);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color:
              Theme.of(context).cardTheme.color ??
              Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (guardReason != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      guardReason,
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('guest-primary-action'),
                    onPressed: canSubmit ? () => execute(guest, primary) : null,
                    icon: submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_actionIcon(primary)),
                    label: Text(submitting ? 'Submitting…' : primary.label),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('guest-migrate'),
                  tooltip: guest == null || _migrationTargets(guest).isEmpty
                      ? 'No online migration target'
                      : 'Migrate guest',
                  onPressed:
                      allowed &&
                          guest != null &&
                          _migrationTargets(guest).isNotEmpty
                      ? () => _openMigration(guest)
                      : null,
                  icon: const Icon(Icons.swap_horiz_rounded),
                ),
                IconButton(
                  key: const Key('guest-delete'),
                  tooltip: guest == null
                      ? 'Guest unavailable'
                      : guest.isTemplate
                      ? 'Template deletion unavailable here'
                      : !guest.isStopped
                      ? 'Stop guest before deletion'
                      : 'Delete guest permanently',
                  onPressed:
                      allowed &&
                          guest != null &&
                          guest.isStopped &&
                          !guest.isTemplate
                      ? () => _openDeletion(guest)
                      : null,
                  icon: Icon(
                    Icons.delete_forever_outlined,
                    color: allowed && guest?.isStopped == true
                        ? scheme.error
                        : null,
                  ),
                ),
                PopupMenuButton<GuestAction>(
                  key: const Key('guest-more-actions'),
                  enabled: allowed && guest != null,
                  tooltip: 'More power actions',
                  onSelected: (action) {
                    if (guest != null) execute(guest, action);
                  },
                  itemBuilder: (context) => [
                    for (final action in GuestAction.values.where(
                      (option) => option != primary,
                    ))
                      PopupMenuItem<GuestAction>(
                        value: action,
                        enabled:
                            allowed &&
                            guest != null &&
                            action.allowedFor(guest),
                        child: Row(
                          children: [
                            Icon(
                              _actionIcon(action),
                              size: 20,
                              color: action == GuestAction.stop
                                  ? scheme.error
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Text(action.label),
                          ],
                        ),
                      ),
                  ],
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _templateCloneBar(
    Guest guest,
    bool allowed,
    String? guardReason,
    ColorScheme scheme,
  ) => SafeArea(
    top: false,
    child: Container(
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (guardReason != null) ...[
            Text(
              guardReason,
              style: TextStyle(
                color: allowed ? scheme.onSurfaceVariant : scheme.error,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton.icon(
            key: const Key('guest-clone-template'),
            onPressed: allowed ? () => _openTemplateClone(guest) : null,
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text('Clone template'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (!_currentSession) {
        return Scaffold(
          appBar: AppBar(title: const Text('Guest unavailable')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Connection changed. Reopen guest details from the active '
                'connection.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }
      final guest = currentGuest();
      final scheme = Theme.of(context).colorScheme;
      final operationBlocked =
          guest != null && widget.controller.isGuestActionBlocked(guest);
      final powerAllowed =
          guest != null &&
          !guest.isTemplate &&
          widget.controller.isInventoryWriteSafe &&
          !widget.controller.refreshing &&
          !submitting &&
          !operationBlocked;
      final cloneAllowed =
          guest != null &&
          guest.isTemplate &&
          widget.controller.isInventoryWriteSafe &&
          !widget.controller.refreshing &&
          !submitting &&
          !operationBlocked;
      final guardReason = _guardReason(guest, operationBlocked);
      return DefaultTabController(
        length: 6,
        child: Scaffold(
          appBar: AppBar(
            title: Text(guest?.name ?? widget.guest.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                onPressed: widget.controller.refresh,
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(key: Key('guest-overview-tab'), text: 'Overview'),
                Tab(key: Key('guest-access-tab'), text: 'Access'),
                Tab(key: Key('guest-configuration-tab'), text: 'Configuration'),
                Tab(key: Key('guest-metrics-tab'), text: 'Metrics'),
                Tab(key: Key('guest-io-tab'), text: 'I/O'),
                Tab(key: Key('guest-recovery-tab'), text: 'Recovery'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _overviewTab(guest, scheme),
              _accessTab(guest),
              _configurationTab(guest),
              _metricsTab(),
              _ioTab(guest),
              _recoveryTab(guest),
            ],
          ),
          bottomNavigationBar: guest?.isTemplate == true
              ? _templateCloneBar(guest!, cloneAllowed, guardReason, scheme)
              : _actionBar(guest, powerAllowed, guardReason, scheme),
        ),
      );
    },
  );
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(50),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.45),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
