import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final form = GlobalKey<FormState>();
  final alias = TextEditingController();
  final endpoint = TextEditingController();
  final tokenId = TextEditingController();
  final tokenSecret = TextEditingController();
  String? error;
  bool busy = false;
  bool showSecret = false;
  bool allowInvalidCertificates = false;

  @override
  void dispose() {
    alias.dispose();
    endpoint.dispose();
    tokenId.dispose();
    tokenSecret.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || form.currentState?.validate() != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Normalize before displaying the exact origin being authorized.
      final address = normalizePveEndpoint(endpoint.text);
      if (allowInvalidCertificates) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Disable certificate verification?'),
            content: SingleChildScrollView(
              child: Text(
                'Server: $address\n\n'
                'The server identity will not be verified. An attacker could '
                'steal your API token, read data, or change commands, even on a '
                'local network. HTTPS encryption alone does not prevent this.\n\n'
                'This exception is saved for this connection, including future '
                'sessions. Prefer a trusted certificate and VPN.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Connect without verification'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      await widget.controller.connect(
        name: alias.text,
        address: address,
        tokenId: tokenId.text,
        secret: tokenSecret.text,
        allowInvalidCertificates: allowInvalidCertificates,
      );
      if (!mounted) return;
      tokenSecret.clear();
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          // Plugin/storage exceptions are not necessarily sanitized. Never
          // expose arbitrary exception text from a credential operation.
          error = e is PveFailure
              ? e.message
              : e is FormatException
              ? e.message
              : 'Could not save or open this connection. Check local secure storage and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasProfile = widget.controller.profiles.isNotEmpty;
    final displayedError = error ?? widget.controller.message;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: hasProfile
            ? AppBar(title: const Text('Add Proxmox connection'))
            : null,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          Icons.dns_rounded,
                          size: 38,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Your infrastructure.\nIn your hands.',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800, height: 1.1),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Connect securely to Proxmox VE using a least-privilege API token.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: alias,
                        decoration: const InputDecoration(
                          labelText: 'Connection name',
                          hintText: 'Home Lab',
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Enter a name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: endpoint,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Server URL',
                          hintText: 'https://pve.example:8006',
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter the HTTPS URL'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: tokenId,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'API token identifier',
                          hintText: 'operator@pve!virthelm',
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter the token ID'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: tokenSecret,
                        obscureText: !showSecret,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'API token secret',
                          suffixIcon: IconButton(
                            tooltip: showSecret ? 'Hide token' : 'Show token',
                            onPressed: () =>
                                setState(() => showSecret = !showSecret),
                            icon: Icon(
                              showSecret
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Enter the secret' : null,
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Disable certificate verification'),
                        subtitle: const Text(
                          'Insecure: for self-signed servers or lab use. '
                          'Saved only for this connection; available for any host.',
                        ),
                        value: allowInvalidCertificates,
                        onChanged: busy
                            ? null
                            : (value) => setState(
                                () => allowInvalidCertificates = value,
                              ),
                      ),
                      const SizedBox(height: 16),
                      if (displayedError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            displayedError,
                            style: TextStyle(color: scheme.onErrorContainer),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      FilledButton.icon(
                        onPressed: busy ? null : submit,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                allowInvalidCertificates
                                    ? Icons.warning_amber_rounded
                                    : Icons.lock_outline_rounded,
                              ),
                        label: Text(
                          busy
                              ? 'Checking connection…'
                              : allowInvalidCertificates
                              ? 'Connect (insecure)'
                              : 'Connect securely',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        allowInvalidCertificates
                            ? 'Certificate and hostname verification will be disabled for this connection. Your API token may be exposed to an impersonated server.'
                            : 'TLS certificates and hostnames are verified by default. Use a trusted certificate or securely provisioned private CA.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (!hasProfile) ...[
                        const SizedBox(height: 26),
                        Text(
                          'VirtHelm is an independent, unofficial Proxmox VE client.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
