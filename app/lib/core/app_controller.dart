import 'dart:async';

import 'package:flutter/foundation.dart';

import 'guest_saved_view.dart';
import 'models.dart';
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
  final List<TrackedTask> tasks = [];
  List<StoragePool> storages = [];
  List<RecentServerTask> serverTasks = [];
  Set<String> favoriteGuests = <String>{};
  List<SavedGuestView> guestSavedViews = [];
  String? storageMessage;
  String? serverTaskMessage;
  String? inventoryWarning;
  String? message;
  bool initialized = false;
  bool refreshing = false;
  bool connecting = false;

  PveGateway? _gateway;
  int _generation = 0;
  Timer? _pollTimer;
  int? _pollingGeneration;
  bool _foreground = true;
  bool _disposed = false;
  Future<void>? _refreshFuture;

  // A guest is single-flight across preflight, submission and UPID completion.
  // Unknown outcomes remain blocked for this connection session.
  final Set<String> _pendingGuestOperations = {};
  final Set<String> _uncertainGuestOperations = {};
  final Map<String, String> _taskTargets = {};
  final Set<String> _deletingProfiles = {};

  String _guestKey(Guest guest) => '${guest.kind}:${guest.node}:${guest.vmid}';

  bool isGuestFavorite(Guest guest) =>
      favoriteGuests.contains(_guestKey(guest));

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
      profiles = repository.readProfiles();
      final selected = repository.activeId;
      if (profiles.isNotEmpty) {
        final first = profiles.where((p) => p.id == selected);
        await activate(first.isEmpty ? profiles.first : first.first);
      }
    } catch (_) {
      message = 'Could not load saved connections. Check local secure storage.';
    } finally {
      initialized = true;
      _notify();
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
      await candidate.version();
      _checkConnectionSetup(generation);
      await candidate.inventory(); // A valid token must also access inventory.
      _checkConnectionSetup(generation);
      await repository.save(profile, credential);
      if (_disposed) {
        await _rollbackCanceledConnection(profile.id, previousActiveId);
        throw const PveFailure('Connection setup canceled.');
      }
      profiles = repository.readProfiles();
      if (generation == _generation) {
        await activate(profile);
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

  Future<void> activate(ConnectionProfile profile) async {
    if (_disposed || _deletingProfiles.contains(profile.id)) return;
    final generation = ++_generation;
    _pollTimer?.cancel();
    _refreshFuture = null;
    _gateway?.close();
    _gateway = null;
    active = profile;
    favoriteGuests = repository.readGuestFavorites(profile.id);
    guestSavedViews = repository.readGuestViews(profile.id);
    inventory = null;
    tasks.clear();
    storages = [];
    serverTasks = [];
    storageMessage = null;
    serverTaskMessage = null;
    inventoryWarning = null;
    _pendingGuestOperations.clear();
    _uncertainGuestOperations.clear();
    _taskTargets.clear();
    message = null;
    refreshing = false;
    _notify();
    try {
      final credentials = await repository.vault.retrieve(profile.id);
      if (generation != _generation || _disposed) return;
      if (credentials == null || !credentials.isValid) {
        throw const PveFailure(
          'Saved token unavailable. Remove and add this connection again.',
        );
      }
      _gateway = _factory(profile, credentials);
      await repository.setActive(profile.id);
      if (generation != _generation || _disposed) return;
      await refresh();
      if (generation == _generation && _foreground) _startPolling();
    } catch (e) {
      if (generation == _generation) {
        _gateway?.close();
        _gateway = null;
        inventory = null;
        message = e is PveFailure ? e.message : 'Could not open connection.';
        _notify();
      }
    }
  }

  Future<void> refresh() {
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
    refreshing = true;
    _notify();
    try {
      final next = await gateway.inventory();
      if (generation != _generation) return;
      inventory = next;
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
    } catch (e) {
      if (generation != _generation) return;
      message = e is PveFailure ? e.message : 'Unable to refresh inventory.';
      // Last result is displayed as stale; no stale data may authorize a write.
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
      if (error.status == 401) message = error.message;
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
      serverTasks = result.values;
      serverTaskMessage = _sectionWarning(result, 'server task history');
    } on PveFailure catch (error) {
      if (generation != _generation || _disposed) return;
      if (error.status == 401) message = error.message;
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
    if (_disposed || inventory == null || message != null) return false;
    final age = DateTime.now().difference(inventory!.fetchedAt);
    return age >= Duration.zero && age < const Duration(minutes: 2);
  }

  bool get isInventoryWriteSafe =>
      isInventoryFresh && inventory!.malformedGuestRecords == 0;

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

  void setForeground(bool visible) {
    if (_disposed) return;
    final resumed = visible && !_foreground;
    _foreground = visible;
    if (visible) {
      if (resumed) unawaited(refresh());
      _startPolling();
    } else {
      _pollTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (_disposed ||
        !_foreground ||
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
        _gateway == null) {
      return;
    }
    final pending = tasks
        .where((t) => t.outcome == OperationOutcome.running)
        .toList();
    if (pending.isEmpty) return;
    final generation = _generation;
    _pollingGeneration = generation;
    final gateway = _gateway!;
    var finished = false;
    String? authenticationFailure;
    final completedTargets = <String>[];
    try {
      for (final pendingTask in pending) {
        if (generation != _generation || _disposed || !_foreground) return;
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
          if (generation != _generation || !_foreground) return;
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
          if (generation != _generation || _disposed || !_foreground) return;
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
      _refreshFuture = null;
      _gateway?.close();
      _gateway = null;
      active = null;
      favoriteGuests = <String>{};
      guestSavedViews = [];
      inventory = null;
      storages = [];
      serverTasks = [];
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
    _refreshFuture = null;
    _gateway?.close();
    super.dispose();
  }
}
