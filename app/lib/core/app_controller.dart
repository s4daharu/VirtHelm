import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'profile_repository.dart';
import 'pve_api.dart';

class AppController extends ChangeNotifier {
  AppController({required this.repository, GatewayFactory? gatewayFactory})
      : _factory = gatewayFactory ??
            ((profile, credentials) => DioPveGateway(profile, credentials));

  final ProfileRepository repository;
  final GatewayFactory _factory;

  List<ConnectionProfile> profiles = [];
  ConnectionProfile? active;
  Inventory? inventory;
  final List<TrackedTask> tasks = [];
  String? message;
  bool initialized = false;
  bool refreshing = false;
  bool connecting = false;

  PveGateway? _gateway;
  int _generation = 0;
  Timer? _pollTimer;
  bool _polling = false;
  bool _foreground = true;
  bool _disposed = false;

  // A guest is single-flight across preflight, submission and UPID completion.
  // Unknown outcomes remain blocked for this connection session.
  final Set<String> _pendingGuestOperations = {};
  final Set<String> _uncertainGuestOperations = {};
  final Map<String, String> _taskTargets = {};

  String _guestKey(Guest guest) =>
      '${guest.kind}:${guest.node}:${guest.vmid}';

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
  }) async {
    if (connecting) return;
    final profile = ConnectionProfile.create(name: name, address: address);
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
      await candidate.inventory(); // A valid token must also access inventory.
      await repository.save(profile, credential);
      profiles = repository.readProfiles();
      await activate(profile);
    } finally {
      candidate?.close();
      connecting = false;
      _notify();
    }
  }

  Future<void> activate(ConnectionProfile profile) async {
    final generation = ++_generation;
    _pollTimer?.cancel();
    _gateway?.close();
    _gateway = null;
    active = profile;
    inventory = null;
    tasks.clear();
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
        throw const PveFailure('Saved token unavailable. Remove and add this connection again.');
      }
      _gateway = _factory(profile, credentials);
      await repository.setActive(profile.id);
      await refresh();
      if (generation == _generation && _foreground) _startPolling();
    } catch (e) {
      if (generation == _generation) {
        message = e is PveFailure ? e.message : 'Could not open connection.';
        _notify();
      }
    }
  }

  Future<void> refresh() async {
    final gateway = _gateway;
    if (gateway == null) return;
    final generation = _generation;
    refreshing = true;
    _notify();
    try {
      final next = await gateway.inventory();
      if (generation != _generation) return;
      inventory = next;
      message = null;
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

  bool get isInventoryFresh =>
      inventory != null &&
      message == null &&
      DateTime.now().difference(inventory!.fetchedAt) < const Duration(minutes: 2);

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
    if (gateway == null || !isInventoryFresh || refreshing) {
      throw const PveFailure('Refresh live inventory before making changes.');
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
      if (generation != _generation || active?.id != profileId || _disposed) {
        throw const PveFailure('Connection changed; action canceled.');
      }
      if (!identical(snapshot, inventory) ||
          refreshing ||
          !isInventoryFresh) {
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
    _foreground = visible;
    if (visible) {
      _startPolling();
    } else {
      _pollTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollTasks();
    });
    if (tasks.any((task) => task.outcome == OperationOutcome.running)) {
      _pollTasks();
    }
  }

  Future<void> _pollTasks() async {
    if (_polling || !_foreground || _gateway == null) return;
    final pending = tasks.where((t) => t.outcome == OperationOutcome.running).toList();
    if (pending.isEmpty) return;
    _polling = true;
    final generation = _generation;
    final gateway = _gateway!;
    var finished = false;
    final completedTargets = <String>[];
    try {
      for (final pendingTask in pending) {
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
            detail: status.exitStatus ?? 'Task ended without a known exit status.',
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
        } catch (_) {
          // Network outages are not evidence of task failure or success.
        }
      }
    } finally {
      _polling = false;
    }
    if (finished && generation == _generation) {
      await refresh();
      if (generation != _generation || _disposed) return;
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
  }

  Future<void> deleteProfile(String id) async {
    await repository.delete(id);
    profiles = repository.readProfiles();
    if (active?.id == id) {
      _generation++;
      _pollTimer?.cancel();
      _gateway?.close();
      _gateway = null;
      active = null;
      inventory = null;
      tasks.clear();
      _pendingGuestOperations.clear();
      _uncertainGuestOperations.clear();
      _taskTargets.clear();
      message = null;
      if (profiles.isNotEmpty) await activate(profiles.first);
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _pollTimer?.cancel();
    _gateway?.close();
    super.dispose();
  }
}
