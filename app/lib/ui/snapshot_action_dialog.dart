import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

enum GuestSnapshotAction { rollback, delete }

/// Owns its confirmation field until the dialog route is disposed.
///
/// The caller supplies live session and safety checks so a reconnect, guest
/// disappearance or pending mutation expires the confirmation immediately.
class GuestSnapshotActionDialog extends StatefulWidget {
  const GuestSnapshotActionDialog({
    super.key,
    required this.controller,
    required this.isCurrent,
    required this.blockedReason,
    required this.guest,
    required this.snapshot,
    required this.action,
  });

  final AppController controller;
  final bool Function() isCurrent;
  final String? Function() blockedReason;
  final Guest guest;
  final GuestSnapshot snapshot;
  final GuestSnapshotAction action;

  @override
  State<GuestSnapshotActionDialog> createState() =>
      _GuestSnapshotActionDialogState();
}

class _GuestSnapshotActionDialogState extends State<GuestSnapshotActionDialog> {
  final _confirmationController = TextEditingController();

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rollback = widget.action == GuestSnapshotAction.rollback;
    final prefix = rollback ? 'snapshot-rollback' : 'snapshot-delete';
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (!widget.isCurrent()) {
          return AlertDialog(
            title: const Text('Confirmation expired'),
            content: const Text(
              'Connection or guest changed. Reopen the guest from the active '
              'connection before acting on a snapshot.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Close'),
              ),
            ],
          );
        }

        final blocked = widget.blockedReason();
        final matches =
            _confirmationController.text.trim() == widget.snapshot.name;
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          key: Key('$prefix-dialog'),
          title: Text(
            rollback
                ? 'Roll back to "${widget.snapshot.name}"?'
                : 'Delete snapshot "${widget.snapshot.name}"?',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connection: ${widget.controller.active?.name ?? 'Unknown'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.controller.active?.allowInvalidCertificates ==
                    true) ...[
                  const SizedBox(height: 4),
                  Text(
                    'INSECURE: server certificate verification is disabled '
                    'for this connection.',
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '${widget.guest.node} • '
                  '${widget.guest.kind.toUpperCase()} ${widget.guest.vmid} • '
                  '${widget.guest.name}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (widget.snapshot.description != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.snapshot.description!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  rollback
                      ? 'All guest disk and configuration changes made after '
                            'this snapshot will be discarded. The guest must '
                            'remain stopped; VirtHelm does not start it '
                            'afterwards. Snapshots are not backups.'
                      : 'This permanently removes the snapshot point. Proxmox '
                            'may consolidate snapshot data and this cannot be '
                            'undone. Deleting a snapshot does not roll back '
                            'the running guest state.',
                  style: TextStyle(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  rollback
                      ? 'Immediately before one POST, VirtHelm rechecks the '
                            'exact stopped guest, VM.Snapshot.Rollback and a '
                            'fresh complete snapshot list. The mutation is '
                            'never retried automatically.'
                      : 'Immediately before one DELETE, VirtHelm rechecks the '
                            'exact guest, VM.Snapshot and a fresh complete '
                            'snapshot list. The mutation is never retried '
                            'automatically.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (blocked != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    blocked,
                    key: Key('$prefix-blocked'),
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Type ${widget.snapshot.name} to confirm:',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  key: Key('$prefix-confirm-name'),
                  controller: _confirmationController,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Snapshot name',
                    border: OutlineInputBorder(),
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
              key: Key('$prefix-submit'),
              onPressed: blocked == null && matches
                  ? () => Navigator.pop(
                      context,
                      widget.isCurrent() && widget.blockedReason() == null,
                    )
                  : null,
              child: Text(rollback ? 'Roll back snapshot' : 'Delete snapshot'),
            ),
          ],
        );
      },
    );
  }
}
