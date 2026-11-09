import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

class QemuCreatePage extends StatefulWidget {
  const QemuCreatePage({
    super.key,
    required this.controller,
    required this.profileId,
    required this.generation,
  });

  final AppController controller;
  final String profileId;
  final int generation;

  @override
  State<QemuCreatePage> createState() => _QemuCreatePageState();
}

class _QemuCreatePageState extends State<QemuCreatePage> {
  late final TextEditingController _vmidController;
  late final TextEditingController _nameController;
  late final TextEditingController _memoryController;
  String? _node;
  int _cores = 2;
  bool _onBoot = false;
  bool _loadingSuggestion = true;
  bool _submitting = false;
  String? _suggestionError;

  bool get _currentSession =>
      widget.controller.active?.id == widget.profileId &&
      widget.controller.connectionGeneration == widget.generation;

  List<String> get _onlineNodes {
    if (!_currentSession) return const [];
    final values = widget.controller.inventory?.nodes
            .where((node) => node.status == 'online')
            .map((node) => node.name)
            .toSet()
            .toList() ??
        <String>[];
    values.sort();
    return values;
  }

  @override
  void initState() {
    super.initState();
    _vmidController = TextEditingController();
    _nameController = TextEditingController();
    _memoryController = TextEditingController(text: '2048');
    final onlineNodes = _onlineNodes;
    _node = onlineNodes.isEmpty ? null : onlineNodes.first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuggestedVmid());
  }

  @override
  void dispose() {
    _vmidController.dispose();
    _nameController.dispose();
    _memoryController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestedVmid() async {
    if (!mounted || !_currentSession) return;
    try {
      final vmid = await widget.controller.suggestQemuCreateVmid(
        profileId: widget.profileId,
        generation: widget.generation,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        _loadingSuggestion = false;
        if (vmid != null && _vmidController.text.trim().isEmpty) {
          _vmidController.text = vmid.toString();
          if (_nameController.text.trim().isEmpty) {
            _nameController.text = 'vm-$vmid';
          }
        } else if (vmid == null) {
          _suggestionError =
              'Could not confirm a suggested VMID. Enter an unused VMID manually.';
        }
      });
    } on PveFailure catch (error) {
      if (!mounted || !_currentSession) return;
      setState(() {
        _loadingSuggestion = false;
        _suggestionError = error.message;
      });
    } catch (_) {
      if (!mounted || !_currentSession) return;
      setState(() {
        _loadingSuggestion = false;
        _suggestionError =
            'Could not load a suggested VMID. Enter an unused VMID manually.';
      });
    }
  }

  QemuCreateRequest? _request() {
    final node = _node;
    final vmid = int.tryParse(_vmidController.text.trim());
    final memory = int.tryParse(_memoryController.text.trim());
    if (node == null || vmid == null || memory == null) return null;
    return QemuCreateRequest(
      node: node,
      vmid: vmid,
      name: _nameController.text,
      cores: _cores,
      memoryMiB: memory,
      onBoot: _onBoot,
    );
  }

  String? _validationError() {
    final node = _node;
    if (node == null) return 'Select an online destination node.';
    if (int.tryParse(_vmidController.text.trim()) == null) {
      return 'Enter a numeric VMID.';
    }
    if (int.tryParse(_memoryController.text.trim()) == null) {
      return 'Enter memory in MiB.';
    }
    return _request()?.validationError;
  }

  bool _nodeStillOnline(String node) => _onlineNodes.contains(node);

  Future<bool> _confirm(QemuCreateRequest request) async {
    final typedController = TextEditingController();
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => StatefulBuilder(
              builder: (context, setDialogState) {
                final matches =
                    typedController.text.trim() == request.vmid.toString();
                final insecure =
                    widget.controller.active?.allowInvalidCertificates == true;
                return AlertDialog(
                  title: const Text('Confirm QEMU VM creation'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Node: ${request.node}\n'
                          'VM: ${request.name.trim()} (VMID ${request.vmid})\n'
                          'CPU: ${request.cores} cores\n'
                          'Memory: ${request.memoryMiB} MiB\n'
                          'Start at boot: ${request.onBoot ? 'Yes' : 'No'}',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'This creates an empty, stopped QEMU VM configuration. '
                          'It does not allocate a disk, attach a network, mount '
                          'installation media, join a pool, enable HA, or start '
                          'the VM.',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Preflight rechecks the online node, clean live '
                          'inventory, destination VMID, and VM.Allocate + '
                          'VM.Config.CPU/Memory/Options before one create POST.',
                        ),
                        if (insecure) ...[
                          const SizedBox(height: 12),
                          Text(
                            'INSECURE: server certificate verification is disabled '
                            'for this connection.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Type VMID ${request.vmid} to submit:',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          key: const Key('qemu-create-confirm-vmid'),
                          controller: typedController,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setDialogState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Confirm destination VMID',
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      key: const Key('qemu-create-confirm-submit'),
                      onPressed: matches
                          ? () => Navigator.pop(dialogContext, true)
                          : null,
                      child: const Text('Create VM'),
                    ),
                  ],
                );
              },
            ),
          ) ??
          false;
    } finally {
      typedController.dispose();
    }
  }

  Future<void> _reviewAndSubmit() async {
    if (_submitting || !_currentSession) return;
    final request = _request();
    final error = _validationError();
    if (request == null || error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Invalid VM create request.')),
      );
      return;
    }
    if (!_nodeStillOnline(request.node)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Destination node is no longer online. Refresh and review again.',
          ),
        ),
      );
      return;
    }
    final confirmed = await _confirm(request.normalized());
    if (!confirmed || !mounted || !_currentSession) return;

    setState(() => _submitting = true);
    try {
      await widget.controller.runQemuCreate(
        request,
        profileId: widget.profileId,
      );
      if (!mounted || !_currentSession) return;
      Navigator.pop(context, true);
    } on PveFailure catch (error) {
      if (!mounted || !_currentSession) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted || !_currentSession) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit QEMU VM creation.')),
      );
    } finally {
      if (mounted && _currentSession) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (!_currentSession) {
        return Scaffold(
          appBar: AppBar(title: const Text('Create VM unavailable')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Connection changed. Reopen the create flow from Guests.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }

      final onlineNodes = _onlineNodes;
      final selectedNode = _node;
      final request = _request();
      final blocked =
          request != null &&
          widget.controller.isProvisioningTargetBlocked(
            'qemu',
            request.node,
            request.vmid,
          );
      final validationError = _validationError();
      final canReview =
          !_submitting &&
          !blocked &&
          selectedNode != null &&
          onlineNodes.contains(selectedNode) &&
          !widget.controller.refreshing &&
          widget.controller.isInventoryWriteSafe &&
          validationError == null;

      return Scaffold(
        appBar: AppBar(title: const Text('Create QEMU VM')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            Text(
              'Empty VM shell',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Create a stopped QEMU configuration with CPU and memory only. '
              'Storage, networking, media, cloud-init, pools, HA and automatic '
              'start remain gated for later reviewed provisioning slices.',
            ),
            const SizedBox(height: 18),
            DropdownMenu<String>(
              key: const Key('qemu-create-node'),
              initialSelection: selectedNode,
              enabled: !_submitting && onlineNodes.isNotEmpty,
              label: const Text('Destination node'),
              expandedInsets: EdgeInsets.zero,
              dropdownMenuEntries: [
                for (final node in onlineNodes)
                  DropdownMenuEntry(value: node, label: node),
              ],
              onSelected: (value) => setState(() => _node = value),
            ),
            if (onlineNodes.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'No online node is available in the current live inventory.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              key: const Key('qemu-create-vmid'),
              controller: _vmidController,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'VMID',
                helperText: _loadingSuggestion
                    ? 'Checking the next free VMID…'
                    : '100–999999999',
                suffixIcon: _loadingSuggestion
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            if (_suggestionError != null) ...[
              const SizedBox(height: 8),
              Text(
                _suggestionError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              key: const Key('qemu-create-name'),
              controller: _nameController,
              enabled: !_submitting,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'VM name',
                helperText:
                    '1–63 letters, numbers, or hyphens; no leading/trailing hyphen',
              ),
            ),
            const SizedBox(height: 14),
            DropdownMenu<int>(
              key: const Key('qemu-create-cores'),
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
            const SizedBox(height: 14),
            TextField(
              key: const Key('qemu-create-memory'),
              controller: _memoryController,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Memory (MiB)',
                helperText: '128–262144 MiB',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('qemu-create-onboot'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Start at boot'),
              subtitle: const Text(
                'Sets the onboot flag only. This wizard never starts the VM.',
              ),
              value: _onBoot,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _onBoot = value),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Safety boundary',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Exact active connection and clean fresh inventory\n'
                      '• Destination node must still be online\n'
                      '• VMID absent locally and free on the server\n'
                      '• VM.Allocate + VM.Config.CPU/Memory/Options\n'
                      '• Exactly one create POST; ambiguous outcomes are locked\n'
                      '• No disk, NIC, storage, ISO, start, HA, pool or restore fields',
                    ),
                  ],
                ),
              ),
            ),
            if (blocked) ...[
              const SizedBox(height: 12),
              Text(
                'A task is pending or an earlier create outcome is uncertain for '
                'this node and VMID. Check Tasks before another submission.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (validationError != null) ...[
              const SizedBox(height: 12),
              Text(
                validationError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('qemu-create-review-submit'),
              onPressed: canReview ? _reviewAndSubmit : null,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_submitting ? 'Submitting…' : 'Review and create'),
            ),
          ],
        ),
      );
    },
  );
}
