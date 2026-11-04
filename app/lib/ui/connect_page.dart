import 'package:flutter/material.dart';

import '../core/app_controller.dart';

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
      await widget.controller.connect(
        name: alias.text,
        address: endpoint.text,
        tokenId: tokenId.text,
        secret: tokenSecret.text,
      );
      tokenSecret.clear();
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          // Exception messages are sanitized by the API gateway.
          error = e.toString().replaceFirst('FormatException: ', '');
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
    return Scaffold(
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
                          : const Icon(Icons.lock_outline_rounded),
                      label: Text(
                        busy ? 'Verifying connection…' : 'Connect securely',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'TLS certificates and hostnames are verified. Self-signed or private CA certificates must be trusted by Android; certificate bypass is not supported.',
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
    );
  }
}
