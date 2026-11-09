import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'provisioning_confirmation_dialog.dart';

class LxcCreatePage extends StatefulWidget {
  const LxcCreatePage({
    super.key,
    required this.controller,
    required this.profileId,
    required this.generation,
  });

  final AppController controller;
  final String profileId;
  final int generation;

  @override
  State<LxcCreatePage> createState() => _LxcCreatePageState();
}

class _LxcCreatePageState extends State<LxcCreatePage> {
  final _vmid = TextEditingController();
  final _hostname = TextEditingController();
  final _memory = TextEditingController(text: '512');
  String? _node;
  String? _template;
  String? _storage;
  LxcCreateOptions? _options;
  int _cores = 2;
  bool _onBoot = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  bool get _current =>
      widget.controller.active?.id == widget.profileId &&
      widget.controller.connectionGeneration == widget.generation;

  List<String> get _nodes {
    if (!_current) return const <String>[];
    final result =
        widget.controller.inventory?.nodes
            .where((node) => node.status == 'online')
            .map((node) => node.name)
            .toSet()
            .toList() ??
        <String>[];
    result.sort();
    return result;
  }

  @override
  void initState() {
    super.initState();
    final nodes = _nodes;
    _node = nodes.isEmpty ? null : nodes.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
  }

  @override
  void dispose() {
    _vmid.dispose();
    _hostname.dispose();
    _memory.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (!_current) return;
    try {
      final suggested = await widget.controller.suggestLxcCreateVmid(
        profileId: widget.profileId,
        generation: widget.generation,
      );
      if (mounted && _current && _vmid.text.isEmpty && suggested != null) {
        _vmid.text = '$suggested';
        _hostname.text = 'ct-$suggested';
      }
      final node = _node;
      if (node != null) await _loadOptions(node);
      if (mounted && _current) setState(() => _loading = false);
    } on PveFailure catch (error) {
      if (mounted && _current) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    }
  }

  Future<void> _loadOptions(String node) async {
    if (!_current) return;
    setState(() {
      _loading = true;
      _error = null;
      _options = null;
      _template = null;
      _storage = null;
    });
    try {
      final options = await widget.controller.inspectLxcCreateOptions(
        profileId: widget.profileId,
        generation: widget.generation,
        node: node,
      );
      if (!mounted || !_current || _node != node) return;
      setState(() {
        _loading = false;
        _options = options;
        if (options == null) {
          _error = 'Template and storage choices are unavailable.';
        } else {
          _template =
              options.templates.isEmpty ? null : options.templates.first.volid;
          _storage = options.rootfsStorages.isEmpty
              ? null
              : options.rootfsStorages.first;
          if (options.incomplete ||
              options.templates.isEmpty ||
              options.rootfsStorages.isEmpty) {
            _error =
                'A clean vztmpl + rootdir discovery is required before creation.';
          }
        }
      });
    } on PveFailure catch (error) {
      if (mounted && _current && _node == node) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    }
  }

  LxcCreateRequest? _request() {
    final node = _node;
    final template = _template;
    final storage = _storage;
    final vmid = int.tryParse(_vmid.text.trim());
    final memory = int.tryParse(_memory.text.trim());
    if (node == null ||
        template == null ||
        storage == null ||
        vmid == null ||
        memory == null) {
      return null;
    }
    return LxcCreateRequest(
      node: node,
      vmid: vmid,
      hostname: _hostname.text,
      cores: _cores,
      memoryMiB: memory,
      templateVolid: template,
      rootfsStorage: storage,
      onBoot: _onBoot,
    );
  }

  String? _validation() {
    if (int.tryParse(_vmid.text.trim()) == null) return 'Enter a numeric VMID.';
    if (int.tryParse(_memory.text.trim()) == null) {
      return 'Enter memory in MiB.';
    }
    return _request()?.validationError ??
        (_template == null
            ? 'Select a container template.'
            : _storage == null
            ? 'Select root filesystem storage.'
            : null);
  }

  Future<void> _submit() async {
    if (_submitting || !_current) return;
    final request = _request()?.normalized();
    final error = _validation();
    if (request == null || error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Invalid container request.')),
      );
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ProvisioningConfirmationDialog(
            controller: widget.controller,
            isCurrent: () => mounted && _current,
            canSubmit: () =>
                widget.controller.isInventoryWriteSafe &&
                !widget.controller.refreshing &&
                _nodes.contains(request.node) &&
                (_options?.supports(request) ?? false) &&
                !widget.controller.isProvisioningTargetBlocked(
                  'lxc',
                  request.node,
                  request.vmid,
                ),
            vmid: request.vmid,
            title: 'Confirm LXC container creation',
            keyPrefix: 'lxc-create',
            submitLabel: 'Create container',
            details: [
              Text(
                'Node: ${request.node}\n'
                'Container: ${request.hostname} (${request.vmid})\n'
                'Template: ${request.templateVolid}\n'
                'Rootfs storage: ${request.rootfsStorage}\n'
                'CPU: ${request.cores} - Memory: ${request.memoryMiB} MiB',
              ),
              const SizedBox(height: 12),
              const Text(
                'Creates an unprivileged container with Proxmox's default 4 GiB '
                'rootfs. No password, SSH key, NIC, pool, HA, restore input or '
                'start-after-create option is sent.',
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted || !_current) return;
    setState(() => _submitting = true);
    try {
      await widget.controller.runLxcCreate(
        request,
        profileId: widget.profileId,
        generation: widget.generation,
      );
      if (mounted && _current) Navigator.pop(context, true);
    } on PveFailure catch (error) {
      if (mounted && _current) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted && _current) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (!_current) {
        return Scaffold(
          appBar: AppBar(title: const Text('Create container unavailable')),
          body: const Center(
            child: Text('Connection changed. Reopen creation from Guests.'),
          ),
        );
      }
      final nodes = _nodes;
      final request = _request();
      final blocked =
          request != null &&
          widget.controller.isProvisioningTargetBlocked(
            'lxc',
            request.node,
            request.vmid,
          );
      final validation = _validation();
      final canReview =
          !_loading &&
          !_submitting &&
          !blocked &&
          widget.controller.isInventoryWriteSafe &&
          !widget.controller.refreshing &&
          (_options?.incomplete == false) &&
          validation == null;

      return Scaffold(
        appBar: AppBar(title: const Text('Create LXC container')),
        body: ListView(
          key: const Key('lxc-create-list'),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            Text(
              'Unprivileged container',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Use a discovered vztmpl image and rootdir-capable storage. '
              'Privileged mode and richer provisioning remain gated.',
            ),
            const SizedBox(height: 16),
            DropdownMenu<String>(
              key: const Key('lxc-create-node'),
              initialSelection: _node,
              enabled: !_submitting && nodes.isNotEmpty,
              label: const Text('Destination node'),
              expandedInsets: EdgeInsets.zero,
              dropdownMenuEntries: [
                for (final node in nodes)
                  DropdownMenuEntry(value: node, label: node),
              ],
              onSelected: (value) {
                if (value == null || value == _node) return;
                setState(() => _node = value);
                unawaited(_loadOptions(value));
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('lxc-create-vmid'),
              controller: _vmid,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'VMID',
                helperText: '100-999999999',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('lxc-create-hostname'),
              controller: _hostname,
              enabled: !_submitting,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Hostname',
                helperText: 'Letters, numbers, and hyphens only',
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator()
            else ...[
              DropdownMenu<String>(
                key: ValueKey('lxc-create-template-${_node ?? 'none'}'),
                initialSelection: _template,
                enabled:
                    !_submitting && (_options?.templates.isNotEmpty ?? false),
                label: const Text('OS template'),
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [
                  for (final template in _options?.templates ?? const <LxcTemplate>[])
                    DropdownMenuEntry(
                      value: template.volid,
                      label: '${template.displayName} - ${template.storage}',
                    ),
                ],
                onSelected: (value) => setState(() => _template = value),
              ),
              const SizedBox(height: 12),
              DropdownMenu<String>(
                key: ValueKey('lxc-create-rootfs-${_node ?? 'none'}'),
                initialSelection: _storage,
                enabled: !_submitting &&
                    (_options?.rootfsStorages.isNotEmpty ?? false),
                label: const Text('Root filesystem storage'),
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [
                  for (final storage in _options?.rootfsStorages ?? const <String>[])
                    DropdownMenuEntry(value: storage, label: storage),
                ],
                onSelected: (value) => setState(() => _storage = value),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            DropdownMenu<int>(
              key: const Key('lxc-create-cores'),
              initialSelection: _cores,
              enabled: !_submitting,
              label: const Text('CPU cores'),
              expandedInsets: EdgeInsets.zero,
              dropdownMenuEntries: const [
                DropdownMenuEntry(value: 1, label: '1'),
                DropdownMenuEntry(value: 2, label: '2'),
                DropdownMenuEntry(value: 4, label: '4'),
                DropdownMenuEntry(value: 8, label: '8'),
                DropdownMenuEntry(value: 16, label: '16'),
                DropdownMenuEntry(value: 32, label: '32'),
                DropdownMenuEntry(value: 64, label: '64'),
              ],
              onSelected: (value) {
                if (value != null) setState(() => _cores = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('lxc-create-memory'),
              controller: _memory,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Memory (MiB)',
                helperText: '128-262144 MiB',
              ),
            ),
            SwitchListTile(
              key: const Key('lxc-create-onboot'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Start at boot'),
              subtitle: const Text('Sets onboot only; creation stays stopped.'),
              value: _onBoot,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _onBoot = value),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: const Text(
                  'Safety: fresh clean inventory, live template/storage '
                  'revalidation, cluster-wide VMID reservation, destination + '
                  'storage ACL checks, one POST, uncertain-outcome lockout.',
                ),
              ),
            ),
            if (blocked || validation != null) ...[
              const SizedBox(height: 8),
              Text(
                blocked
                    ? 'This VMID has a pending or uncertain provisioning operation.'
                    : validation!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('lxc-create-review-submit'),
              onPressed: canReview ? _submit : null,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_submitting ? 'Submitting...' : 'Review and create'),
            ),
          ],
        ),
      );
    },
  );
}
