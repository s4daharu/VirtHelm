import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/device_connectivity.dart';
import '../core/models.dart';
import 'components.dart';
import 'connect_page.dart';

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({
    super.key,
    required this.controller,
    this.chooserMode = false,
  });

  final AppController controller;
  final bool chooserMode;

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  String? testingProfileId;
  String? removingProfileId;

  Future<void> _openAdd() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConnectPage(controller: widget.controller),
      ),
    );
  }

  Future<void> _openEdit(ConnectionProfile profile) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ConnectPage(controller: widget.controller, profile: profile),
      ),
    );
  }

  Future<void> _activate(ConnectionProfile profile) async {
    await widget.controller.activate(profile);
  }

  Future<void> _test(ConnectionProfile profile) async {
    if (testingProfileId != null || widget.controller.connecting) return;
    setState(() => testingProfileId = profile.id);
    try {
      final result = await widget.controller.testSavedConnection(profile.id);
      if (!mounted) return;
      await _showCheckResult(profile, result);
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is PveFailure
          ? error.message
          : error is FormatException
          ? error.message
          : 'Could not test this connection. Check local secure storage and try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => testingProfileId = null);
    }
  }

  Future<void> _showCheckResult(
    ConnectionProfile profile,
    ConnectionCheckResult result,
  ) async {
    final tls = result.certificateVerificationEnabled
        ? 'Certificate and hostname verification passed.'
        : 'TLS identity verification was disabled for this check.';
    final inventory = result.inventoryAccessible
        ? 'Inventory access confirmed: \${result.nodeCount} node(s), '
              '\${result.guestCount} workload(s).'
        : result.permissionLimited
        ? 'The server responded, but the API token cannot read cluster '
              'inventory. \${result.inventoryMessage ?? 'Check token privileges.'}'
        : 'Inventory access could not be confirmed.';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          result.inventoryAccessible
              ? 'Connection verified'
              : 'Limited connection access',
        ),
        content: SingleChildScrollView(
          child: Text(
            '\${profile.name}\n'
            'PVE \${result.serverVersion}\n\n'
            '\$tls\n\n'
            '\$inventory',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(ConnectionProfile profile) async {
    if (removingProfileId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove connection?'),
        content: Text(
          'Delete \${profile.name} and its locally stored API token. '
          'This does not revoke the token on the Proxmox server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => removingProfileId = profile.id);
    try {
      await widget.controller.deleteProfile(profile.id);
      if (!mounted) return;
      if (widget.controller.profiles.isEmpty &&
          !widget.chooserMode &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove stored connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => removingProfileId = null);
    }
  }

  Widget _stateChip(ConnectionProfile profile) {
    final controller = widget.controller;
    if (controller.active?.id != profile.id) {
      return const Chip(
        avatar: Icon(Icons.bookmark_outline_rounded, size: 17),
        label: Text('Saved'),
      );
    }
    if (controller.deviceNetworkState == DeviceNetworkState.unavailable) {
      return const Chip(
        avatar: Icon(Icons.wifi_off_rounded, size: 17),
        label: Text('Offline'),
      );
    }
    if (controller.message != null) {
      return const Chip(
        avatar: Icon(Icons.warning_amber_rounded, size: 17),
        label: Text('Needs attention'),
      );
    }
    if (controller.inventory == null) {
      return const Chip(
        avatar: Icon(Icons.sync_rounded, size: 17),
        label: Text('Connecting'),
      );
    }
    if (controller.isInventoryFresh) {
      return const Chip(
        avatar: Icon(Icons.check_circle_outline_rounded, size: 17),
        label: Text('Live'),
      );
    }
    return const Chip(
      avatar: Icon(Icons.history_rounded, size: 17),
      label: Text('Stale'),
    );
  }

  Widget _profileCard(ConnectionProfile profile) {
    final controller = widget.controller;
    final active = controller.active?.id == profile.id;
    final testing = testingProfileId == profile.id;
    final removing = removingProfileId == profile.id;
    final disabled = testingProfileId != null ||
        removingProfileId != null ||
        controller.connecting;
    return Card(
      key: ValueKey('connection-card-\${profile.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Icon(
                    active ? Icons.dns_rounded : Icons.dns_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.endpoint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _stateChip(profile),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.info_outline_rounded, size: 17),
                  label: Text(
                    profile.lastServerVersion == null
                        ? 'PVE version not observed'
                        : 'PVE \${profile.lastServerVersion} • last observed',
                  ),
                ),
                Chip(
                  avatar: Icon(
                    profile.allowInvalidCertificates
                        ? Icons.warning_amber_rounded
                        : Icons.verified_user_outlined,
                    size: 17,
                  ),
                  label: Text(
                    profile.allowInvalidCertificates
                        ? 'TLS UNVERIFIED'
                        : 'TLS verification on',
                  ),
                ),
              ],
            ),
            if (active && controller.message != null) ...[
              const SizedBox(height: 12),
              MessageCard(
                text: controller.message!,
                tone: MessageTone.warning,
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!active)
                  FilledButton.tonalIcon(
                    key: ValueKey('connection-use-\${profile.id}'),
                    onPressed: disabled ? null : () => _activate(profile),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Use connection'),
                  ),
                OutlinedButton.icon(
                  key: ValueKey('connection-test-\${profile.id}'),
                  onPressed: disabled ? null : () => _test(profile),
                  icon: testing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined),
                  label: Text(testing ? 'Testing…' : 'Test'),
                ),
                TextButton.icon(
                  key: ValueKey('connection-edit-\${profile.id}'),
                  onPressed: disabled ? null : () => _openEdit(profile),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  key: ValueKey('connection-remove-\${profile.id}'),
                  onPressed: disabled ? null : () => _remove(profile),
                  icon: removing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded),
                  label: Text(removing ? 'Removing…' : 'Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final profiles = widget.controller.profiles;
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.chooserMode,
          title: Text(widget.chooserMode ? 'Choose connection' : 'Connections'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
            children: [
              if (widget.chooserMode) ...[
                const MessageCard(
                  title: 'Choose where to connect',
                  text:
                      'A saved connection exists, but none is selected. '
                      'Choose one explicitly or add another connection.',
                  icon: Icons.hub_outlined,
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      profiles.isEmpty
                          ? 'No saved connections'
                          : '\${profiles.length} saved connection\${profiles.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('connections-add'),
                    onPressed: widget.controller.connecting ? null : _openAdd,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (profiles.isEmpty)
                const EmptyState(
                  icon: Icons.dns_outlined,
                  title: 'No connections yet',
                  body:
                      'Add a Proxmox VE server and verify its API token before use.',
                )
              else
                for (final profile in profiles) ...[
                  _profileCard(profile),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 10),
              Text(
                'Connection tests are read-only. They check the configured '
                'HTTPS origin, PVE version and cluster-inventory permission. '
                'They never submit guest actions.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}
