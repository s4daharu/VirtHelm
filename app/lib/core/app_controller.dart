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

  Future<void> runAction(Guest guest, GuestAction action, {required String profileId}) async {
    final gateway = _gateway;
    final generation = _generation;
    if (active?.id != profileId) {
      throw const PveFailure('Connection changed; return to the guest list before acting.');
    }
    if (gateway == null || active == null || !isInventoryFresh) {
      throw const PveFailure('Refresh live inventory before making changes.');
    }
    if (!action.allowedFor(guest)) {
      throw const PveFailure('This action is not available for the current guest state.');
    }
    final actual = await gateway.guestStatus(guest);
    if (generation != _generation || active?.id != profileId || _disposed) {
      throw const PveFailure('Connection changed; action canceled.');
    }
    if (actual != guest.status) {
      throw const PveFailure('Guest state changed. Refresh and review before retrying.');
    }
    // Exactly one POST. A timeout must never trigger an automatic retry.
    final upid = await gateway.submit(guest, action);
    if (generation != _generation || _disposed) {
      throw const PveFailure(
        'Connection changed after submission. Check server task history.',
        mayHaveExecuted: true,
      );
    }
    tasks.insert(0, TrackedTask(
      upid: upid,
      node: guest.node,
      title: '${action.label} ${guest.name} (${guest.vmid})',
      startedAt: DateTime.now(),
      outcome: OperationOutcome.running,
    ));
    _notify();
    if (_foreground) _startPolling();
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
          finished = true;
          _notify();
        } catch (_) {
          // Network outages are not evidence of task failure or success.
        }
      }
    } finally {
      _polling = false;
    }
    if (finished && generation == _generation) await refresh();
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
