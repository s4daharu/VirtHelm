import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';

/// Owns its text controller until the dialog route is actually disposed.
class ProvisioningConfirmationDialog extends StatefulWidget {
  const ProvisioningConfirmationDialog({
    super.key,
    required this.controller,
    required this.isCurrent,
    required this.canSubmit,
    required this.vmid,
    required this.title,
    required this.details,
    required this.keyPrefix,
    required this.submitLabel,
  });

  final AppController controller;
  final bool Function() isCurrent;
  final bool Function() canSubmit;
  final int vmid;
  final String title;
  final List<Widget> details;
  final String keyPrefix;
  final String submitLabel;

  @override
  State<ProvisioningConfirmationDialog> createState() =>
      _ProvisioningConfirmationDialogState();
}

class _ProvisioningConfirmationDialogState
    extends State<ProvisioningConfirmationDialog> {
  final _typedController = TextEditingController();

  @override
  void dispose() {
    _typedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (!widget.isCurrent()) {
        return AlertDialog(
          title: const Text('Confirmation expired'),
          content: const Text(
            'Connection or source changed. Reopen the provisioning workflow.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close'),
            ),
          ],
        );
      }
      final allowed = widget.canSubmit();
      final matches = _typedController.text.trim() == widget.vmid.toString();
      return AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...widget.details,
              if (widget.controller.active?.allowInvalidCertificates ==
                  true) ...[
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
              if (!allowed) ...[
                const SizedBox(height: 12),
                const Text(
                  'Live inventory or target availability changed. '
                  'Cancel and refresh before reviewing again.',
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Type VMID ${widget.vmid} to submit:',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              TextField(
                key: Key('${widget.keyPrefix}-confirm-vmid'),
                controller: _typedController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Confirm destination VMID',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('${widget.keyPrefix}-confirm-submit'),
            onPressed: allowed && matches
                ? () => Navigator.pop(
                    context,
                    widget.isCurrent() && widget.canSubmit(),
                  )
                : null,
            child: Text(widget.submitLabel),
          ),
        ],
      );
    },
  );
}
