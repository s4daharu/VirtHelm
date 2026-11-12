import 'dart:async';

import 'package:flutter/foundation.dart';

import 'alert_rules.dart';
import 'app_preferences.dart';
import 'background_checks.dart';
import 'device_connectivity.dart';
import 'foreground_notifications.dart';
import 'guest_saved_view.dart';
import 'incident_center.dart';
import 'incident_history.dart';
import 'incident_triage.dart';
import 'models.dart';
import 'offline_overview.dart';
import 'profile_repository.dart';
import 'pve_api.dart';

enum _GuestSnapshotLifecycleAction { delete, rollback }

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    GatewayFactory? gatewayFactory,
    ForegroundIncidentNotifier? incidentNotifier,
    BackgroundCheckScheduler? backgroundCheckScheduler,
    this.taskVerificationTtl = const Duration(minutes: 15),
  }) : _incidentNotifier =
           incidentNotifier ?? const AndroidForegroundIncidentNotifier(),
       _backgroundCheckScheduler =
           backgroundCheckScheduler ?? const AndroidBackgroundCheckScheduler(),
       _factory =
           gatewayFactory ??
           ((profile, credentials) => DioPveGateway(profile, credentials));

  final ProfileRepository repository;
  final GatewayFactory _factory;
  final ForegroundIncidentNotifier _incidentNotifier;
  final BackgroundCheckScheduler _backgroundCheckScheduler;
  final Duration taskVerificationTtl;

  List<ConnectionProfile> profiles = [];
  ConnectionProfile? active;
  Inventory? inventory;
  // Display-only, last-known aggregate counts. Never a mutation snapshot.
  OfflineOverview? cachedOverview;
  bool offlineOverviewEnabled = false;
  final List<TrackedTask> tasks = [];
  List<StoragePool> storages = [];
  List<RecentServerTask> serverTasks = [];
  List<ForegroundThresholdAlertRule> thresholdAlertRules = [];
  final ForegroundThresholdAlertEngine _thresholdAlertEngine =
      ForegroundThresholdAlertEngine();
  List<CockpitIncident> _retainedServerTaskIncidents =
      const <CockpitIncident>[];
  final IncidentTriageLedger _incidentTriage = IncidentTriageLedger();
  List<IncidentHistoryEntry> incidentHistory = const <IncidentHistoryEntry>[];
  ForegroundNotificationPolicy foregroundNotificationPolicy =
      const ForegroundNotificationPolicy();
  DateTime? _lastForegroundNotificationAt;
  bool _notificationDeliveryInFlight = false;

  List<CockpitIncident> get incidents => buildCockpitIncidents(
    inventory: inventory,
    serverTasks: serverTasks,
    sessionTasks: tasks,
    retainedTaskIncidents: _retainedServerTaskIncidents,
    foregroundRuleIncidents: _thresholdAlertEngine.incidents,
  );

  List<IncidentTriageRecord> get currentIncidentTriage {
    final observed = incidents;
    _incidentTriage.observe(observed);
    final visibleKeys = observed.map((incident) => incident.key).toSet();
    return List<IncidentTriageRecord>.unmodifiable(
      _incidentTriage.current.where(
        (record) => visibleKeys.contains(record.incident.key),
      ),
    );
  }

  List<IncidentTriageRecord> get earlierIncidentTriage =>
      _incidentTriage.earlier;

  /// Acknowledgement is a session-local annotation, never remediation.
  bool setIncidentAcknowledged(
    String key,
    bool acknowledged, {
    required String expectedProfileId,
    required int expectedGeneration,
  }) {
    if (_disposed ||
        active?.id != expectedProfileId ||
        expectedGeneration != _generation ||
        !incidents.any((incident) => incident.key == key)) {
      return false;
    }
    _incidentTriage.observe(incidents);
    final changed = _incidentTriage.setAcknowledged(key, acknowledged);
    if (changed) {
      _captureIncidentHistory(complete: false);
      _notify();
    }
    return changed;
  }

  /// The rendering profile/generation and current incident keys are checked
  /// again after any UI confirmation; no server health is changed.
  int acknowledgeIncidents(
    Iterable<String> keys, {
    required String expectedProfileId,
    required int expectedGeneration,
  }) {
    if (_disposed ||
        active?.id != expectedProfileId ||
        expectedGeneration != _generation) {
      return 0;
    }
    final observed = incidents;
    _incidentTriage.observe(observed);
    final visible = observed.map((incident) => incident.key).toSet();
    final changed = _incidentTriage.acknowledgeCurrentKeys(
      keys.toSet().where(visible.contains),
    );
    if (changed > 0) {
      _captureIncidentHistory(complete: false);
      _notify();
    }
    return changed;
  }

  List<IncidentHistoryEntry> _captureIncidentHistory({required bool complete}) {
    final profile = active;
    if (_disposed || profile == null) return const <IncidentHistoryEntry>[];
    final previousIds = incidentHistory
        .map((entry) => entry.occurrenceId)
        .toSet();
    incidentHistory = reconcileIncidentHistory(
      incidentHistory,
      <IncidentTriageRecord>[
        ..._incidentTriage.current,
        ..._incidentTriage.earlier,
      ],
      complete: complete,
    );
    unawaited(_persistIncidentHistory(profile.id, incidentHistory));
    return List<IncidentHistoryEntry>.unmodifiable(
      incidentHistory.where(
        (entry) => entry.isOpen && !previousIds.contains(entry.occurrenceId),
      ),
    );
  }

  Future<void> _maybeDeliverForegroundIncidentNotification(
    List<IncidentHistoryEntry> newOccurrences, {
    required String profileId,
    required int generation,
  }) async {
    if (_disposed ||
        !_foreground ||
        newOccurrences.isEmpty ||
        active?.id != profileId ||
        generation != _generation ||
        _notificationDeliveryInFlight) {
      return;
    }
    final policy = foregroundNotificationPolicy;
    final now = DateTime.now();
    if (!policy.canDeliverAt(
      now,
      lastDeliveredAt: _lastForegroundNotificationAt,
    )) {
      return;
    }

    _notificationDeliveryInFlight = true;
    try {
      final shown = await _incidentNotifier.showIncidentSummary(
        critical: newOccurrences.any(
          (entry) => entry.severity == CockpitIncidentSeverity.critical,
        ),
      );
      if (!shown) return;
      final deliveredAt = now.toUtc();
      try {
        await repository.saveLastForegroundNotificationAt(
          profileId,
          deliveredAt,
        );
      } catch (_) {
        // Notification state is best-effort local metadata only.
      }
      if (!_disposed && active?.id == profileId && generation == _generation) {
        _lastForegroundNotificationAt = deliveredAt;
      }
    } catch (_) {
      // Delivery failure cannot change health, history or authorization.
    } finally {
      _notificationDeliveryInFlight = false;
    }
  }

  Future<void> _persistIncidentHistory(
    String profileId,
    List<IncidentHistoryEntry> entries,
  ) async {
    try {
      await repository.saveIncidentHistory(profileId, entries);
    } catch (_) {
      // History is operator context only. A local persistence failure must not
      // alter current health, task outcomes, authorization or write safety.
    }
  }

  Set<String> favoriteGuests = <String>{};
  List<SavedGuestView> guestSavedViews = [];
  String? storageMessage;
  String? serverTaskMessage;
  String? inventoryWarning;
  String? message;
  bool initialized = false;
  bool refreshing = false;
  bool connecting = false;
  AppThemePreference themePreference = AppThemePreference.system;
  AutoRefreshPreference autoRefreshPreference = AutoRefreshPreference.off;
  bool showNodeMetrics = true;
  bool highContrast = false;
  bool reduceMotion = false;
  DeviceNetworkState deviceNetworkState = DeviceNetworkState.unknown;

  PveGateway? _gateway;
  int _generation = 0;
  int _networkEpoch = 0;
  int _inventoryRevision = 0;
  Timer? _pollTimer;
  Timer? _autoRefreshTimer;
  int? _pollingGeneration;
  bool _foreground = true;
  bool _disposed = false;
  bool _requiresRecovery = false;
  Future<void>? _refreshFuture;

  // A guest is single-flight across preflight, submission and UPID completion.
  // Unknown outcomes remain blocked for this connection session.
  final Set<String> _pendingGuestOperations = {};
  final Set<String> _uncertainGuestOperations = {};
  final Map<String, Set<String>> _taskTargets = {};
  final Set<String> _deletingProfiles = {};

  /// Identifies the active connection session, even across reconnects.
  int get connectionGeneration => _generation;

  Future<TaskInspection?> inspectTask({
    required String profileId,
    required int generation,
    required String node,
    required String upid,
    int logStart = 0,
  }) async {
    final gateway = _gateway;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;
    if (!current() ||
        gateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable ||
        !tasks.any((task) => task.node == node && task.upid == upid) &&
            !serverTasks.any(
              (task) => task.node == node && task.upid == upid,
            )) {
      return null;
    }

    // Task reads are strictly on demand. Never retain task-log data in app
    // state or issue any mutation as part of viewing task details.
    ServerTaskStatus? status;
    TaskLogResult? log;
    String? statusError;
    String? logError;
    var authLost = false;
    try {
      status = await gateway.taskStatus(
        TrackedTask(
          node: node,
          upid: upid,
          title: 'Task inspection',
          startedAt: DateTime.fromMillisecondsSinceEpoch(0),
          outcome: OperationOutcome.unknown,
        ),
      );
    } on PveFailure catch (error) {
      statusError = error.message;
      authLost = error.status == 401;
      if (authLost && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
    } catch (_) {
      statusError = 'Could not read task status.';
    }
    if (!current()) return null;
    if (!authLost) {
      try {
        log = await gateway.taskLog(node, upid, start: logStart);
      } on PveFailure catch (error) {
        logError = error.message;
        if (error.status == 401 && current()) {
          await _recordAuthenticatedReadLoss(generation, error.message);
        }
      } catch (_) {
        logError = 'Could not read task log.';
      }
    } else {
      logError = 'Authentication required before task logs can be read.';
    }
    if (!current()) return null;
    return TaskInspection(
      status: status,
      log: log,
      statusError: statusError,
      logError: logError,
    );
  }

  Future<GuestSnapshotInventory?> inspectGuestSnapshots({
    required String profileId,
    required int generation,
    required Guest guest,
  }) async {
    final gateway = _gateway;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;
    Guest? currentGuest() {
      final matches = inventory?.guests.where(
        (item) =>
            item.node == guest.node &&
            item.kind == guest.kind &&
            item.vmid == guest.vmid,
      );
      if (matches == null || matches.length != 1) return null;
      return matches.single;
    }

    if (!current() ||
        gateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      return null;
    }
    final target = currentGuest();
    if (target == null) return null;

    try {
      final result = await gateway.guestSnapshots(target);
      if (!current() || currentGuest() == null) return null;
      return result;
    } on PveFailure catch (error) {
      if (error.status == 401 && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
      rethrow;
    }
  }

  Future<GuestBackupArchiveInventory?> inspectGuestBackupArchives({
    required String profileId,
    required int generation,
    required Guest guest,
    required String storage,
  }) async {
    final gateway = _gateway;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;
    Guest? currentGuest() {
      final matches = inventory?.guests.where(
        (item) =>
            item.node == guest.node &&
            item.kind == guest.kind &&
            item.vmid == guest.vmid,
      );
      if (matches == null || matches.length != 1) return null;
      return matches.single;
    }

    StoragePool? currentStorage() {
      final matches = storages.where(
        (item) =>
            item.node == guest.node &&
            item.id == storage &&
            item.enabled == true &&
            item.active == true &&
            item.contentTypes.contains('backup'),
      );
      if (matches.length != 1) return null;
      return matches.single;
    }

    if (!current() ||
        gateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      return null;
    }
    final target = currentGuest();
    final targetStorage = currentStorage();
    if (target == null || targetStorage == null) return null;

    try {
      final result = await gateway.guestBackupArchives(
        target,
        targetStorage.id,
      );
      if (!current() || currentGuest() == null || currentStorage() == null) {
        return null;
      }
      return result;
    } on PveFailure catch (error) {
      if (error.status == 401 && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
      rethrow;
    }
  }

  Future<GuestRestorePlanPreflight?> inspectGuestRestorePlan({
    required String profileId,
    required int generation,
    required Guest guest,
    required GuestBackupArchive archive,
    required GuestRestorePlanRequest request,
  }) async {
    final gateway = _gateway;
    final networkEpoch = _networkEpoch;
    final GuestBackupGateway? backupGateway = gateway is GuestBackupGateway
        ? gateway as GuestBackupGateway
        : null;
    final GuestCreateGateway? createGateway = gateway is GuestCreateGateway
        ? gateway as GuestCreateGateway
        : null;

    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;

    Guest? currentGuest() {
      final matches = inventory?.guests.where(
        (item) =>
            item.node == guest.node &&
            item.kind == guest.kind &&
            item.vmid == guest.vmid,
      );
      if (matches == null || matches.length != 1) return null;
      return matches.single;
    }

    if (!current() ||
        gateway == null ||
        backupGateway == null ||
        createGateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      return null;
    }

    final source = currentGuest();
    if (source == null) return null;
    if (archive.node != source.node ||
        archive.kind != source.kind ||
        archive.vmid != source.vmid) {
      throw const PveFailure(
        'Selected backup archive no longer matches this guest.',
      );
    }
    final cachedSourceStorage = storages.where(
      (item) =>
          item.node == source.node &&
          item.id == archive.storage &&
          item.enabled == true &&
          item.active == true &&
          item.contentTypes.contains('backup'),
    );
    if (cachedSourceStorage.length != 1) {
      return null;
    }

    final normalized = request.normalized();
    final validationError = normalized.validationError;
    if (validationError != null) throw PveFailure(validationError);
    if (normalized.targetNode != source.node) {
      throw const PveFailure(
        'Cross-node restore planning remains gated in this milestone.',
      );
    }

    final inventorySnapshot = inventory;
    bool stillCurrent() =>
        current() &&
        _foreground &&
        networkEpoch == _networkEpoch &&
        deviceNetworkState != DeviceNetworkState.unavailable &&
        identical(inventorySnapshot, inventory) &&
        currentGuest() != null;

    Future<T> authenticatedRead<T>(Future<T> Function() read) async {
      try {
        return await read();
      } on PveFailure catch (error) {
        if (error.status == 401 && current()) {
          await _recordAuthenticatedReadLoss(generation, error.message);
        }
        rethrow;
      }
    }

    final live = await authenticatedRead(gateway.inventory);
    if (!stillCurrent()) return null;
    if (live.malformedGuestRecords != 0) {
      throw const PveFailure(
        'Live inventory verification is incomplete. Restore planning was stopped.',
      );
    }

    final liveSources = live.guests
        .where(
          (item) =>
              item.node == source.node &&
              item.kind == source.kind &&
              item.vmid == source.vmid,
        )
        .toList(growable: false);
    if (liveSources.length != 1) {
      throw const PveFailure(
        'The source guest moved or disappeared during restore planning.',
      );
    }
    final liveSource = liveSources.single;

    final freshArchives = await authenticatedRead(
      () => gateway.guestBackupArchives(liveSource, archive.storage),
    );
    if (!stillCurrent()) return null;
    final matchingArchives = freshArchives.archives.where(
      (item) =>
          item.node == source.node &&
          item.storage == archive.storage &&
          item.volid == archive.volid &&
          item.kind == archive.kind &&
          item.vmid == archive.vmid,
    );
    final sourceArchiveVisible = matchingArchives.length == 1;

    final storageRead = await authenticatedRead(
      () => gateway.storageOverview([normalized.targetNode]),
    );
    if (!stillCurrent()) return null;

    final targetNodes = live.nodes.where(
      (item) => item.name == normalized.targetNode,
    );
    final targetNodeOnline =
        targetNodes.length == 1 && targetNodes.single.status == 'online';
    var targetVmidAvailable = !live.guests.any(
      (item) => item.vmid == normalized.targetVmid,
    );
    String? vmidVerificationError;
    if (targetVmidAvailable) {
      // Cluster resources are ACL-filtered. Absence there cannot prove that a
      // VMID is free; nextid checks the server's cluster-wide namespace.
      try {
        await authenticatedRead(
          () => createGateway.assertVmidAvailable(normalized.targetVmid),
        );
      } on PveFailure catch (error) {
        if (error.status == 401) rethrow;
        targetVmidAvailable = false;
        vmidVerificationError =
            'Target VMID availability could not be confirmed by the server. '
            'Overwrite restore remains gated.';
      }
      if (!stillCurrent()) return null;
    }
    if (isProvisioningTargetBlocked(
      source.kind,
      normalized.targetNode,
      normalized.targetVmid,
    )) {
      targetVmidAvailable = false;
      vmidVerificationError =
          'Target VMID has a pending or uncertain operation in this session.';
    }
    final sourceStorageMatches = storageRead.values.where(
      (item) =>
          item.node == source.node &&
          item.id == archive.storage &&
          item.enabled == true &&
          item.active == true &&
          item.contentTypes.contains('backup'),
    );
    final sourceStorageUsable =
        storageRead.complete && sourceStorageMatches.length == 1;

    final requiredTargetContent = source.kind == 'qemu' ? 'images' : 'rootdir';
    final targetStorageMatches = storageRead.values.where(
      (item) =>
          item.node == normalized.targetNode &&
          item.id == normalized.targetStorage,
    );
    final targetStorage = targetStorageMatches.length == 1
        ? targetStorageMatches.single
        : null;
    final targetStorageUsable =
        storageRead.complete &&
        targetStorage != null &&
        targetStorage.enabled == true &&
        targetStorage.active == true &&
        targetStorage.contentTypes.contains(requiredTargetContent);

    final vmPermissions = await authenticatedRead(
      () => createGateway.permissionsForVmid(normalized.targetVmid),
    );
    if (!stillCurrent()) return null;
    final storagePermissions = await authenticatedRead(
      () => backupGateway.permissionsForPath(
        '/storage/${normalized.targetStorage}',
      ),
    );
    if (!stillCurrent()) return null;

    final vmAllocateAvailable = vmPermissions.has('VM.Allocate');
    final datastoreAllocateSpaceAvailable = storagePermissions.has(
      'Datastore.AllocateSpace',
    );

    final blockers = <String>[];
    if (!sourceArchiveVisible) {
      blockers.add(
        freshArchives.truncated
            ? 'The selected archive could not be confirmed in the truncated fresh archive response.'
            : 'The selected archive is no longer visible on the source backup storage.',
      );
    }
    if (!storageRead.complete) {
      blockers.add(
        'Storage inventory is incomplete; source and target storage state cannot be trusted.',
      );
    }
    if (!sourceStorageUsable) {
      blockers.add(
        'The source backup storage is no longer uniquely active and backup-capable.',
      );
    }
    if (!targetNodeOnline) {
      blockers.add('The target node is not currently online.');
    }
    if (!targetVmidAvailable) {
      blockers.add(
        vmidVerificationError ??
            'Target VMID ${normalized.targetVmid} is already in use. Overwrite restore remains gated.',
      );
    }
    if (!targetStorageUsable) {
      blockers.add(
        'Target storage "${normalized.targetStorage}" is not uniquely active with $requiredTargetContent content.',
      );
    }
    if (!vmAllocateAvailable) {
      blockers.add(
        'The active token does not report VM.Allocate on target VMID ${normalized.targetVmid}.',
      );
    }
    if (!datastoreAllocateSpaceAvailable) {
      blockers.add(
        'The active token does not report Datastore.AllocateSpace on target storage "${normalized.targetStorage}".',
      );
    }

    return GuestRestorePlanPreflight(
      sourceArchive: sourceArchiveVisible ? matchingArchives.single : archive,
      targetNode: normalized.targetNode,
      targetVmid: normalized.targetVmid,
      targetStorage: normalized.targetStorage,
      status: blockers.isEmpty
          ? GuestRestorePlanStatus.preflightComplete
          : GuestRestorePlanStatus.blocked,
      sourceArchiveVisible: sourceArchiveVisible,
      sourceStorageUsable: sourceStorageUsable,
      targetNodeOnline: targetNodeOnline,
      targetVmidAvailable: targetVmidAvailable,
      targetStorageUsable: targetStorageUsable,
      vmAllocateAvailable: vmAllocateAvailable,
      datastoreAllocateSpaceAvailable: datastoreAllocateSpaceAvailable,
      storageReadComplete: storageRead.complete,
      targetStorageAvailableBytes: targetStorage?.available,
      blockers: List<String>.unmodifiable(blockers),
    );
  }

  Future<GuestConfiguration?> inspectGuestConfiguration({
    required String profileId,
    required int generation,
    required Guest guest,
  }) async {
    final gateway = _gateway;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;
    Guest? currentGuest() {
      final matches = inventory?.guests.where(
        (item) =>
            item.node == guest.node &&
            item.kind == guest.kind &&
            item.vmid == guest.vmid,
      );
      if (matches == null || matches.length != 1) return null;
      return matches.single;
    }

    if (!current() ||
        gateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      return null;
    }
    final target = currentGuest();
    if (target == null) return null;

    try {
      final result = await gateway.guestConfiguration(target);
      if (!current() || currentGuest() == null) return null;
      return result;
    } on PveFailure catch (error) {
      if (error.status == 401 && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
      rethrow;
    }
  }

  Future<GuestPermissionSnapshot?> inspectGuestPermissions({
    required String profileId,
    required int generation,
    required Guest guest,
  }) async {
    final gateway = _gateway;
    final GuestPermissionGateway? permissionGateway =
        gateway is GuestPermissionGateway
        ? gateway as GuestPermissionGateway
        : null;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;
    Guest? currentGuest() {
      final matches = inventory?.guests.where(
        (item) =>
            item.node == guest.node &&
            item.kind == guest.kind &&
            item.vmid == guest.vmid,
      );
      if (matches == null || matches.length != 1) return null;
      return matches.single;
    }

    if (!current() ||
        permissionGateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      return null;
    }
    final target = currentGuest();
    if (target == null) return null;

    try {
      final result = await permissionGateway.guestPermissions(target);
      if (!current() || currentGuest() == null) return null;
      return result;
    } on PveFailure catch (error) {
      if (error.status == 401 && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
      rethrow;
    }
  }

  Future<int?> suggestQemuCreateVmid({
    required String profileId,
    required int generation,
  }) async {
    final gateway = _gateway;
    final GuestCreateGateway? createGateway = gateway is GuestCreateGateway
        ? gateway as GuestCreateGateway
        : null;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;

    if (!current() ||
        createGateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable ||
        !isInventoryWriteSafe) {
      return null;
    }

    try {
      final result = await createGateway.nextFreeVmid();
      if (!current() ||
          !isInventoryWriteSafe ||
          inventory!.guests.any((guest) => guest.vmid == result)) {
        return null;
      }
      return result;
    } on PveFailure catch (error) {
      if (error.status == 401 && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
      rethrow;
    }
  }

  Future<int?> suggestLxcCreateVmid({
    required String profileId,
    required int generation,
  }) async {
    final gateway = _gateway;
    final LxcCreateGateway? createGateway = gateway is LxcCreateGateway
        ? gateway as LxcCreateGateway
        : null;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;

    if (!current() ||
        createGateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable ||
        !isInventoryWriteSafe) {
      return null;
    }

    try {
      final result = await createGateway.nextFreeVmid();
      if (!current() ||
          !isInventoryWriteSafe ||
          inventory!.guests.any((guest) => guest.vmid == result)) {
        return null;
      }
      return result;
    } on PveFailure catch (error) {
      if (error.status == 401 && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
      rethrow;
    }
  }

  Future<LxcCreateOptions?> inspectLxcCreateOptions({
    required String profileId,
    required int generation,
    required String node,
  }) async {
    final gateway = _gateway;
    final LxcCreateGateway? createGateway = gateway is LxcCreateGateway
        ? gateway as LxcCreateGateway
        : null;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;
    bool nodeOnline() {
      final matches = inventory?.nodes.where((item) => item.name == node);
      return matches != null &&
          matches.length == 1 &&
          matches.single.status == 'online';
    }

    if (!current() ||
        createGateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable ||
        !isInventoryWriteSafe ||
        !nodeOnline()) {
      return null;
    }

    try {
      final result = await createGateway.lxcCreateOptions(node);
      if (!current() || !isInventoryWriteSafe || !nodeOnline()) return null;
      return result;
    } on PveFailure catch (error) {
      if (error.status == 401 && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
      rethrow;
    }
  }

  Future<int?> suggestTemplateCloneVmid({
    required String profileId,
    required int generation,
    required Guest source,
  }) async {
    final gateway = _gateway;
    final GuestCloneGateway? cloneGateway = gateway is GuestCloneGateway
        ? gateway as GuestCloneGateway
        : null;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;
    Guest? currentSource() {
      final matches = inventory?.guests.where(
        (item) =>
            item.node == source.node &&
            item.kind == source.kind &&
            item.vmid == source.vmid &&
            item.isTemplate,
      );
      if (matches == null || matches.length != 1) return null;
      return matches.single;
    }

    if (!current() ||
        cloneGateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable ||
        currentSource() == null) {
      return null;
    }

    try {
      final result = await cloneGateway.nextFreeVmid();
      if (!current() || currentSource() == null) return null;
      return result;
    } on PveFailure catch (error) {
      if (error.status == 401 && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
      rethrow;
    }
  }

  Future<GuestMetricSeries?> inspectGuestMetrics({
    required String profileId,
    required int generation,
    required Guest guest,
    required GuestMetricTimeframe timeframe,
  }) async {
    final gateway = _gateway;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;
    Guest? currentGuest() {
      final matches = inventory?.guests.where(
        (item) =>
            item.node == guest.node &&
            item.kind == guest.kind &&
            item.vmid == guest.vmid,
      );
      if (matches == null || matches.length != 1) return null;
      return matches.single;
    }

    if (!current() ||
        gateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      return null;
    }
    final target = currentGuest();
    if (target == null) return null;

    try {
      final result = await gateway.guestMetrics(target, timeframe);
      if (!current() || currentGuest() == null) return null;
      return result;
    } on PveFailure catch (error) {
      if (error.status == 401 && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
      rethrow;
    }
  }

  Future<NodeMetricSeries?> inspectNodeMetrics({
    required String profileId,
    required int generation,
    required Node node,
    required NodeMetricTimeframe timeframe,
  }) async {
    final gateway = _gateway;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;
    Node? currentNode() {
      final matches = inventory?.nodes.where((item) => item.name == node.name);
      if (matches == null || matches.length != 1) return null;
      return matches.single;
    }

    if (!current() ||
        gateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      return null;
    }
    final target = currentNode();
    if (target == null) return null;

    try {
      final result = await gateway.nodeMetrics(target.name, timeframe);
      if (!current() || currentNode() == null) return null;
      return result;
    } on PveFailure catch (error) {
      if (error.status == 401 && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
      rethrow;
    }
  }

  Future<StorageMetricSeries?> inspectStorageMetrics({
    required String profileId,
    required int generation,
    required StoragePool storage,
    required StorageMetricTimeframe timeframe,
  }) async {
    final gateway = _gateway;
    bool current() =>
        !_disposed && generation == _generation && active?.id == profileId;
    StoragePool? currentStorage() {
      final matches = storages.where(
        (item) => item.node == storage.node && item.id == storage.id,
      );
      if (matches.length != 1) return null;
      return matches.single;
    }

    if (!current() ||
        gateway == null ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      return null;
    }
    final target = currentStorage();
    if (target == null) return null;

    try {
      final result = await gateway.storageMetrics(target, timeframe);
      if (!current() || currentStorage() == null) return null;
      return result;
    } on PveFailure catch (error) {
      if (error.status == 401 && current()) {
        await _recordAuthenticatedReadLoss(generation, error.message);
      }
      rethrow;
    }
  }

  String _provisioningKey(String kind, String node, int vmid) =>
      '$kind:$node:$vmid';

  String _guestKey(Guest guest) =>
      _provisioningKey(guest.kind, guest.node, guest.vmid);

  // VMIDs share one cluster-wide namespace across nodes and guest types.
  String _provisioningVmidKey(int vmid) => 'provision:$vmid';

  bool isProvisioningTargetBlocked(String kind, String node, int vmid) {
    final key = _provisioningKey(kind, node, vmid);
    return _pendingGuestOperations.contains(key) ||
        _uncertainGuestOperations.contains(key) ||
        _pendingGuestOperations.contains(_provisioningVmidKey(vmid)) ||
        _uncertainGuestOperations.contains(_provisioningVmidKey(vmid));
  }

  bool isGuestFavorite(Guest guest) =>
      favoriteGuests.contains(_guestKey(guest));

  Future<void> saveThresholdAlertRule(
    ForegroundThresholdAlertRule rule, {
    required String expectedProfileId,
  }) async {
    final profile = active;
    if (profile == null || _disposed || profile.id != expectedProfileId) {
      return;
    }
    await repository.saveThresholdAlertRule(profile.id, rule);
    if (_disposed || active?.id != profile.id) return;
    thresholdAlertRules = repository.readThresholdAlertRules(profile.id);
    _thresholdAlertEngine.reconcileRules(thresholdAlertRules);
    _notify();
  }

  Future<void> deleteThresholdAlertRule(
    String ruleId, {
    required String expectedProfileId,
  }) async {
    final profile = active;
    if (profile == null || _disposed || profile.id != expectedProfileId) {
      return;
    }
    await repository.deleteThresholdAlertRule(profile.id, ruleId);
    if (_disposed || active?.id != profile.id) return;
    thresholdAlertRules = repository.readThresholdAlertRules(profile.id);
    _thresholdAlertEngine.reconcileRules(thresholdAlertRules);
    _notify();
  }

  void _evaluateThresholdAlerts() {
    final snapshot = inventory;
    if (snapshot == null) return;
    _thresholdAlertEngine.evaluate(
      inventory: snapshot,
      storages: storages,
      rules: thresholdAlertRules,
      storageDataCurrent: storageMessage == null,
    );
  }

  Future<void> setGuestFavorite(
    Guest guest,
    bool favorite, {
    String? expectedProfileId,
  }) async {
    final profile = active;
    if (profile == null ||
        _disposed ||
        (expectedProfileId != null && profile.id != expectedProfileId)) {
      return;
    }
    final key = _guestKey(guest);
    await repository.setGuestFavorite(profile.id, key, favorite);
    if (active?.id != profile.id || _disposed) return;
    if (favorite) {
      favoriteGuests.add(key);
    } else {
      favoriteGuests.remove(key);
    }
    _notify();
  }

  Future<void> toggleGuestFavorite(Guest guest, {String? expectedProfileId}) =>
      setGuestFavorite(
        guest,
        !isGuestFavorite(guest),
        expectedProfileId: expectedProfileId,
      );

  Future<SavedGuestView?> saveGuestView(
    SavedGuestView view, {
    required String expectedProfileId,
  }) async {
    final profile = active;
    if (profile == null || _disposed || profile.id != expectedProfileId) {
      return null;
    }
    await repository.saveGuestView(profile.id, view);
    if (_disposed || active?.id != profile.id) return null;
    guestSavedViews = repository.readGuestViews(profile.id);
    final normalizedName = view.name.toLowerCase();
    final saved = guestSavedViews.where(
      (item) => item.name.toLowerCase() == normalizedName,
    );
    _notify();
    return saved.isEmpty ? null : saved.first;
  }

  Future<void> deleteGuestView(
    String viewId, {
    required String expectedProfileId,
  }) async {
    final profile = active;
    if (profile == null || _disposed || profile.id != expectedProfileId) {
      return;
    }
    await repository.deleteGuestView(profile.id, viewId);
    if (_disposed || active?.id != profile.id) return;
    guestSavedViews = repository.readGuestViews(profile.id);
    _notify();
  }

  bool isGuestActionBlocked(Guest guest) {
    return isProvisioningTargetBlocked(guest.kind, guest.node, guest.vmid);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      themePreference = repository.themePreference;
      autoRefreshPreference = repository.autoRefreshPreference;
      showNodeMetrics = repository.showNodeMetrics;
      highContrast = repository.highContrast;
      reduceMotion = repository.reduceMotion;
      profiles = repository.readProfiles();
      final selected = repository.activeId;
      if (selected != null) {
        final matches = profiles.where((profile) => profile.id == selected);
        if (matches.isNotEmpty) {
          await activate(matches.first);
        } else {
          // Do not silently connect to a different profile when the persisted
          // selection is missing or corrupt. Let the operator choose.
          await repository.setActive(null);
        }
      }
    } catch (_) {
      message = 'Could not load saved connections. Check local secure storage.';
    } finally {
      initialized = true;
      _notify();
    }
  }

  Future<void> setThemePreference(AppThemePreference value) async {
    if (_disposed) return;
    await repository.setThemePreference(value);
    if (_disposed) return;
    themePreference = value;
    _notify();
  }

  Future<void> setAutoRefreshPreference(AutoRefreshPreference value) async {
    if (_disposed) return;
    await repository.setAutoRefreshPreference(value);
    if (_disposed) return;
    autoRefreshPreference = value;
    _scheduleAutoRefresh();
    _notify();
  }

  Future<void> setShowNodeMetrics(bool value) async {
    if (_disposed) return;
    await repository.setShowNodeMetrics(value);
    if (_disposed) return;
    showNodeMetrics = value;
    _notify();
  }

  Future<void> setHighContrast(bool value) async {
    if (_disposed) return;
    await repository.setHighContrast(value);
    if (_disposed) return;
    highContrast = value;
    _notify();
  }

  Future<void> setReduceMotion(bool value) async {
    if (_disposed) return;
    await repository.setReduceMotion(value);
    if (_disposed) return;
    reduceMotion = value;
    _notify();
  }

  Future<bool> setForegroundNotificationPolicy(
    ForegroundNotificationPolicy policy, {
    required String expectedProfileId,
  }) async {
    final profile = active;
    if (_disposed || profile == null || profile.id != expectedProfileId) {
      return false;
    }
    final generation = _generation;
    final validated = ForegroundNotificationPolicy.fromJson(policy.toJson());
    if (validated.enabled && !foregroundNotificationPolicy.enabled) {
      final granted = await _incidentNotifier.requestPermission();
      if (!granted ||
          _disposed ||
          active?.id != expectedProfileId ||
          generation != _generation) {
        return false;
      }
    }
    await repository.saveForegroundNotificationPolicy(
      expectedProfileId,
      validated,
    );
    if (_disposed ||
        active?.id != expectedProfileId ||
        generation != _generation) {
      return false;
    }
    foregroundNotificationPolicy = validated;
    _notify();
    return true;
  }

  Future<void> setOfflineOverviewEnabled(bool enabled) async {
    final profileId = active?.id;
    if (_disposed || profileId == null) return;
    await repository.setOfflineOverviewEnabled(profileId, enabled);
    if (_disposed || active?.id != profileId) return;
    offlineOverviewEnabled = enabled;
    if (!enabled) {
      cachedOverview = null;
    } else if (isInventoryWriteSafe) {
      try {
        await repository.saveOfflineOverview(
          profileId,
          OfflineOverview.fromInventory(inventory!),
        );
      } catch (_) {
        // Cache persistence is optional; never change live authorization.
      }
    }
    _notify();
  }

  Future<void> _clearOfflineAfterAuth(int generation) async {
    if (_disposed || generation != _generation) return;
    final profileId = active?.id;
    cachedOverview = null;
    if (profileId == null) return;
    try {
      await repository.clearOfflineOverview(profileId);
    } catch (_) {
      // The cached data is hidden for this session even if deletion fails.
    }
  }

  Future<void> _recordAuthenticatedReadLoss(
    int generation,
    String errorMessage,
  ) async {
    if (_disposed || generation != _generation) return;
    message = errorMessage;
    await _clearOfflineAfterAuth(generation);
    if (_disposed || generation != _generation) return;
    _notify();
  }

  Future<ConnectionCheckResult> verifyConnectionConfiguration({
    required String name,
    required String address,
    String tokenId = '',
    String secret = '',
    bool allowInvalidCertificates = false,
    String? existingProfileId,
  }) async {
    if (_disposed) throw const PveFailure('Connection check canceled.');
    if (connecting) {
      throw const PveFailure('A connection is already being checked.');
    }

    ConnectionProfile profile;
    ApiCredentials? credential;
    if (existingProfileId == null) {
      profile = ConnectionProfile.create(
        name: name,
        address: address,
        allowInvalidCertificates: allowInvalidCertificates,
      );
      credential = ApiCredentials(tokenId: tokenId.trim(), secret: secret);
    } else {
      final matches = repository.readProfiles().where(
        (item) => item.id == existingProfileId,
      );
      if (matches.isEmpty) {
        throw const PveFailure('Connection no longer exists.');
      }
      final existing = matches.first;
      final normalizedName = name.trim();
      if (normalizedName.isEmpty) {
        throw const FormatException('Enter a profile name.');
      }
      profile = ConnectionProfile(
        id: existing.id,
        name: normalizedName,
        endpoint: normalizePveEndpoint(address),
        allowInvalidCertificates: allowInvalidCertificates,
        lastServerVersion: existing.lastServerVersion,
      );
      final tokenChanged = tokenId.trim().isNotEmpty || secret.isNotEmpty;
      credential = tokenChanged
          ? ApiCredentials(tokenId: tokenId.trim(), secret: secret)
          : await repository.vault.retrieve(existing.id);
      if (credential == null) {
        throw const PveFailure(
          'Saved token unavailable. Enter a replacement token to check this connection.',
        );
      }
    }

    if (!credential.isValid) {
      throw const FormatException(
        'Enter both a valid token ID (user@realm!token-name) and token secret.',
      );
    }

    final generation = _generation;
    connecting = true;
    _notify();
    try {
      return await _checkConnectionCandidate(profile, credential, generation);
    } finally {
      connecting = false;
      _notify();
    }
  }

  Future<ConnectionCheckResult> testSavedConnection(String profileId) async {
    if (_disposed) throw const PveFailure('Connection check canceled.');
    if (connecting) {
      throw const PveFailure('A connection is already being checked.');
    }
    final matches = repository.readProfiles().where(
      (profile) => profile.id == profileId,
    );
    if (matches.isEmpty) {
      throw const PveFailure('Connection no longer exists.');
    }
    final profile = matches.first;
    final credential = await repository.vault.retrieve(profile.id);
    if (credential == null || !credential.isValid) {
      throw const PveFailure(
        'Saved token unavailable. Edit this connection and enter a replacement token.',
      );
    }

    final generation = _generation;
    connecting = true;
    _notify();
    try {
      final result = await _checkConnectionCandidate(
        profile,
        credential,
        generation,
      );
      final observed = profile.withServerVersion(result.serverVersion);
      if (observed.lastServerVersion != profile.lastServerVersion) {
        try {
          await repository.updateMetadata(observed);
          if (!_disposed && generation == _generation) {
            profiles = repository.readProfiles();
            if (active?.id == observed.id) active = observed;
            _notify();
          }
        } catch (_) {
          // Verification remains valid even if display-only version metadata
          // cannot be refreshed locally.
        }
      }
      return result;
    } finally {
      connecting = false;
      _notify();
    }
  }

  Future<ConnectionCheckResult> _checkConnectionCandidate(
    ConnectionProfile profile,
    ApiCredentials credential,
    int generation,
  ) async {
    PveGateway? candidate;
    try {
      candidate = _factory(profile, credential);
      final serverVersion = normalizeServerVersion(await candidate.version());
      _checkConnectionSetup(generation);
      try {
        final snapshot = await candidate.inventory();
        _checkConnectionSetup(generation);
        return ConnectionCheckResult(
          serverVersion: serverVersion,
          inventoryAccessible: true,
          certificateVerificationEnabled: !profile.allowInvalidCertificates,
          nodeCount: snapshot.nodes.length,
          guestCount: snapshot.guests.length,
        );
      } on PveFailure catch (error) {
        _checkConnectionSetup(generation);
        if (error.status == 401 || error.status == 403) {
          return ConnectionCheckResult(
            serverVersion: serverVersion,
            inventoryAccessible: false,
            certificateVerificationEnabled: !profile.allowInvalidCertificates,
            inventoryMessage: error.message,
            inventoryStatus: error.status,
          );
        }
        rethrow;
      }
    } finally {
      candidate?.close();
    }
  }

  Future<void> connect({
    required String name,
    required String address,
    required String tokenId,
    required String secret,
    bool allowInvalidCertificates = false,
  }) async {
    if (_disposed) throw const PveFailure('Connection setup canceled.');
    if (connecting) {
      throw const PveFailure('A connection is already being checked.');
    }
    final generation = _generation;
    final previousActiveId = repository.activeId;
    final profile = ConnectionProfile.create(
      name: name,
      address: address,
      allowInvalidCertificates: allowInvalidCertificates,
    );
    final credential = ApiCredentials(tokenId: tokenId.trim(), secret: secret);
    if (!credential.isValid) {
      throw const FormatException('Token ID must be user@realm!token-name.');
    }
    connecting = true;
    _notify();
    PveGateway? candidate;
    try {
      candidate = _factory(profile, credential);
      final serverVersion = await candidate.version();
      _checkConnectionSetup(generation);
      await candidate.inventory(); // A valid token must also access inventory.
      _checkConnectionSetup(generation);
      final validatedProfile = profile.withServerVersion(serverVersion);
      await repository.save(validatedProfile, credential);
      if (_disposed) {
        await _rollbackCanceledConnection(profile.id, previousActiveId);
        throw const PveFailure('Connection setup canceled.');
      }
      profiles = repository.readProfiles();
      if (generation == _generation) {
        await activate(validatedProfile, knownServerVersion: serverVersion);
      } else {
        // Saving may finish after the operator has switched connections. Keep
        // their selection, but retain the newly saved profile for later use.
        await repository.setActive(active?.id);
        throw const PveFailure(
          'Connection saved, but the active connection changed.',
        );
      }
    } finally {
      candidate?.close();
      connecting = false;
      _notify();
    }
  }

  Future<void> updateConnection({
    required String profileId,
    required String name,
    required String address,
    String tokenId = '',
    String secret = '',
    bool allowInvalidCertificates = false,
  }) async {
    if (_disposed) throw const PveFailure('Connection update canceled.');
    if (connecting) {
      throw const PveFailure('A connection is already being checked.');
    }
    final matches = repository.readProfiles().where(
      (profile) => profile.id == profileId,
    );
    if (matches.isEmpty) {
      throw const PveFailure('Connection no longer exists.');
    }
    final existing = matches.first;
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const FormatException('Enter a profile name.');
    }
    final profile = ConnectionProfile(
      id: existing.id,
      name: normalizedName,
      endpoint: normalizePveEndpoint(address),
      allowInvalidCertificates: allowInvalidCertificates,
      lastServerVersion: existing.lastServerVersion,
    );
    final tokenChanged = tokenId.trim().isNotEmpty || secret.isNotEmpty;
    final storedCredentials = await repository.vault.retrieve(existing.id);
    final credential = tokenChanged
        ? ApiCredentials(tokenId: tokenId.trim(), secret: secret)
        : storedCredentials;
    if (credential == null) {
      throw const PveFailure(
        'Saved token unavailable. Enter a replacement token to update this connection.',
      );
    }
    if (!credential.isValid) {
      throw const FormatException(
        'Enter both a valid token ID (user@realm!token-name) and token secret, or leave both blank to keep the saved token.',
      );
    }

    final generation = _generation;
    connecting = true;
    _notify();
    PveGateway? candidate;
    try {
      candidate = _factory(profile, credential);
      final serverVersion = await candidate.version();
      _checkConnectionSetup(generation);
      await candidate.inventory();
      _checkConnectionSetup(generation);
      final validatedProfile = profile.withServerVersion(serverVersion);
      try {
        await _backgroundCheckScheduler.disable(
          existing.id,
          clearPolicy: true,
        );
      } on BackgroundCheckException {
        throw const PveFailure(
          'Could not clear scheduled checks before updating this connection.',
        );
      }
      _checkConnectionSetup(generation);
      if (tokenChanged) {
        await repository.update(validatedProfile, credential);
      } else {
        await repository.updateConfigurationMetadata(validatedProfile);
      }
      if (_disposed) {
        throw const PveFailure(
          'Connection update completed after app shutdown.',
        );
      }
      profiles = repository.readProfiles();
      if (generation == _generation && active?.id == profile.id) {
        await activate(validatedProfile, knownServerVersion: serverVersion);
      } else {
        _notify();
      }
    } finally {
      candidate?.close();
      connecting = false;
      _notify();
    }
  }

  void _checkConnectionSetup(int generation) {
    if (_disposed || generation != _generation) {
      throw const PveFailure('Connection changed; setup canceled.');
    }
  }

  Future<void> _rollbackCanceledConnection(
    String profileId,
    String? previousActiveId,
  ) async {
    try {
      await repository.delete(profileId);
    } catch (_) {
      // Failing closed is preferable to reviving a disposed controller. A
      // subsequent launch will surface any incomplete local credential state.
      return;
    }
    try {
      final remaining = repository.readProfiles();
      if (previousActiveId == null ||
          remaining.any((profile) => profile.id == previousActiveId)) {
        await repository.setActive(previousActiveId);
      }
    } catch (_) {
      // Rollback is best-effort after the newly-created credential is removed.
    }
  }

  Future<void> activate(
    ConnectionProfile profile, {
    String? knownServerVersion,
  }) async {
    if (_disposed || _deletingProfiles.contains(profile.id)) return;
    final generation = ++_generation;
    _pollTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _refreshFuture = null;
    _gateway?.close();
    _gateway = null;
    active = profile;
    offlineOverviewEnabled = repository.offlineOverviewEnabled(profile.id);
    cachedOverview = null;
    favoriteGuests = repository.readGuestFavorites(profile.id);
    guestSavedViews = repository.readGuestViews(profile.id);
    thresholdAlertRules = repository.readThresholdAlertRules(profile.id);
    incidentHistory = repository.readIncidentHistory(profile.id);
    foregroundNotificationPolicy = repository.readForegroundNotificationPolicy(
      profile.id,
    );
    _lastForegroundNotificationAt = repository.readLastForegroundNotificationAt(
      profile.id,
    );
    _thresholdAlertEngine.clear();
    _incidentTriage.clear();
    inventory = null;
    tasks.clear();
    storages = [];
    serverTasks = [];
    _retainedServerTaskIncidents = const <CockpitIncident>[];
    storageMessage = null;
    serverTaskMessage = null;
    inventoryWarning = null;
    _pendingGuestOperations.clear();
    _uncertainGuestOperations.clear();
    _taskTargets.clear();
    message = null;
    refreshing = false;
    _notify();
    if (deviceNetworkState == DeviceNetworkState.unavailable) {
      cachedOverview = repository.readOfflineOverview(profile.id);
      _notify();
      return;
    }
    try {
      final credentials = await repository.vault.retrieve(profile.id);
      if (generation != _generation || _disposed) return;
      if (credentials == null || !credentials.isValid) {
        throw const PveFailure(
          'Saved token unavailable. Remove and add this connection again.',
        );
      }
      _gateway = _factory(profile, credentials);
      final serverVersion = knownServerVersion ?? await _gateway!.version();
      if (generation != _generation || _disposed) return;
      final observedProfile = profile.withServerVersion(serverVersion);
      active = observedProfile;
      if (profile.lastServerVersion != observedProfile.lastServerVersion) {
        try {
          await repository.updateMetadata(observedProfile);
          if (generation != _generation || _disposed) return;
          profiles = repository.readProfiles();
        } catch (_) {
          // Version metadata is useful but not credential-sensitive. Keep the
          // live observed version in memory even if local metadata cannot be
          // refreshed; the connection itself may still be used safely.
        }
      }
      await repository.setActive(profile.id);
      if (generation != _generation || _disposed) return;
      _notify();
      await refresh();
      if (generation == _generation && _foreground) {
        _startPolling();
        _scheduleAutoRefresh();
      }
    } catch (e) {
      if (generation == _generation) {
        _gateway?.close();
        _gateway = null;
        inventory = null;
        cachedOverview =
            deviceNetworkState == DeviceNetworkState.unavailable ||
                (e is PveFailure && e.transportFailure != null)
            ? repository.readOfflineOverview(profile.id)
            : null;
        if (e is PveFailure && e.status == 401) {
          await _clearOfflineAfterAuth(generation);
        }
        if (generation != _generation || _disposed) return;
        message = e is PveFailure ? e.message : 'Could not open connection.';
        _notify();
      }
    }
  }

  Future<void> refresh() {
    if (_disposed || deviceNetworkState == DeviceNetworkState.unavailable) {
      return Future<void>.value();
    }
    final current = _refreshFuture;
    if (current != null) return current;
    late final Future<void> future;
    future = _refreshOnce().whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
    _refreshFuture = future;
    return future;
  }

  Future<void> _refreshOnce() async {
    final gateway = _gateway;
    if (_disposed || gateway == null) return;
    final generation = _generation;
    final networkEpoch = _networkEpoch;
    final profileId = active?.id;
    refreshing = true;
    _notify();
    try {
      final next = await gateway.inventory();
      if (generation != _generation ||
          networkEpoch != _networkEpoch ||
          _disposed ||
          deviceNetworkState == DeviceNetworkState.unavailable) {
        return;
      }
      inventory = next;
      _inventoryRevision++;
      cachedOverview = null;
      message = null;
      inventoryWarning = next.malformedGuestRecords == 0
          ? null
          : 'Ignored ${next.malformedGuestRecords} malformed guest record(s). '
                'Guest mutations are disabled until a clean inventory refresh.';
      final nodes = next.nodes.map((node) => node.name).toList(growable: false);
      await Future.wait<void>([
        _loadStorage(gateway, nodes, generation),
        _loadServerTasks(gateway, nodes, generation),
      ]);
      if (generation != _generation ||
          networkEpoch != _networkEpoch ||
          _disposed) {
        return;
      }
      _evaluateThresholdAlerts();
      // Do not turn a network-presence hint into authorization. A completed
      // clean authenticated read is the only way to restore live writes.
      if (message == null &&
          deviceNetworkState != DeviceNetworkState.unavailable) {
        _requiresRecovery = false;
      }
      // Save only a clean, fully authenticated live inventory. Supplemental
      // 401s must not refresh a cache belonging to a revoked credential.
      if (profileId != null &&
          offlineOverviewEnabled &&
          deviceNetworkState != DeviceNetworkState.unavailable &&
          message == null &&
          next.malformedGuestRecords == 0) {
        try {
          await repository.saveOfflineOverview(
            profileId,
            OfflineOverview.fromInventory(next),
          );
        } catch (_) {
          // Offline display is optional; cache failures cannot make live
          // inventory appear unsafe or block normal read operations.
        }
      }
      if (generation == _generation &&
          networkEpoch == _networkEpoch &&
          !_disposed &&
          deviceNetworkState != DeviceNetworkState.unavailable) {
        // Only a complete authenticated snapshot can move missing signals
        // into the local earlier-observations timeline.
        final triageComplete =
            message == null &&
            inventoryWarning == null &&
            storageMessage == null &&
            serverTaskMessage == null;
        _incidentTriage.observe(incidents, complete: triageComplete);
        final newOccurrences = _captureIncidentHistory(
          complete: triageComplete,
        );
        if (profileId != null && newOccurrences.isNotEmpty) {
          unawaited(
            _maybeDeliverForegroundIncidentNotification(
              newOccurrences,
              profileId: profileId,
              generation: generation,
            ),
          );
        }
      }
    } catch (e) {
      if (generation != _generation || _disposed) return;
      message = e is PveFailure ? e.message : 'Unable to refresh inventory.';
      if (e is PveFailure && e.status == 401) {
        await _clearOfflineAfterAuth(generation);
      } else if (inventory == null &&
          e is PveFailure &&
          e.transportFailure != null &&
          profileId != null) {
        cachedOverview = repository.readOfflineOverview(profileId);
      }
      // Last live result remains stale; cached counts never authorize writes.
    } finally {
      if (generation == _generation) {
        refreshing = false;
        _notify();
      }
    }
  }

  Future<void> _loadStorage(
    PveGateway gateway,
    List<String> nodes,
    int generation,
  ) async {
    try {
      final result = await gateway.storageOverview(nodes);
      if (generation != _generation || _disposed) return;
      storages = result.values;
      storageMessage = _sectionWarning(result, 'storage data');
    } on PveFailure catch (error) {
      if (generation != _generation || _disposed) return;
      if (error.status == 401) {
        message = error.message;
        await _clearOfflineAfterAuth(generation);
      }
      if (generation != _generation || _disposed) return;
      storageMessage =
          'Storage overview could not be refreshed. Previously shown data may be stale.';
    } catch (_) {
      if (generation != _generation || _disposed) return;
      storageMessage =
          'Storage overview could not be refreshed. Previously shown data may be stale.';
    }
  }

  Future<void> _loadServerTasks(
    PveGateway gateway,
    List<String> nodes,
    int generation,
  ) async {
    try {
      final result = await gateway.recentTasks(nodes);
      if (generation != _generation || _disposed) return;
      if (result.complete) {
        _retainedServerTaskIncidents = const <CockpitIncident>[];
      } else {
        final retained =
            <String, CockpitIncident>{
              for (final incident in _retainedServerTaskIncidents)
                incident.key: incident,
              for (final incident in failedServerTaskIncidents(serverTasks))
                incident.key: incident,
            }.values.toList()..sort(
              (left, right) => right.observedAt.compareTo(left.observedAt),
            );
        _retainedServerTaskIncidents = List<CockpitIncident>.unmodifiable(
          retained.take(60),
        );
      }
      serverTasks = result.values;
      serverTaskMessage = _sectionWarning(result, 'server task history');
    } on PveFailure catch (error) {
      if (generation != _generation || _disposed) return;
      if (error.status == 401) {
        message = error.message;
        await _clearOfflineAfterAuth(generation);
      }
      if (generation != _generation || _disposed) return;
      serverTaskMessage =
          'Server task history could not be refreshed. Previously shown data may be stale.';
    } catch (_) {
      if (generation != _generation || _disposed) return;
      serverTaskMessage =
          'Server task history could not be refreshed. Previously shown data may be stale.';
    }
  }

  String? _sectionWarning<T>(ReadCollection<T> result, String label) {
    if (result.complete) return null;
    final details = <String>[];
    if (result.permissionDeniedNodes > 0) {
      details.add('${result.permissionDeniedNodes} node(s) denied access');
    }
    if (result.failedNodes > 0) {
      details.add('${result.failedNodes} node(s) unavailable');
    }
    if (result.malformedRecords > 0) {
      details.add('${result.malformedRecords} malformed record(s) ignored');
    }
    final detail = details.join(', ');
    return result.values.isEmpty
        ? 'Could not load $label ($detail).'
        : 'Some $label is unavailable ($detail).';
  }

  bool get isInventoryFresh {
    if (_disposed ||
        _requiresRecovery ||
        deviceNetworkState == DeviceNetworkState.unavailable ||
        inventory == null ||
        message != null) {
      return false;
    }
    final age = DateTime.now().difference(inventory!.fetchedAt);
    return age >= Duration.zero && age < const Duration(minutes: 2);
  }

  bool get isInventoryWriteSafe =>
      isInventoryFresh && inventory!.malformedGuestRecords == 0;

  Future<void> _verifyGuestStatusBeforeMutation(
    PveGateway gateway,
    Guest guest,
    bool Function() stillCurrent,
  ) async {
    final status = await gateway.guestStatus(guest);
    if (!stillCurrent()) {
      throw const PveFailure(
        'Connection or inventory changed during live status verification.',
      );
    }
    if (status != guest.status) {
      throw const PveFailure(
        'Guest state changed during live status verification. Refresh and review again.',
      );
    }
  }

  Future<void> runQemuCreate(
    QemuCreateRequest request, {
    required String profileId,
    required int generation,
  }) async {
    final gateway = _gateway;
    final GuestCreateGateway? createGateway = gateway is GuestCreateGateway
        ? gateway as GuestCreateGateway
        : null;
    final normalized = request.normalized();
    final validationError = normalized.validationError;
    if (validationError != null) {
      throw PveFailure(validationError);
    }
    if (_disposed || active?.id != profileId || generation != _generation) {
      throw const PveFailure(
        'Connection changed; return to Guests before creating a VM.',
      );
    }
    if (!_foreground ||
        gateway == null ||
        createGateway == null ||
        !isInventoryWriteSafe ||
        refreshing ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      throw const PveFailure(
        'Refresh a clean live inventory before creating a VM.',
      );
    }

    final snapshot = inventory!;
    final nodes = snapshot.nodes
        .where((node) => node.name == normalized.node)
        .toList();
    if (nodes.length != 1 || nodes.single.status != 'online') {
      throw const PveFailure(
        'Destination node is no longer confirmed online. Refresh and review again.',
      );
    }
    if (snapshot.guests.any((guest) => guest.vmid == normalized.vmid)) {
      throw const PveFailure(
        'Destination VMID is already present in the current inventory.',
      );
    }

    final key = _provisioningKey('qemu', normalized.node, normalized.vmid);
    final destinationKey = _provisioningVmidKey(normalized.vmid);
    final keys = {key, destinationKey};
    if (keys.any(_uncertainGuestOperations.contains)) {
      throw const PveFailure(
        'An earlier create has an unknown outcome. Verify server task history '
        'and inventory before reconnecting and trying again.',
        mayHaveExecuted: true,
      );
    }
    if (keys.any(_pendingGuestOperations.contains)) {
      throw const PveFailure(
        'A create operation is already pending for this VMID. Check Tasks.',
      );
    }

    _pendingGuestOperations.addAll(keys);
    _notify();
    var postAttempted = false;
    try {
      final live = await gateway.inventory();
      if (generation != _generation ||
          active?.id != profileId ||
          _disposed ||
          !_foreground ||
          deviceNetworkState == DeviceNetworkState.unavailable) {
        throw const PveFailure('Connection changed; VM create canceled.');
      }
      if (!identical(snapshot, inventory) ||
          refreshing ||
          !isInventoryWriteSafe) {
        throw const PveFailure(
          'Inventory changed during create verification. Refresh and review again.',
        );
      }
      if (live.malformedGuestRecords != 0) {
        throw const PveFailure(
          'Live inventory verification is incomplete. VM create was not submitted.',
        );
      }
      final liveNodes = live.nodes
          .where((node) => node.name == normalized.node)
          .toList();
      if (liveNodes.length != 1 || liveNodes.single.status != 'online') {
        throw const PveFailure(
          'Destination node is no longer online. VM create was not submitted.',
        );
      }
      if (live.guests.any((guest) => guest.vmid == normalized.vmid)) {
        throw const PveFailure(
          'Destination VMID became occupied. Choose another VMID.',
        );
      }

      final permissions = await createGateway.permissionsForVmid(
        normalized.vmid,
      );
      if (generation != _generation ||
          active?.id != profileId ||
          _disposed ||
          !_foreground ||
          deviceNetworkState == DeviceNetworkState.unavailable ||
          !identical(snapshot, inventory) ||
          refreshing ||
          !isInventoryWriteSafe) {
        throw const PveFailure(
          'Connection or inventory changed during create verification.',
        );
      }
      const requiredPrivileges = {
        'VM.Allocate',
        'VM.Config.CPU',
        'VM.Config.Memory',
        'VM.Config.Options',
      };
      final missing =
          requiredPrivileges
              .where((privilege) => !permissions.has(privilege))
              .toList()
            ..sort();
      if (missing.isNotEmpty) {
        throw PveFailure(
          'The active token does not report required destination privileges: '
          '${missing.join(', ')}.',
          status: 403,
        );
      }

      await createGateway.assertVmidAvailable(normalized.vmid);
      if (generation != _generation ||
          active?.id != profileId ||
          _disposed ||
          !_foreground ||
          deviceNetworkState == DeviceNetworkState.unavailable ||
          !identical(snapshot, inventory) ||
          refreshing ||
          !isInventoryWriteSafe) {
        throw const PveFailure(
          'Connection or inventory changed during create verification.',
        );
      }

      postAttempted = true;
      final upid = await createGateway.createQemu(normalized);
      if (generation != _generation || active?.id != profileId || _disposed) {
        throw const PveFailure(
          'Connection changed after create submission. Check server task history.',
          mayHaveExecuted: true,
        );
      }
      _taskTargets[upid] = keys;
      tasks.insert(
        0,
        TrackedTask(
          upid: upid,
          node: normalized.node,
          title:
              'Create QEMU ${normalized.name} (${normalized.vmid}) on ${normalized.node}',
          startedAt: DateTime.now(),
          outcome: OperationOutcome.running,
        ),
      );
      _notify();
      if (_foreground) _startPolling();
    } catch (error) {
      if (generation == _generation &&
          error is PveFailure &&
          error.status == 401) {
        message = error.message;
        unawaited(_clearOfflineAfterAuth(generation));
      }
      if (generation == _generation &&
          (error is PveFailure ? error.mayHaveExecuted : postAttempted)) {
        _uncertainGuestOperations.addAll(keys);
      }
      rethrow;
    } finally {
      if (generation == _generation &&
          !_taskTargets.values.any((targets) => targets.contains(key))) {
        _pendingGuestOperations.removeAll(keys);
      }
      if (generation == _generation) _notify();
    }
  }

  Future<void> runLxcCreate(
    LxcCreateRequest request, {
    required String profileId,
    required int generation,
  }) async {
    final gateway = _gateway;
    final LxcCreateGateway? createGateway = gateway is LxcCreateGateway
        ? gateway as LxcCreateGateway
        : null;
    final normalized = request.normalized();
    final validationError = normalized.validationError;
    if (validationError != null) {
      throw PveFailure(validationError);
    }
    if (_disposed || active?.id != profileId || generation != _generation) {
      throw const PveFailure(
        'Connection changed; return to Guests before creating a container.',
      );
    }
    if (!_foreground ||
        gateway == null ||
        createGateway == null ||
        !isInventoryWriteSafe ||
        refreshing ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      throw const PveFailure(
        'Refresh a clean live inventory before creating a container.',
      );
    }

    final snapshot = inventory!;
    final nodes = snapshot.nodes
        .where((node) => node.name == normalized.node)
        .toList();
    if (nodes.length != 1 || nodes.single.status != 'online') {
      throw const PveFailure(
        'Destination node is no longer confirmed online. Refresh and review again.',
      );
    }
    if (snapshot.guests.any((guest) => guest.vmid == normalized.vmid)) {
      throw const PveFailure(
        'Destination VMID is already present in the current inventory.',
      );
    }

    final key = _provisioningKey('lxc', normalized.node, normalized.vmid);
    final destinationKey = _provisioningVmidKey(normalized.vmid);
    final keys = {key, destinationKey};
    if (keys.any(_uncertainGuestOperations.contains)) {
      throw const PveFailure(
        'An earlier create has an unknown outcome. Verify server task history '
        'and inventory before reconnecting and trying again.',
        mayHaveExecuted: true,
      );
    }
    if (keys.any(_pendingGuestOperations.contains)) {
      throw const PveFailure(
        'A create operation is already pending for this VMID. Check Tasks.',
      );
    }

    bool stillCurrent() =>
        generation == _generation &&
        active?.id == profileId &&
        !_disposed &&
        _foreground &&
        deviceNetworkState != DeviceNetworkState.unavailable &&
        identical(snapshot, inventory) &&
        !refreshing &&
        isInventoryWriteSafe;

    _pendingGuestOperations.addAll(keys);
    _notify();
    var postAttempted = false;
    try {
      final live = await gateway.inventory();
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection changed; container create canceled.',
        );
      }
      if (live.malformedGuestRecords != 0) {
        throw const PveFailure(
          'Live inventory verification is incomplete. Container create was not submitted.',
        );
      }
      final liveNodes = live.nodes
          .where((node) => node.name == normalized.node)
          .toList();
      if (liveNodes.length != 1 || liveNodes.single.status != 'online') {
        throw const PveFailure(
          'Destination node is no longer online. Container create was not submitted.',
        );
      }
      if (live.guests.any((guest) => guest.vmid == normalized.vmid)) {
        throw const PveFailure(
          'Destination VMID became occupied. Choose another VMID.',
        );
      }

      final options = await createGateway.lxcCreateOptions(normalized.node);
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during container verification.',
        );
      }
      if (options.incomplete || !options.supports(normalized)) {
        throw const PveFailure(
          'Container template or root filesystem storage could not be cleanly revalidated. Refresh and review again.',
        );
      }

      final destinationPermissions = await createGateway.permissionsForVmid(
        normalized.vmid,
      );
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during container verification.',
        );
      }
      const requiredPrivileges = {
        'VM.Allocate',
        'VM.Config.CPU',
        'VM.Config.Memory',
        'VM.Config.Network',
        'VM.Config.Options',
      };
      final missing =
          requiredPrivileges
              .where((privilege) => !destinationPermissions.has(privilege))
              .toList()
            ..sort();
      if (missing.isNotEmpty) {
        throw PveFailure(
          'The active token does not report required destination privileges: '
          '${missing.join(', ')}.',
          status: 403,
        );
      }

      final rootfsPermissions = await createGateway.permissionsForPath(
        '/storage/${normalized.rootfsStorage}',
      );
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during container verification.',
        );
      }
      if (!rootfsPermissions.has('Datastore.AllocateSpace')) {
        throw const PveFailure(
          'The active token does not report Datastore.AllocateSpace on the root filesystem storage.',
          status: 403,
        );
      }

      final templatePermissions = await createGateway.permissionsForPath(
        '/storage/${normalized.templateStorage}',
      );
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during container verification.',
        );
      }
      if (!templatePermissions.has('Datastore.Audit') &&
          !templatePermissions.has('Datastore.AllocateSpace')) {
        throw const PveFailure(
          'The active token cannot read the selected container template storage.',
          status: 403,
        );
      }

      await createGateway.assertVmidAvailable(normalized.vmid);
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during container verification.',
        );
      }

      postAttempted = true;
      final upid = await createGateway.createLxc(normalized);
      if (generation != _generation || active?.id != profileId || _disposed) {
        throw const PveFailure(
          'Connection changed after container create submission. Check server task history.',
          mayHaveExecuted: true,
        );
      }
      _taskTargets[upid] = keys;
      tasks.insert(
        0,
        TrackedTask(
          upid: upid,
          node: normalized.node,
          title:
              'Create LXC ${normalized.hostname} (${normalized.vmid}) on ${normalized.node}',
          startedAt: DateTime.now(),
          outcome: OperationOutcome.running,
        ),
      );
      _notify();
      if (_foreground) _startPolling();
    } catch (error) {
      if (generation == _generation &&
          error is PveFailure &&
          error.status == 401) {
        message = error.message;
        unawaited(_clearOfflineAfterAuth(generation));
      }
      if (generation == _generation &&
          (error is PveFailure ? error.mayHaveExecuted : postAttempted)) {
        _uncertainGuestOperations.addAll(keys);
      }
      rethrow;
    } finally {
      if (generation == _generation &&
          !_taskTargets.values.any((targets) => targets.contains(key))) {
        _pendingGuestOperations.removeAll(keys);
      }
      if (generation == _generation) _notify();
    }
  }

  Future<void> runTemplateClone(
    Guest source,
    GuestCloneRequest request, {
    required String profileId,
  }) async {
    final gateway = _gateway;
    final GuestCloneGateway? cloneGateway = gateway is GuestCloneGateway
        ? gateway as GuestCloneGateway
        : null;
    final generation = _generation;
    final normalized = request.normalized();
    final validationError = normalized.validationError;
    if (validationError != null) {
      throw PveFailure(validationError);
    }
    if (_disposed || active?.id != profileId) {
      throw const PveFailure(
        'Connection changed; return to the template before cloning.',
      );
    }
    if (!_foreground ||
        gateway == null ||
        cloneGateway == null ||
        !isInventoryWriteSafe ||
        refreshing ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      throw const PveFailure(
        'Refresh a clean live inventory before cloning a template.',
      );
    }

    final snapshot = inventory!;
    final sourceMatches = snapshot.guests
        .where(
          (item) =>
              item.kind == source.kind &&
              item.vmid == source.vmid &&
              item.node == source.node,
        )
        .toList();
    if (sourceMatches.length != 1 ||
        !identical(sourceMatches.single, source) ||
        !source.isTemplate) {
      throw const PveFailure(
        'Template inventory changed. Refresh and review the source again.',
      );
    }
    if (snapshot.guests.any((item) => item.vmid == normalized.newVmid)) {
      throw const PveFailure(
        'Destination VMID is already present in the current inventory.',
      );
    }

    final key = _guestKey(source);
    final destinationKey = _provisioningVmidKey(normalized.newVmid);
    final keys = {key, destinationKey};
    if (keys.any(_uncertainGuestOperations.contains)) {
      throw const PveFailure(
        'An earlier clone has an unknown outcome. Verify server task history '
        'and inventory before reconnecting and trying again.',
        mayHaveExecuted: true,
      );
    }
    if (keys.any(_pendingGuestOperations.contains)) {
      throw const PveFailure(
        'An operation is already pending for this template or destination VMID. Check Tasks.',
      );
    }

    _pendingGuestOperations.addAll(keys);
    _notify();
    var postAttempted = false;
    try {
      final live = await gateway.inventory();
      if (generation != _generation ||
          active?.id != profileId ||
          _disposed ||
          !_foreground ||
          deviceNetworkState == DeviceNetworkState.unavailable) {
        throw const PveFailure('Connection changed; clone canceled.');
      }
      if (!identical(snapshot, inventory) ||
          refreshing ||
          !isInventoryWriteSafe) {
        throw const PveFailure(
          'Inventory changed during clone verification. Refresh and review again.',
        );
      }
      if (live.malformedGuestRecords != 0) {
        throw const PveFailure(
          'Live inventory verification is incomplete. Clone was not submitted.',
        );
      }
      final liveSources = live.guests
          .where(
            (item) =>
                item.kind == source.kind &&
                item.vmid == source.vmid &&
                item.node == source.node,
          )
          .toList();
      if (liveSources.length != 1 || !liveSources.single.isTemplate) {
        throw const PveFailure(
          'The source is no longer a confirmed template. Clone was not submitted.',
        );
      }
      if (live.guests.any((item) => item.vmid == normalized.newVmid)) {
        throw const PveFailure(
          'Destination VMID became occupied. Choose another VMID.',
        );
      }

      final sourcePermissions = await cloneGateway.permissionsForVmid(
        source.vmid,
      );
      if (!sourcePermissions.has('VM.Clone')) {
        throw const PveFailure(
          'The active token does not report VM.Clone on this template.',
          status: 403,
        );
      }
      final destinationPermissions = await cloneGateway.permissionsForVmid(
        normalized.newVmid,
      );
      if (!destinationPermissions.has('VM.Allocate')) {
        throw const PveFailure(
          'The active token does not report VM.Allocate for the destination VMID.',
          status: 403,
        );
      }

      // This is a last-moment server-side collision check. A successful GET is
      // still followed by exactly one clone POST; the POST remains authoritative.
      await cloneGateway.assertVmidAvailable(normalized.newVmid);
      if (generation != _generation ||
          active?.id != profileId ||
          _disposed ||
          !_foreground ||
          deviceNetworkState == DeviceNetworkState.unavailable ||
          !identical(snapshot, inventory) ||
          refreshing ||
          !isInventoryWriteSafe) {
        throw const PveFailure(
          'Connection or inventory changed during clone verification.',
        );
      }

      postAttempted = true;
      final upid = await cloneGateway.cloneTemplate(source, normalized);
      if (generation != _generation || active?.id != profileId || _disposed) {
        throw const PveFailure(
          'Connection changed after clone submission. Check server task history.',
          mayHaveExecuted: true,
        );
      }
      _taskTargets[upid] = keys;
      tasks.insert(
        0,
        TrackedTask(
          upid: upid,
          node: source.node,
          title:
              'Clone ${source.name} (${source.vmid}) → ${normalized.name} (${normalized.newVmid})',
          startedAt: DateTime.now(),
          outcome: OperationOutcome.running,
        ),
      );
      _notify();
      if (_foreground) _startPolling();
    } catch (error) {
      if (generation == _generation &&
          error is PveFailure &&
          error.status == 401) {
        message = error.message;
        unawaited(_clearOfflineAfterAuth(generation));
      }
      if (generation == _generation &&
          (error is PveFailure ? error.mayHaveExecuted : postAttempted)) {
        _uncertainGuestOperations.addAll(keys);
      }
      rethrow;
    } finally {
      if (generation == _generation &&
          !_taskTargets.values.any((targets) => targets.contains(key))) {
        _pendingGuestOperations.removeAll(keys);
      }
      if (generation == _generation) _notify();
    }
  }

  Future<void> runGuestMigration(
    Guest source,
    GuestMigrationRequest request, {
    required String profileId,
    required int generation,
  }) async {
    final gateway = _gateway;
    final GuestMigrationGateway? migrationGateway =
        gateway is GuestMigrationGateway
        ? gateway as GuestMigrationGateway
        : null;
    final normalized = request.normalized();
    final validationError = normalized.validationError;
    if (validationError != null) {
      throw PveFailure(validationError);
    }
    if (_disposed || generation != _generation || active?.id != profileId) {
      throw const PveFailure(
        'Connection changed; return to the guest before migrating.',
      );
    }
    if (source.isTemplate) {
      throw const PveFailure(
        'Templates cannot be migrated. Clone the template instead.',
      );
    }
    if (!source.isRunning && !source.isStopped) {
      throw const PveFailure(
        'Guest state must be running or stopped before migration.',
      );
    }
    if (normalized.targetNode == source.node) {
      throw const PveFailure(
        'Choose a destination node different from the source node.',
      );
    }
    if (!_foreground ||
        gateway == null ||
        migrationGateway == null ||
        !isInventoryWriteSafe ||
        refreshing ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      throw const PveFailure(
        'Refresh a clean live inventory before migrating a guest.',
      );
    }

    final snapshot = inventory!;
    final sourceMatches = snapshot.guests
        .where(
          (item) =>
              item.kind == source.kind &&
              item.vmid == source.vmid &&
              item.node == source.node,
        )
        .toList();
    if (sourceMatches.length != 1 ||
        !identical(sourceMatches.single, source) ||
        sourceMatches.single.isTemplate) {
      throw const PveFailure(
        'Guest inventory changed. Refresh and review the source again.',
      );
    }
    final targetMatches = snapshot.nodes
        .where((node) => node.name == normalized.targetNode)
        .toList();
    if (targetMatches.length != 1 || targetMatches.single.status != 'online') {
      throw const PveFailure(
        'Destination node is not uniquely available and online.',
      );
    }

    final key = _guestKey(source);
    final vmidKey = _provisioningVmidKey(source.vmid);
    final keys = {key, vmidKey};
    if (keys.any(_uncertainGuestOperations.contains)) {
      throw const PveFailure(
        'An earlier operation for this guest has an unknown outcome. '
        'Verify server task history and inventory before reconnecting and trying again.',
        mayHaveExecuted: true,
      );
    }
    if (keys.any(_pendingGuestOperations.contains)) {
      throw const PveFailure(
        'An operation is already pending for this guest. Check Tasks.',
      );
    }

    bool stillCurrent() =>
        generation == _generation &&
        active?.id == profileId &&
        !_disposed &&
        _foreground &&
        deviceNetworkState != DeviceNetworkState.unavailable &&
        identical(snapshot, inventory) &&
        !refreshing &&
        isInventoryWriteSafe;

    _pendingGuestOperations.addAll(keys);
    _notify();
    var postAttempted = false;
    try {
      final live = await gateway.inventory();
      if (!stillCurrent()) {
        throw const PveFailure('Connection changed; migration canceled.');
      }
      if (live.malformedGuestRecords != 0) {
        throw const PveFailure(
          'Live inventory verification is incomplete. Migration was not submitted.',
        );
      }

      final liveSources = live.guests
          .where(
            (item) =>
                item.kind == source.kind &&
                item.vmid == source.vmid &&
                item.node == source.node,
          )
          .toList();
      if (liveSources.length != 1 || liveSources.single.isTemplate) {
        throw const PveFailure(
          'The source guest moved or disappeared during verification.',
        );
      }
      final liveSource = liveSources.single;
      if (liveSource.status != source.status) {
        throw const PveFailure(
          'Guest state changed during migration verification. Refresh and review again.',
        );
      }

      final liveTargets = live.nodes
          .where((node) => node.name == normalized.targetNode)
          .toList();
      if (liveTargets.length != 1 || liveTargets.single.status != 'online') {
        throw const PveFailure(
          'Destination node is no longer online. Migration was not submitted.',
        );
      }

      final permissions = await migrationGateway.guestPermissions(liveSource);
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during migration verification.',
        );
      }
      if (!permissions.has('VM.Migrate')) {
        throw const PveFailure(
          'The active token does not report VM.Migrate on this guest.',
          status: 403,
        );
      }

      final preflight = await migrationGateway.migrationPreflight(
        liveSource,
        normalized.targetNode,
      );
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during migration verification.',
        );
      }
      if (preflight.incomplete ||
          preflight.running != liveSource.isRunning ||
          !preflight.allowsTarget(normalized.targetNode)) {
        throw const PveFailure(
          'Server migration preflight did not cleanly allow the selected destination.',
        );
      }
      if (liveSource.kind == 'qemu' &&
          (preflight.localDiskCount != 0 ||
              preflight.localResources.isNotEmpty)) {
        throw const PveFailure(
          'This guarded QEMU migration slice requires shared storage and no local host resources. '
          'Local-disk/resource migration options remain gated.',
        );
      }

      await _verifyGuestStatusBeforeMutation(gateway, liveSource, stillCurrent);
      postAttempted = true;
      final upid = await migrationGateway.migrateGuest(liveSource, normalized);
      if (generation != _generation || active?.id != profileId || _disposed) {
        throw const PveFailure(
          'Connection changed after migration submission. Check server task history.',
          mayHaveExecuted: true,
        );
      }
      _taskTargets[upid] = keys;
      tasks.insert(
        0,
        TrackedTask(
          upid: upid,
          node: source.node,
          title:
              'Migrate ${source.name} (${source.vmid}) '
              '${source.node} → ${normalized.targetNode}',
          startedAt: DateTime.now(),
          outcome: OperationOutcome.running,
        ),
      );
      _notify();
      if (_foreground) _startPolling();
    } catch (error) {
      if (generation == _generation &&
          error is PveFailure &&
          error.status == 401) {
        message = error.message;
        unawaited(_clearOfflineAfterAuth(generation));
      }
      if (generation == _generation &&
          (error is PveFailure ? error.mayHaveExecuted : postAttempted)) {
        _uncertainGuestOperations.addAll(keys);
      }
      rethrow;
    } finally {
      if (generation == _generation &&
          !_taskTargets.values.any((targets) => targets.contains(key))) {
        _pendingGuestOperations.removeAll(keys);
        _pendingGuestOperations.remove(vmidKey);
      }
      if (generation == _generation) _notify();
    }
  }

  Future<void> runGuestSnapshotCreate(
    Guest source,
    GuestSnapshotCreateRequest request, {
    required String profileId,
    required int generation,
  }) async {
    final gateway = _gateway;
    final GuestSnapshotCreateGateway? snapshotGateway =
        gateway is GuestSnapshotCreateGateway
        ? gateway as GuestSnapshotCreateGateway
        : null;
    if (_disposed || generation != _generation || active?.id != profileId) {
      throw const PveFailure(
        'Connection changed; return to the guest before taking a snapshot.',
      );
    }
    if (source.isTemplate) {
      throw const PveFailure(
        'Template snapshots are not exposed by this guarded workflow.',
      );
    }
    if (!source.isRunning && !source.isStopped) {
      throw const PveFailure(
        'Refresh the guest before taking a snapshot; its state is unknown.',
      );
    }
    final normalized = request.normalized();
    final validationError = normalized.validationError;
    if (validationError != null) throw PveFailure(validationError);
    if (!_foreground ||
        gateway == null ||
        snapshotGateway == null ||
        !isInventoryWriteSafe ||
        refreshing ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      throw const PveFailure(
        'Refresh a clean live inventory before taking a snapshot.',
      );
    }

    final inventorySnapshot = inventory!;
    final sourceMatches = inventorySnapshot.guests
        .where(
          (item) =>
              item.kind == source.kind &&
              item.vmid == source.vmid &&
              item.node == source.node,
        )
        .toList();
    if (sourceMatches.length != 1 ||
        !identical(sourceMatches.single, source) ||
        sourceMatches.single.status != source.status ||
        sourceMatches.single.isTemplate) {
      throw const PveFailure(
        'Guest inventory changed. Refresh and review the snapshot target again.',
      );
    }

    final key = _guestKey(source);
    final vmidKey = _provisioningVmidKey(source.vmid);
    final keys = {key, vmidKey};
    if (keys.any(_uncertainGuestOperations.contains)) {
      throw const PveFailure(
        'An earlier operation for this guest has an unknown outcome. '
        'Verify server task history and inventory before reconnecting and trying again.',
        mayHaveExecuted: true,
      );
    }
    if (keys.any(_pendingGuestOperations.contains)) {
      throw const PveFailure(
        'An operation is already pending for this guest. Check Tasks.',
      );
    }

    bool stillCurrent() =>
        generation == _generation &&
        active?.id == profileId &&
        !_disposed &&
        _foreground &&
        deviceNetworkState != DeviceNetworkState.unavailable &&
        identical(inventorySnapshot, inventory) &&
        !refreshing &&
        isInventoryWriteSafe;

    _pendingGuestOperations.addAll(keys);
    _notify();
    var postAttempted = false;
    try {
      final live = await gateway.inventory();
      if (!stillCurrent()) {
        throw const PveFailure('Connection changed; snapshot canceled.');
      }
      if (live.malformedGuestRecords != 0) {
        throw const PveFailure(
          'Live inventory verification is incomplete. Snapshot was not submitted.',
        );
      }

      final liveSources = live.guests
          .where(
            (item) =>
                item.kind == source.kind &&
                item.vmid == source.vmid &&
                item.node == source.node,
          )
          .toList();
      if (liveSources.length != 1 || liveSources.single.isTemplate) {
        throw const PveFailure(
          'The guest moved, disappeared, or became a template during verification.',
        );
      }
      final liveSource = liveSources.single;
      if (liveSource.status != source.status ||
          (!liveSource.isRunning && !liveSource.isStopped)) {
        throw const PveFailure(
          'Guest state changed during snapshot verification. Refresh and review it again.',
        );
      }

      final permissions = await snapshotGateway.guestPermissions(liveSource);
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during snapshot verification.',
        );
      }
      if (!permissions.has('VM.Snapshot')) {
        throw const PveFailure(
          'The active token does not report VM.Snapshot on this guest.',
          status: 403,
        );
      }

      final currentSnapshots = await snapshotGateway.guestSnapshots(liveSource);
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during snapshot-name verification.',
        );
      }
      if (currentSnapshots.malformedRecords != 0 ||
          currentSnapshots.truncated) {
        throw const PveFailure(
          'Snapshot inventory verification is incomplete. Snapshot was not submitted.',
        );
      }
      if (currentSnapshots.snapshots.any(
        (item) => !item.isCurrent && item.name == normalized.name,
      )) {
        throw PveFailure(
          'A snapshot named "${normalized.name}" already exists.',
        );
      }

      await _verifyGuestStatusBeforeMutation(gateway, liveSource, stillCurrent);
      postAttempted = true;
      final upid = await snapshotGateway.createGuestSnapshot(
        liveSource,
        normalized,
      );
      if (generation != _generation || active?.id != profileId || _disposed) {
        throw const PveFailure(
          'Connection changed after snapshot submission. Check server task history.',
          mayHaveExecuted: true,
        );
      }

      _taskTargets[upid] = keys;
      tasks.insert(
        0,
        TrackedTask(
          upid: upid,
          node: source.node,
          title:
              'Snapshot ${source.name} (${source.vmid}) • ${normalized.name}',
          startedAt: DateTime.now(),
          outcome: OperationOutcome.running,
        ),
      );
      _notify();
      if (_foreground) _startPolling();
    } catch (error) {
      if (generation == _generation &&
          error is PveFailure &&
          error.status == 401) {
        message = error.message;
        unawaited(_clearOfflineAfterAuth(generation));
      }
      if (generation == _generation &&
          (error is PveFailure ? error.mayHaveExecuted : postAttempted)) {
        _uncertainGuestOperations.addAll(keys);
      }
      rethrow;
    } finally {
      if (generation == _generation &&
          !_taskTargets.values.any((targets) => targets.contains(key))) {
        _pendingGuestOperations.removeAll(keys);
      }
      if (generation == _generation) _notify();
    }
  }

  Future<void> runGuestSnapshotDelete(
    Guest source,
    GuestSnapshot snapshot, {
    required String profileId,
    required int generation,
  }) => _runGuestSnapshotLifecycle(
    source,
    snapshot,
    profileId: profileId,
    generation: generation,
    action: _GuestSnapshotLifecycleAction.delete,
  );

  Future<void> runGuestSnapshotRollback(
    Guest source,
    GuestSnapshot snapshot, {
    required String profileId,
    required int generation,
  }) => _runGuestSnapshotLifecycle(
    source,
    snapshot,
    profileId: profileId,
    generation: generation,
    action: _GuestSnapshotLifecycleAction.rollback,
  );

  Future<void> _runGuestSnapshotLifecycle(
    Guest source,
    GuestSnapshot snapshot, {
    required String profileId,
    required int generation,
    required _GuestSnapshotLifecycleAction action,
  }) async {
    final gateway = _gateway;
    final GuestSnapshotMutationGateway? mutationGateway =
        gateway is GuestSnapshotMutationGateway
        ? gateway as GuestSnapshotMutationGateway
        : null;
    final rollback = action == _GuestSnapshotLifecycleAction.rollback;
    final actionVerb = rollback ? 'rolling back' : 'deleting';
    final actionLabel = rollback ? 'rollback' : 'delete';

    if (_disposed || generation != _generation || active?.id != profileId) {
      throw PveFailure(
        'Connection changed; return to the guest before $actionVerb a snapshot.',
      );
    }
    if (source.isTemplate) {
      throw const PveFailure(
        'Template snapshots are not exposed by this guarded workflow.',
      );
    }
    if (rollback && !source.isStopped) {
      throw const PveFailure(
        'Stop the guest and refresh before rolling back a snapshot.',
      );
    }
    if (!rollback && !source.isRunning && !source.isStopped) {
      throw const PveFailure(
        'Refresh the guest before deleting a snapshot; its state is unknown.',
      );
    }
    final validationError = snapshot.mutationValidationError;
    if (validationError != null) throw PveFailure(validationError);
    if (rollback && snapshot.includesMemory == true) {
      throw const PveFailure(
        'Snapshots that include QEMU RAM state require a separate '
        'power-aware rollback workflow.',
      );
    }
    if (!_foreground ||
        gateway == null ||
        mutationGateway == null ||
        !isInventoryWriteSafe ||
        refreshing ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      throw PveFailure(
        'Refresh a clean live inventory before $actionVerb this snapshot.',
      );
    }

    final inventorySnapshot = inventory!;
    final sourceMatches = inventorySnapshot.guests
        .where(
          (item) =>
              item.kind == source.kind &&
              item.vmid == source.vmid &&
              item.node == source.node,
        )
        .toList();
    if (sourceMatches.length != 1 ||
        !identical(sourceMatches.single, source) ||
        sourceMatches.single.status != source.status ||
        sourceMatches.single.isTemplate) {
      throw const PveFailure(
        'Guest inventory changed. Refresh and review the snapshot target again.',
      );
    }

    final key = _guestKey(source);
    final vmidKey = _provisioningVmidKey(source.vmid);
    final keys = {key, vmidKey};
    if (keys.any(_uncertainGuestOperations.contains)) {
      throw const PveFailure(
        'An earlier operation for this guest has an unknown outcome. '
        'Verify server task history and inventory before reconnecting and trying again.',
        mayHaveExecuted: true,
      );
    }
    if (keys.any(_pendingGuestOperations.contains)) {
      throw const PveFailure(
        'An operation is already pending for this guest. Check Tasks.',
      );
    }

    bool stillCurrent() =>
        generation == _generation &&
        active?.id == profileId &&
        !_disposed &&
        _foreground &&
        deviceNetworkState != DeviceNetworkState.unavailable &&
        identical(inventorySnapshot, inventory) &&
        !refreshing &&
        isInventoryWriteSafe;

    _pendingGuestOperations.addAll(keys);
    _notify();
    var mutationAttempted = false;
    try {
      final live = await gateway.inventory();
      if (!stillCurrent()) {
        throw PveFailure('Connection changed; snapshot $actionLabel canceled.');
      }
      if (live.malformedGuestRecords != 0) {
        throw PveFailure(
          'Live inventory verification is incomplete. Snapshot $actionLabel was not submitted.',
        );
      }

      final liveSources = live.guests
          .where(
            (item) =>
                item.kind == source.kind &&
                item.vmid == source.vmid &&
                item.node == source.node,
          )
          .toList();
      if (liveSources.length != 1 ||
          liveSources.single.isTemplate ||
          liveSources.single.status != source.status ||
          liveSources.single.name != source.name) {
        throw PveFailure(
          'The guest moved, disappeared, was renamed, or changed state during '
          'verification. Snapshot $actionLabel was not submitted.',
        );
      }
      final liveSource = liveSources.single;
      if (rollback && !liveSource.isStopped) {
        throw const PveFailure(
          'The guest is no longer stopped. Snapshot rollback was not submitted.',
        );
      }

      final permissions = await mutationGateway.guestPermissions(liveSource);
      if (!stillCurrent()) {
        throw PveFailure(
          'Connection or inventory changed during snapshot $actionLabel verification.',
        );
      }
      final hasPermission = rollback
          ? permissions.has('VM.Snapshot') ||
                permissions.has('VM.Snapshot.Rollback')
          : permissions.has('VM.Snapshot');
      if (!hasPermission) {
        throw PveFailure(
          rollback
              ? 'The active token does not report VM.Snapshot or '
                    'VM.Snapshot.Rollback on this guest.'
              : 'The active token does not report VM.Snapshot on this guest.',
          status: 403,
        );
      }

      final currentSnapshots = await mutationGateway.guestSnapshots(liveSource);
      if (!stillCurrent()) {
        throw PveFailure(
          'Connection or inventory changed during snapshot $actionLabel verification.',
        );
      }
      if (currentSnapshots.malformedRecords != 0 ||
          currentSnapshots.truncated) {
        throw PveFailure(
          'Snapshot inventory verification is incomplete. '
          'Snapshot $actionLabel was not submitted.',
        );
      }
      final freshMatches = currentSnapshots.snapshots
          .where((item) => !item.isCurrent && item.name == snapshot.name)
          .toList();
      if (freshMatches.length != 1) {
        throw PveFailure(
          'Snapshot "${snapshot.name}" no longer exists. Refresh before retrying.',
        );
      }
      final freshSnapshot = freshMatches.single;
      if (!freshSnapshot.sameMetadataAs(snapshot)) {
        throw PveFailure(
          'Snapshot "${snapshot.name}" changed during verification. '
          'Refresh and review it again.',
        );
      }
      if (rollback && freshSnapshot.includesMemory == true) {
        throw const PveFailure(
          'The snapshot now reports QEMU RAM state and cannot use this '
          'stopped-only workflow.',
        );
      }

      await _verifyGuestStatusBeforeMutation(gateway, liveSource, stillCurrent);
      mutationAttempted = true;
      final upid = rollback
          ? await mutationGateway.rollbackGuestSnapshot(
              liveSource,
              freshSnapshot,
            )
          : await mutationGateway.deleteGuestSnapshot(
              liveSource,
              freshSnapshot,
            );
      if (generation != _generation || active?.id != profileId || _disposed) {
        throw PveFailure(
          'Connection changed after snapshot $actionLabel submission. '
          'Check server task history.',
          mayHaveExecuted: true,
        );
      }

      _taskTargets[upid] = keys;
      tasks.insert(
        0,
        TrackedTask(
          upid: upid,
          node: source.node,
          title: rollback
              ? 'Rollback ${source.name} (${source.vmid}) • ${snapshot.name}'
              : 'Delete snapshot ${source.name} (${source.vmid}) • ${snapshot.name}',
          startedAt: DateTime.now(),
          outcome: OperationOutcome.running,
        ),
      );
      _notify();
      if (_foreground) _startPolling();
    } catch (error) {
      if (generation == _generation &&
          error is PveFailure &&
          error.status == 401) {
        message = error.message;
        unawaited(_clearOfflineAfterAuth(generation));
      }
      if (generation == _generation &&
          (error is PveFailure ? error.mayHaveExecuted : mutationAttempted)) {
        _uncertainGuestOperations.addAll(keys);
      }
      rethrow;
    } finally {
      if (generation == _generation &&
          !_taskTargets.values.any((targets) => targets.contains(key))) {
        _pendingGuestOperations.removeAll(keys);
      }
      if (generation == _generation) _notify();
    }
  }

  Future<void> runGuestBackup(
    Guest source,
    GuestBackupRequest request, {
    required String profileId,
    required int generation,
  }) async {
    final gateway = _gateway;
    final GuestBackupGateway? backupGateway = gateway is GuestBackupGateway
        ? gateway as GuestBackupGateway
        : null;
    if (_disposed || generation != _generation || active?.id != profileId) {
      throw const PveFailure(
        'Connection changed; return to the guest before starting a backup.',
      );
    }
    if (source.isTemplate) {
      throw const PveFailure(
        'Template backup is not exposed by this guarded guest workflow.',
      );
    }
    if (!source.isRunning && !source.isStopped) {
      throw const PveFailure(
        'Refresh the guest before starting a backup; its state is unknown.',
      );
    }
    final normalized = request.normalized();
    final validationError = normalized.validationError;
    if (validationError != null) throw PveFailure(validationError);
    if (!_foreground ||
        gateway == null ||
        backupGateway == null ||
        !isInventoryWriteSafe ||
        refreshing ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      throw const PveFailure(
        'Refresh a clean live inventory before starting a backup.',
      );
    }

    final inventorySnapshot = inventory!;
    final sourceMatches = inventorySnapshot.guests
        .where(
          (item) =>
              item.kind == source.kind &&
              item.vmid == source.vmid &&
              item.node == source.node,
        )
        .toList();
    if (sourceMatches.length != 1 ||
        !identical(sourceMatches.single, source) ||
        sourceMatches.single.status != source.status ||
        sourceMatches.single.isTemplate) {
      throw const PveFailure(
        'Guest inventory changed. Refresh and review the backup target again.',
      );
    }

    final key = _guestKey(source);
    final vmidKey = _provisioningVmidKey(source.vmid);
    final keys = {key, vmidKey};
    if (keys.any(_uncertainGuestOperations.contains)) {
      throw const PveFailure(
        'An earlier operation for this guest has an unknown outcome. '
        'Verify server task history and inventory before reconnecting and trying again.',
        mayHaveExecuted: true,
      );
    }
    if (keys.any(_pendingGuestOperations.contains)) {
      throw const PveFailure(
        'An operation is already pending for this guest. Check Tasks.',
      );
    }

    bool stillCurrent() =>
        generation == _generation &&
        active?.id == profileId &&
        !_disposed &&
        _foreground &&
        deviceNetworkState != DeviceNetworkState.unavailable &&
        identical(inventorySnapshot, inventory) &&
        !refreshing &&
        isInventoryWriteSafe;

    _pendingGuestOperations.addAll(keys);
    _notify();
    var postAttempted = false;
    try {
      final live = await gateway.inventory();
      if (!stillCurrent()) {
        throw const PveFailure('Connection changed; backup canceled.');
      }
      if (live.malformedGuestRecords != 0) {
        throw const PveFailure(
          'Live inventory verification is incomplete. Backup was not submitted.',
        );
      }

      final liveSources = live.guests
          .where(
            (item) =>
                item.kind == source.kind &&
                item.vmid == source.vmid &&
                item.node == source.node,
          )
          .toList();
      if (liveSources.length != 1 || liveSources.single.isTemplate) {
        throw const PveFailure(
          'The guest moved, disappeared, or became a template during verification.',
        );
      }
      final liveSource = liveSources.single;
      if (liveSource.status != source.status ||
          (!liveSource.isRunning && !liveSource.isStopped)) {
        throw const PveFailure(
          'Guest state changed during backup verification. Refresh and review it again.',
        );
      }

      final permissions = await backupGateway.guestPermissions(liveSource);
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during backup verification.',
        );
      }
      if (!permissions.has('VM.Backup')) {
        throw const PveFailure(
          'The active token does not report VM.Backup on this guest.',
          status: 403,
        );
      }

      final backupStorages = await backupGateway.backupStorages(
        liveSource.node,
      );
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during backup-storage verification.',
        );
      }
      if (!backupStorages.contains(normalized.storage)) {
        throw PveFailure(
          'Backup storage "${normalized.storage}" is not active and backup-capable on this node.',
        );
      }

      final storagePermissions = await backupGateway.permissionsForPath(
        '/storage/${normalized.storage}',
      );
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during storage permission verification.',
        );
      }
      if (!storagePermissions.has('Datastore.AllocateSpace')) {
        throw const PveFailure(
          'The active token does not report Datastore.AllocateSpace on the selected backup storage.',
          status: 403,
        );
      }

      await _verifyGuestStatusBeforeMutation(gateway, liveSource, stillCurrent);
      postAttempted = true;
      final upid = await backupGateway.startGuestBackup(liveSource, normalized);
      if (generation != _generation || active?.id != profileId || _disposed) {
        throw const PveFailure(
          'Connection changed after backup submission. Check server task history.',
          mayHaveExecuted: true,
        );
      }

      _taskTargets[upid] = keys;
      tasks.insert(
        0,
        TrackedTask(
          upid: upid,
          node: source.node,
          title:
              'Backup ${source.name} (${source.vmid}) • ${normalized.storage}',
          startedAt: DateTime.now(),
          outcome: OperationOutcome.running,
        ),
      );
      _notify();
      if (_foreground) _startPolling();
    } catch (error) {
      if (generation == _generation &&
          error is PveFailure &&
          error.status == 401) {
        message = error.message;
        unawaited(_clearOfflineAfterAuth(generation));
      }
      if (generation == _generation &&
          (error is PveFailure ? error.mayHaveExecuted : postAttempted)) {
        _uncertainGuestOperations.addAll(keys);
      }
      rethrow;
    } finally {
      if (generation == _generation &&
          !_taskTargets.values.any((targets) => targets.contains(key))) {
        _pendingGuestOperations.removeAll(keys);
      }
      if (generation == _generation) _notify();
    }
  }

  Future<void> runGuestDeletion(
    Guest source, {
    required String profileId,
    required int generation,
  }) async {
    final gateway = _gateway;
    final GuestDeleteGateway? deleteGateway = gateway is GuestDeleteGateway
        ? gateway as GuestDeleteGateway
        : null;
    if (_disposed || generation != _generation || active?.id != profileId) {
      throw const PveFailure(
        'Connection changed; return to the guest before deleting.',
      );
    }
    if (source.isTemplate) {
      throw const PveFailure(
        'Template deletion is not exposed by this guarded guest workflow.',
      );
    }
    if (!source.isStopped) {
      throw const PveFailure('Stop the guest before deleting it.');
    }
    if (!_foreground ||
        gateway == null ||
        deleteGateway == null ||
        !isInventoryWriteSafe ||
        refreshing ||
        deviceNetworkState == DeviceNetworkState.unavailable) {
      throw const PveFailure(
        'Refresh a clean live inventory before deleting a guest.',
      );
    }

    final snapshot = inventory!;
    final sourceMatches = snapshot.guests
        .where(
          (item) =>
              item.kind == source.kind &&
              item.vmid == source.vmid &&
              item.node == source.node,
        )
        .toList();
    if (sourceMatches.length != 1 ||
        !identical(sourceMatches.single, source) ||
        sourceMatches.single.status != source.status ||
        sourceMatches.single.isTemplate) {
      throw const PveFailure(
        'Guest inventory changed. Refresh and review the deletion target again.',
      );
    }

    final key = _guestKey(source);
    final vmidKey = _provisioningVmidKey(source.vmid);
    final keys = {key, vmidKey};
    if (keys.any(_uncertainGuestOperations.contains)) {
      throw const PveFailure(
        'An earlier operation for this guest has an unknown outcome. '
        'Verify server task history and inventory before reconnecting and trying again.',
        mayHaveExecuted: true,
      );
    }
    if (keys.any(_pendingGuestOperations.contains)) {
      throw const PveFailure(
        'An operation is already pending for this guest. Check Tasks.',
      );
    }

    bool stillCurrent() =>
        generation == _generation &&
        active?.id == profileId &&
        !_disposed &&
        _foreground &&
        deviceNetworkState != DeviceNetworkState.unavailable &&
        identical(snapshot, inventory) &&
        !refreshing &&
        isInventoryWriteSafe;

    _pendingGuestOperations.addAll(keys);
    _notify();
    var deleteAttempted = false;
    try {
      final live = await gateway.inventory();
      if (!stillCurrent()) {
        throw const PveFailure('Connection changed; deletion canceled.');
      }
      if (live.malformedGuestRecords != 0) {
        throw const PveFailure(
          'Live inventory verification is incomplete. Deletion was not submitted.',
        );
      }

      final liveSources = live.guests
          .where(
            (item) =>
                item.kind == source.kind &&
                item.vmid == source.vmid &&
                item.node == source.node,
          )
          .toList();
      if (liveSources.length != 1 || liveSources.single.isTemplate) {
        throw const PveFailure(
          'The guest moved, disappeared, or became a template during verification.',
        );
      }
      final liveSource = liveSources.single;
      if (!liveSource.isStopped || liveSource.status != source.status) {
        throw const PveFailure(
          'Guest state changed during deletion verification. It must remain stopped.',
        );
      }
      if (liveSource.name != source.name) {
        throw const PveFailure(
          'Guest name changed during deletion verification. Refresh and confirm the exact target again.',
        );
      }

      final permissions = await deleteGateway.guestPermissions(liveSource);
      if (!stillCurrent()) {
        throw const PveFailure(
          'Connection or inventory changed during deletion verification.',
        );
      }
      if (!permissions.has('VM.Allocate')) {
        throw const PveFailure(
          'The active token does not report VM.Allocate on this guest.',
          status: 403,
        );
      }

      await _verifyGuestStatusBeforeMutation(gateway, liveSource, stillCurrent);
      deleteAttempted = true;
      final upid = await deleteGateway.deleteGuest(liveSource);
      if (generation != _generation || active?.id != profileId || _disposed) {
        throw const PveFailure(
          'Connection changed after deletion submission. Check server task history.',
          mayHaveExecuted: true,
        );
      }
      _taskTargets[upid] = keys;
      tasks.insert(
        0,
        TrackedTask(
          upid: upid,
          node: source.node,
          title: 'Delete ${source.name} (${source.vmid})',
          startedAt: DateTime.now(),
          outcome: OperationOutcome.running,
        ),
      );
      _notify();
      if (_foreground) _startPolling();
    } catch (error) {
      if (generation == _generation &&
          error is PveFailure &&
          error.status == 401) {
        message = error.message;
        unawaited(_clearOfflineAfterAuth(generation));
      }
      if (generation == _generation &&
          (error is PveFailure ? error.mayHaveExecuted : deleteAttempted)) {
        _uncertainGuestOperations.addAll(keys);
      }
      rethrow;
    } finally {
      if (generation == _generation &&
          !_taskTargets.values.any((targets) => targets.contains(key))) {
        _pendingGuestOperations.removeAll(keys);
      }
      if (generation == _generation) _notify();
    }
  }

  Future<void> runAction(
    Guest guest,
    GuestAction action, {
    required String profileId,
  }) async {
    final gateway = _gateway;
    final generation = _generation;
    if (_disposed || active?.id != profileId) {
      throw const PveFailure(
        'Connection changed; return to the guest list before acting.',
      );
    }
    if (!_foreground ||
        gateway == null ||
        !isInventoryWriteSafe ||
        refreshing) {
      throw const PveFailure(
        'Refresh a clean live inventory before making changes.',
      );
    }

    // A guest shown by an old screen must not authorize a command. A VMID
    // present at multiple nodes is ambiguous even if its status matches.
    final snapshot = inventory!;
    final matches = snapshot.guests
        .where((item) => item.kind == guest.kind && item.vmid == guest.vmid)
        .toList();
    if (matches.length != 1 ||
        !identical(matches.single, guest) ||
        matches.single.node != guest.node ||
        matches.single.status != guest.status) {
      throw const PveFailure(
        'Guest inventory changed. Refresh and review the target again.',
      );
    }
    if (guest.isTemplate) {
      throw const PveFailure(
        'Templates cannot use power actions. Use the guarded clone workflow for supported template cloning.',
      );
    }
    if (!action.allowedFor(guest)) {
      throw const PveFailure(
        'This action is not available for the current guest state.',
      );
    }

    final key = _guestKey(guest);
    final provisioningKey = _provisioningVmidKey(guest.vmid);
    if (_uncertainGuestOperations.contains(key) ||
        _uncertainGuestOperations.contains(provisioningKey)) {
      throw const PveFailure(
        'An earlier action has an unknown outcome. Verify the guest and '
        'server task history before reconnecting and trying again.',
        mayHaveExecuted: true,
      );
    }
    if (_pendingGuestOperations.contains(key) ||
        _pendingGuestOperations.contains(provisioningKey)) {
      throw const PveFailure(
        'An operation is already pending for this guest. Check Tasks.',
      );
    }
    // Reserve the target synchronously before the first await. This prevents
    // double-taps or independent screens from submitting duplicate writes.
    _pendingGuestOperations.add(key);
    _notify();
    var postAttempted = false;
    try {
      final actual = await gateway.guestStatus(guest);
      if (generation != _generation ||
          active?.id != profileId ||
          _disposed ||
          !_foreground) {
        throw const PveFailure('Connection changed; action canceled.');
      }
      if (!identical(snapshot, inventory) ||
          refreshing ||
          !isInventoryWriteSafe) {
        throw const PveFailure(
          'Inventory changed during verification. Refresh and review again.',
        );
      }
      if (actual != guest.status) {
        throw const PveFailure(
          'Guest state changed. Refresh and review before retrying.',
        );
      }

      // Exactly one POST; no automatic retry after an ambiguous failure.
      postAttempted = true;
      final upid = await gateway.submit(guest, action);
      if (generation != _generation || active?.id != profileId || _disposed) {
        throw const PveFailure(
          'Connection changed after submission. Check server task history.',
          mayHaveExecuted: true,
        );
      }
      _taskTargets[upid] = {key};
      tasks.insert(
        0,
        TrackedTask(
          upid: upid,
          node: guest.node,
          title: '${action.label} ${guest.name} (${guest.vmid})',
          startedAt: DateTime.now(),
          outcome: OperationOutcome.running,
        ),
      );
      _notify();
      if (_foreground) _startPolling();
    } catch (error) {
      if (generation == _generation &&
          error is PveFailure &&
          error.status == 401) {
        message = error.message;
        unawaited(_clearOfflineAfterAuth(generation));
      }
      // A failed POST can have executed on the server; do not allow another
      // local submission until the operator reviews the server-side result.
      if (generation == _generation &&
          (error is PveFailure ? error.mayHaveExecuted : postAttempted)) {
        _uncertainGuestOperations.add(key);
      }
      rethrow;
    } finally {
      if (generation == _generation &&
          !_taskTargets.values.any((targets) => targets.contains(key))) {
        _pendingGuestOperations.remove(key);
      }
      if (generation == _generation) _notify();
    }
  }

  /// Android's default-network signal is not a PVE server reachability test.
  void setDeviceNetworkState(DeviceNetworkState next) {
    if (_disposed || next == deviceNetworkState) return;
    deviceNetworkState = next;
    if (next == DeviceNetworkState.unavailable) {
      _networkEpoch++;
      _requiresRecovery = true;
      _pollTimer?.cancel();
      _autoRefreshTimer?.cancel();
      if (inventory == null && active != null) {
        cachedOverview = repository.readOfflineOverview(active!.id);
      }
    } else if (next == DeviceNetworkState.available && _requiresRecovery) {
      final profileId = active?.id;
      if (_foreground && profileId != null) {
        unawaited(_recoverNetwork(_generation, profileId));
      }
    }
    _notify();
  }

  Future<void> _recoverNetwork(int generation, String profileId) async {
    final previous = _refreshFuture;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // Begin a new GET only after any prior request finishes.
      }
    }
    if (_disposed ||
        !_foreground ||
        deviceNetworkState != DeviceNetworkState.available ||
        generation != _generation ||
        active?.id != profileId) {
      return;
    }
    if (_gateway == null) {
      await activate(active!); // Cold/offline profile: recheck server version.
    } else {
      await refresh();
      if (_disposed ||
          generation != _generation ||
          deviceNetworkState != DeviceNetworkState.available) {
        return;
      }
      _startPolling();
      _scheduleAutoRefresh();
    }
  }

  void setForeground(bool visible) {
    if (_disposed) return;
    final resumed = visible && !_foreground;
    _foreground = visible;
    if (visible) {
      if (resumed && deviceNetworkState != DeviceNetworkState.unavailable) {
        if (_requiresRecovery && _gateway == null && active != null) {
          unawaited(activate(active!));
        } else {
          unawaited(refresh());
        }
      }
      _startPolling();
      _scheduleAutoRefresh();
    } else {
      _pollTimer?.cancel();
      _autoRefreshTimer?.cancel();
    }
  }

  void _scheduleAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    final interval = autoRefreshPreference.interval;
    if (_disposed ||
        !_foreground ||
        _gateway == null ||
        active == null ||
        deviceNetworkState == DeviceNetworkState.unavailable ||
        interval == null) {
      return;
    }
    _autoRefreshTimer = Timer.periodic(interval, (_) {
      // Read errors require explicit recovery, not unbounded retries.
      if (!_disposed && _foreground && message == null) {
        unawaited(refresh());
      }
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (_disposed ||
        !_foreground ||
        deviceNetworkState == DeviceNetworkState.unavailable ||
        !tasks.any((task) => task.outcome == OperationOutcome.running)) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_pollTasks());
    });
    unawaited(_pollTasks());
  }

  Future<void> _pollTasks() async {
    if (_disposed ||
        _pollingGeneration == _generation ||
        !_foreground ||
        deviceNetworkState == DeviceNetworkState.unavailable ||
        _gateway == null) {
      return;
    }
    final pending = tasks
        .where((t) => t.outcome == OperationOutcome.running)
        .toList();
    if (pending.isEmpty) return;
    final generation = _generation;
    final networkEpoch = _networkEpoch;
    _pollingGeneration = generation;
    final gateway = _gateway!;
    var finished = false;
    String? authenticationFailure;
    final completedTargets = <String>[];
    try {
      for (final pendingTask in pending) {
        if (generation != _generation ||
            networkEpoch != _networkEpoch ||
            _disposed ||
            !_foreground ||
            deviceNetworkState == DeviceNetworkState.unavailable) {
          return;
        }
        if (DateTime.now().difference(pendingTask.startedAt) >=
            taskVerificationTtl) {
          final index = tasks.indexWhere(
            (task) => task.upid == pendingTask.upid,
          );
          if (index >= 0) {
            tasks[index] = pendingTask.withOutcome(
              OperationOutcome.unknown,
              detail:
                  'Task verification timed out. Verify server task history and guest state before another action.',
            );
          }
          final targets = _taskTargets.remove(pendingTask.upid);
          if (targets != null) {
            _pendingGuestOperations.removeAll(targets);
            _uncertainGuestOperations.addAll(targets);
          }
          finished = true;
          _notify();
          continue;
        }
        try {
          final status = await gateway.taskStatus(pendingTask);
          if (generation != _generation ||
              networkEpoch != _networkEpoch ||
              !_foreground ||
              deviceNetworkState == DeviceNetworkState.unavailable) {
            return;
          }
          if (!status.isDone) continue;
          final index = tasks.indexWhere((t) => t.upid == pendingTask.upid);
          if (index < 0) continue;
          final result = status.succeeded
              ? OperationOutcome.succeeded
              : status.exitStatus == null
              ? OperationOutcome.unknown
              : OperationOutcome.failed;
          tasks[index] = pendingTask.withOutcome(
            result,
            detail:
                status.exitStatus ?? 'Task ended without a known exit status.',
          );
          final targets = _taskTargets.remove(pendingTask.upid);
          if (targets != null) {
            if (result == OperationOutcome.unknown) {
              _uncertainGuestOperations.addAll(targets);
              _pendingGuestOperations.removeAll(targets);
            } else {
              // A terminal UPID is not an authoritative guest-state refresh.
              // Keep writes locked until inventory has reconciled.
              completedTargets.addAll(targets);
            }
          }
          finished = true;
          _notify();
        } on PveFailure catch (error) {
          if (generation != _generation) return;
          if (error.status == 401) {
            message = error.message;
            unawaited(_clearOfflineAfterAuth(generation));
            authenticationFailure = error.message;
            final index = tasks.indexWhere(
              (task) => task.upid == pendingTask.upid,
            );
            if (index >= 0) {
              tasks[index] = pendingTask.withOutcome(
                OperationOutcome.unknown,
                detail:
                    'Task verification lost authentication. Check server task history and guest state before another action.',
              );
            }
            final targets = _taskTargets.remove(pendingTask.upid);
            if (targets != null) {
              _pendingGuestOperations.removeAll(targets);
              _uncertainGuestOperations.addAll(targets);
            }
            finished = true;
            _notify();
            continue;
          }
          if (error.status == 403 || error.status == 404) {
            final index = tasks.indexWhere(
              (task) => task.upid == pendingTask.upid,
            );
            if (index >= 0) {
              tasks[index] = pendingTask.withOutcome(
                OperationOutcome.unknown,
                detail:
                    'Task verification is unavailable. Check server task history and guest state before another action.',
              );
            }
            final targets = _taskTargets.remove(pendingTask.upid);
            if (targets != null) {
              _pendingGuestOperations.removeAll(targets);
              _uncertainGuestOperations.addAll(targets);
            }
            finished = true;
            _notify();
          }
          // Other network/server failures remain unproven and retry until TTL.
        } catch (_) {
          if (generation != _generation ||
              _disposed ||
              !_foreground ||
              deviceNetworkState == DeviceNetworkState.unavailable) {
            return;
          }
          // Unknown client/network failures are not evidence of task outcome.
        }
      }
    } finally {
      if (_pollingGeneration == generation) _pollingGeneration = null;
    }
    if (finished && generation == _generation) {
      // Persist the newly terminal signal before any authoritative refresh.
      // This is deliberately non-closing: timeout/auth/visibility failures are
      // not evidence that any previously observed incident disappeared.
      _incidentTriage.observe(incidents);
      final newOccurrences = _captureIncidentHistory(complete: false);
      final notificationProfileId = active?.id;
      if (notificationProfileId != null && newOccurrences.isNotEmpty) {
        unawaited(
          _maybeDeliverForegroundIncidentNotification(
            newOccurrences,
            profileId: notificationProfileId,
            generation: generation,
          ),
        );
      }
      var reconciled = false;
      if (authenticationFailure == null || completedTargets.isNotEmpty) {
        reconciled = await _refreshAfterTask(generation);
        if (generation != _generation || _disposed) return;
      }
      if (authenticationFailure != null) {
        message = authenticationFailure;
      }
      for (final target in completedTargets) {
        if (reconciled && isInventoryWriteSafe) {
          _pendingGuestOperations.remove(target);
        } else {
          // Reconciliation failed; an operator must check the server before
          // intentionally reconnecting to re-enable the operation.
          _uncertainGuestOperations.add(target);
          _pendingGuestOperations.remove(target);
        }
      }
      _notify();
    }
    if (!tasks.any((task) => task.outcome == OperationOutcome.running)) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  /// Do not reconcile a terminal UPID against a read started before it ended.
  Future<bool> _refreshAfterTask(int generation) async {
    final previousRefresh = _refreshFuture;
    if (previousRefresh != null) await previousRefresh;
    if (generation != _generation || _disposed) return false;
    final previousRevision = _inventoryRevision;
    await refresh();
    return generation == _generation &&
        !_disposed &&
        _inventoryRevision > previousRevision &&
        isInventoryWriteSafe;
  }

  Future<void> deleteProfile(String id) async {
    if (_disposed || !_deletingProfiles.add(id)) return;
    final deletingActiveProfile = active?.id == id;
    if (deletingActiveProfile) {
      // Revoke the in-memory session immediately, before an asynchronous
      // credential deletion could race an in-flight guest preflight.
      _generation++;
      _pollTimer?.cancel();
      _autoRefreshTimer?.cancel();
      _refreshFuture = null;
      _gateway?.close();
      _gateway = null;
      active = null;
      favoriteGuests = <String>{};
      guestSavedViews = [];
      inventory = null;
      cachedOverview = null;
      offlineOverviewEnabled = false;
      storages = [];
      serverTasks = [];
      _retainedServerTaskIncidents = const <CockpitIncident>[];
      _incidentTriage.clear();
      incidentHistory = const <IncidentHistoryEntry>[];
      foregroundNotificationPolicy = const ForegroundNotificationPolicy();
      _lastForegroundNotificationAt = null;
      storageMessage = null;
      serverTaskMessage = null;
      inventoryWarning = null;
      tasks.clear();
      _pendingGuestOperations.clear();
      _uncertainGuestOperations.clear();
      _taskTargets.clear();
      message = null;
      refreshing = false;
      _notify();
    }

    // On deletion failure remain disconnected: failing closed is safer than
    // silently restoring a session whose credential state is uncertain.
    final generation = _generation;
    try {
      await _backgroundCheckScheduler.disable(id, clearPolicy: true);
      await repository.delete(id);
      if (_disposed) return;
      profiles = repository.readProfiles();
      if (deletingActiveProfile &&
          generation == _generation &&
          active == null &&
          profiles.isNotEmpty) {
        await activate(profiles.first);
      }
      _notify();
    } catch (_) {
      if (generation == _generation) {
        message =
            'Could not remove stored connection. Check local secure storage.';
        _notify();
      }
      rethrow;
    } finally {
      _deletingProfiles.remove(id);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _incidentTriage.clear();
    incidentHistory = const <IncidentHistoryEntry>[];
    _generation++;
    _pollTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _refreshFuture = null;
    _gateway?.close();
    super.dispose();
  }
}
