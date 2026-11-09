import 'dart:async';

import 'package:flutter/foundation.dart';

import 'alert_rules.dart';
import 'app_preferences.dart';
import 'device_connectivity.dart';
import 'guest_saved_view.dart';
import 'incident_center.dart';
import 'models.dart';
import 'offline_overview.dart';
import 'profile_repository.dart';
import 'pve_api.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    GatewayFactory? gatewayFactory,
    this.taskVerificationTtl = const Duration(minutes: 15),
  }) : _factory =
           gatewayFactory ??
           ((profile, credentials) => DioPveGateway(profile, credentials));

  final ProfileRepository repository;
  final GatewayFactory _factory;
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

  List<CockpitIncident> get incidents => buildCockpitIncidents(
    inventory: inventory,
    serverTasks: serverTasks,
    sessionTasks: tasks,
    retainedTaskIncidents: _retainedServerTaskIncidents,
    foregroundRuleIncidents: _thresholdAlertEngine.incidents,
  );
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
  final Map<String, String> _taskTargets = {};
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

  Future<int?> suggestTemplateCloneVmid({
    required String profileId,
    required int generation,
    required Guest source,
  }) async {
    final gateway = _gateway;
    final GuestCloneGateway? cloneGateway = gateway is GuestCloneGateway
        ? gateway
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

  String _guestKey(Guest guest) => '${guest.kind}:${guest.node}:${guest.vmid}';

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
    final key = _guestKey(guest);
    return _pendingGuestOperations.contains(key) ||
        _uncertainGuestOperations.contains(key);
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
      await repository.update(validatedProfile, credential);
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
    _thresholdAlertEngine.clear();
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

  Future<void> runTemplateClone(
    Guest source,
    GuestCloneRequest request, {
    required String profileId,
  }) async {
    final gateway = _gateway;
    final GuestCloneGateway? cloneGateway = gateway is GuestCloneGateway
        ? gateway
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
    if (_uncertainGuestOperations.contains(key)) {
      throw const PveFailure(
        'An earlier clone has an unknown outcome. Verify server task history '
        'and inventory before reconnecting and trying again.',
        mayHaveExecuted: true,
      );
    }
    if (_pendingGuestOperations.contains(key)) {
      throw const PveFailure(
        'An operation is already pending for this template. Check Tasks.',
      );
    }

    _pendingGuestOperations.add(key);
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
      _taskTargets[upid] = key;
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
        _uncertainGuestOperations.add(key);
      }
      rethrow;
    } finally {
      if (generation == _generation && !_taskTargets.containsValue(key)) {
        _pendingGuestOperations.remove(key);
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
    if (_uncertainGuestOperations.contains(key)) {
      throw const PveFailure(
        'An earlier action has an unknown outcome. Verify the guest and '
        'server task history before reconnecting and trying again.',
        mayHaveExecuted: true,
      );
    }
    if (_pendingGuestOperations.contains(key)) {
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
      _taskTargets[upid] = key;
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
      if (generation == _generation && !_taskTargets.containsValue(key)) {
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
          final target = _taskTargets.remove(pendingTask.upid);
          if (target != null) {
            _pendingGuestOperations.remove(target);
            _uncertainGuestOperations.add(target);
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
          final target = _taskTargets.remove(pendingTask.upid);
          if (target != null) {
            if (result == OperationOutcome.unknown) {
              _uncertainGuestOperations.add(target);
              _pendingGuestOperations.remove(target);
            } else {
              // A terminal UPID is not an authoritative guest-state refresh.
              // Keep writes locked until inventory has reconciled.
              completedTargets.add(target);
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
            final target = _taskTargets.remove(pendingTask.upid);
            if (target != null) {
              _pendingGuestOperations.remove(target);
              _uncertainGuestOperations.add(target);
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
            final target = _taskTargets.remove(pendingTask.upid);
            if (target != null) {
              _pendingGuestOperations.remove(target);
              _uncertainGuestOperations.add(target);
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
      if (authenticationFailure == null || completedTargets.isNotEmpty) {
        await _refreshAfterTask(generation);
        if (generation != _generation || _disposed) return;
      }
      if (authenticationFailure != null) {
        message = authenticationFailure;
      }
      for (final target in completedTargets) {
        if (isInventoryFresh) {
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
  Future<void> _refreshAfterTask(int generation) async {
    final previousRefresh = _refreshFuture;
    if (previousRefresh != null) await previousRefresh;
    if (generation != _generation || _disposed) return;
    await refresh();
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
    _generation++;
    _pollTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _refreshFuture = null;
    _gateway?.close();
    super.dispose();
  }
}
