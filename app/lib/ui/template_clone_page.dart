import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

class TemplateClonePage extends StatefulWidget {
  const TemplateClonePage({
    super.key,
    required this.controller,
    required this.source,
    required this.profileId,
    required this.generation,
  });

  final AppController controller;
  final Guest source;
  final String profileId;
  final int generation;

  @override
  State<TemplateClonePage> createState() => _TemplateClonePageState();
}

class _TemplateClonePageState extends State<TemplateClonePage> {
  late final TextEditingController _vmidController;
  late final TextEditingController _nameController;
  bool _loadingSuggestion = true;
  bool _submitting = false;
  String? _suggestionError;

  bool get _currentSession =>
      widget.controller.active?.id == widget.profileId &&
      widget.controller.connectionGeneration == widget.generation;

  Guest? get _currentSource {
    if (!_currentSession) return null;
    final inventory = widget.controller.inventory;
    if (inventory == null) return null;
    final matches = inventory.guests.where(
      (guest) =>
          guest.node == widget.source.node &&
          guest.kind == widget.source.kind &&
          guest.vmid == widget.source.vmid &&
          guest.isTemplate,
    );
    return matches.length == 1 ? matches.single : null;
  }

  @override
  void initState() {
    super.initState();
    _vmidController = TextEditingController();
    final baseName = widget.source.name.trim();
    final suggestedName = baseName.length <= 58 ? '${baseName}-copy' : '';
    _nameController = TextEditingController(text: suggestedName);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuggestedVmid());
  }

  @override
  void dispose() {
    _vmidController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestedVmid() async {
    final source = _currentSource;
    if (!mounted || source == null) {
      if (mounted) setState(() => _loadingSuggestion = false);
      return;
    }
    try {
      final vmid = await widget.controller.suggestTemplateCloneVmid(
        profileId: widget.profileId,
        generation: widget.generation,
        source: source,
      );
      if (!mounted || !_currentSession) return;
      setState(() {
        _loadingSuggestion = false;
        if (vmid != null && _vmidController.text.trim().isEmpty) {
          _vmidController.text = vmid.toString();
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

  GuestCloneRequest? _request() {
    final vmid = int.tryParse(_vmidController.text.trim());
    if (vmid == null) return null;
    return GuestCloneRequest(newVmid: vmid, name: _nameController.text);
  }

  String? _validationError() {
    final request = _request();
    if (request == null) return 'Enter a numeric VMID.';
    return request.validationError;
  }

  Future<bool> _confirm(Guest source, GuestCloneRequest request) async {
    final typedController = TextEditingController();
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => StatefulBuilder(
              builder: (context, setDialogState) {
                final matches =
                    typedController.text.trim() == request.newVmid.toString();
                final insecure =
                    widget.controller.active?.allowInvalidCertificates == true;
                return AlertDialog(
                  title: const Text('Confirm full template clone'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Source: ${source.kind.toUpperCase()} ${source.vmid} '
                          'on ${source.node}\n'
                          'Destination: ${request.name.trim()} '
                          '(VMID ${request.newVmid})\n\n'
                          'VirtHelm will request one full clone on the same node. '
                          'Proxmox will choose the destination storage using its '
                          'default clone behavior.',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Preflight checks VM.Clone on the source, VM.Allocate '
                          'on the destination VMID, a fresh clean inventory, and '
                          'server-side VMID availability. Proxmox remains the '
                          'final authority for datastore and network permissions.',
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
                          'Type VMID ${request.newVmid} to submit:',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          key: const Key('clone-confirm-vmid'),
                          controller: typedController,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                      key: const Key('clone-confirm-submit'),
                      onPressed: matches
                          ? () => Navigator.pop(dialogContext, true)
                          : null,
                      child: const Text('Submit clone'),
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
    final source = _currentSource;
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Template is no longer current. Refresh and reopen it.'),
        ),
      );
      return;
    }
    final error = _validationError();
    final request = _request();
    if (error != null || request == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Invalid clone request.')),
      );
      return;
    }
    final confirmed = await _confirm(source, request.normalized());
    if (!confirmed || !mounted || !_currentSession) return;

    setState(() => _submitting = true);
    try {
      await widget.controller.runTemplateClone(
        source,
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
        const SnackBar(content: Text('Could not submit template clone.')),
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
      if (!_currentSession || _currentSource == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Clone unavailable')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Connection or template inventory changed. Reopen the template '
                'from the active connection.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }

      final source = _currentSource!;
      final blocked = widget.controller.isGuestActionBlocked(source);
      final canReview =
          !_submitting &&
          !blocked &&
          !widget.controller.refreshing &&
          widget.controller.isInventoryWriteSafe;
      return Scaffold(
        appBar: AppBar(title: const Text('Clone template')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.copy_all_rounded),
                title: Text(source.name),
                subtitle: Text(
                  '${source.kind.toUpperCase()} template • VMID ${source.vmid} • '
                  '${source.node}',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Full same-node clone',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'This reviewed first provisioning slice creates a full clone from '
              'the selected template. Linked clones, cross-node targets, explicit '
              'storage placement, create-from-scratch, and migration remain gated.',
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('clone-vmid-field'),
              controller: _vmidController,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Destination VMID',
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
              key: const Key('clone-name-field'),
              controller: _nameController,
              enabled: !_submitting,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (canReview) _reviewAndSubmit();
              },
              decoration: InputDecoration(
                labelText: source.kind == 'lxc' ? 'Hostname' : 'Name',
                helperText:
                    '1–63 letters, numbers, or hyphens; no leading/trailing hyphen',
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Safety preflight',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Fresh clean inventory and exact template identity\n'
                      '• Destination VMID absent locally and free on the server\n'
                      '• VM.Clone on the source template\n'
                      '• VM.Allocate on the destination VMID\n'
                      '• Exactly one clone POST; ambiguous outcomes are locked',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Datastore.AllocateSpace and SDN.Use can also be required '
                      'by Proxmox depending on the template. This initial wizard '
                      'does not claim those checks; a server denial is shown '
                      'without retrying the write.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (blocked) ...[
              const SizedBox(height: 12),
              Text(
                'A task is pending or an earlier outcome is uncertain. Check Tasks '
                'before another clone.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('clone-review-submit'),
              onPressed: canReview ? _reviewAndSubmit : null,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_submitting ? 'Submitting…' : 'Review and clone'),
            ),
          ],
        ),
      );
    },
  );
}
