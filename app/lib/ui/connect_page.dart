import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'components.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.controller, this.profile});

  final AppController controller;
  final ConnectionProfile? profile;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final serverForm = GlobalKey<FormState>();
  final credentialForm = GlobalKey<FormState>();
  final alias = TextEditingController();
  final endpoint = TextEditingController();
  final tokenId = TextEditingController();
  final tokenSecret = TextEditingController();

  int step = 0;
  String? error;
  bool busy = false;
  bool showSecret = false;
  bool allowInvalidCertificates = false;
  ConnectionCheckResult? checkResult;

  bool get editing => widget.profile != null;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    if (profile != null) {
      alias.text = profile.name;
      endpoint.text = profile.endpoint;
      allowInvalidCertificates = profile.allowInvalidCertificates;
    }
  }

  @override
  void dispose() {
    alias.dispose();
    endpoint.dispose();
    tokenId.dispose();
    tokenSecret.dispose();
    super.dispose();
  }

  String? _nameError(String? value) =>
      value == null || value.trim().isEmpty ? 'Enter a name' : null;

  String? _endpointError(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter the HTTPS URL';
    try {
      normalizePveEndpoint(value);
      return null;
    } on FormatException catch (caught) {
      return caught.message;
    }
  }

  String? _tokenIdError(String? value) {
    final id = value?.trim() ?? '';
    if (!editing) return id.isEmpty ? 'Enter the token ID' : null;
    if (id.isEmpty && tokenSecret.text.isEmpty) return null;
    return id.isEmpty ? 'Enter the token ID or clear the token secret' : null;
  }

  String? _tokenSecretError(String? value) {
    final secret = value ?? '';
    if (!editing) return secret.isEmpty ? 'Enter the secret' : null;
    if (secret.isEmpty && tokenId.text.trim().isEmpty) return null;
    return secret.isEmpty ? 'Enter the secret or clear the token ID' : null;
  }

  String _errorMessage(Object caught) => caught is PveFailure
      ? caught.message
      : caught is FormatException
      ? caught.message
      : 'Could not save or open this connection. Check local secure storage and try again.';

  void _invalidateCheck([String? _]) {
    if (checkResult == null && error == null) return;
    setState(() {
      checkResult = null;
      error = null;
    });
  }

  void _next() {
    if (busy) return;
    if (step == 0) {
      if (serverForm.currentState?.validate() != true) return;
      setState(() {
        step = 1;
        error = null;
        checkResult = null;
      });
      return;
    }
    if (step == 1) {
      if (credentialForm.currentState?.validate() != true) return;
      setState(() {
        step = 2;
        error = null;
        checkResult = null;
      });
    }
  }

  void _back() {
    if (busy || step == 0) return;
    setState(() {
      step--;
      error = null;
      checkResult = null;
    });
  }

  Future<bool> _confirmInsecureAttempt() async {
    if (!allowInvalidCertificates) return true;
    final address = normalizePveEndpoint(endpoint.text);
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
    return confirmed == true;
  }

  Future<void> _runCheck() async {
    if (busy || step != 2) return;
    if (!await _confirmInsecureAttempt() || !mounted) return;
    setState(() {
      busy = true;
      error = null;
      checkResult = null;
    });
    try {
      final result = await widget.controller.verifyConnectionConfiguration(
        existingProfileId: widget.profile?.id,
        name: alias.text,
        address: endpoint.text,
        tokenId: tokenId.text,
        secret: tokenSecret.text,
        allowInvalidCertificates: allowInvalidCertificates,
      );
      if (!mounted) return;
      setState(() => checkResult = result);
    } catch (caught) {
      if (mounted) setState(() => error = _errorMessage(caught));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy || checkResult?.inventoryAccessible != true) return;
    if (!await _confirmInsecureAttempt() || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final address = normalizePveEndpoint(endpoint.text);
      if (editing) {
        await widget.controller.updateConnection(
          profileId: widget.profile!.id,
          name: alias.text,
          address: address,
          tokenId: tokenId.text,
          secret: tokenSecret.text,
          allowInvalidCertificates: allowInvalidCertificates,
        );
      } else {
        await widget.controller.connect(
          name: alias.text,
          address: address,
          tokenId: tokenId.text,
          secret: tokenSecret.text,
          allowInvalidCertificates: allowInvalidCertificates,
        );
      }
      if (!mounted) return;
      tokenSecret.clear();
      if (Navigator.of(context).canPop()) {
        setState(() => busy = false);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (caught) {
      if (mounted) {
        setState(() {
          error = _errorMessage(caught);
          checkResult = null;
        });
      }
    } finally {
      if (mounted && busy) setState(() => busy = false);
    }
  }

  Widget _progress(BuildContext context) {
    const labels = ['Server', 'API token', 'Verify'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step ${step + 1} of 3 • ${labels[step]}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (step + 1) / 3),
      ],
    );
  }

  Widget _serverStep(BuildContext context) => Form(
    key: serverForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Server',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Name the connection and enter the exact HTTPS origin you trust.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const Key('connection-name'),
          controller: alias,
          decoration: const InputDecoration(
            labelText: 'Connection name',
            hintText: 'Home Lab',
          ),
          textInputAction: TextInputAction.next,
          validator: _nameError,
          onChanged: _invalidateCheck,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('connection-url'),
          controller: endpoint,
          keyboardType: TextInputType.url,
          autocorrect: false,
          autofillHints: const [AutofillHints.url],
          decoration: const InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://pve.example:8006',
          ),
          textInputAction: TextInputAction.done,
          validator: _endpointError,
          onChanged: _invalidateCheck,
          onFieldSubmitted: (_) => _next(),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('connection-tls-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Disable certificate verification'),
          subtitle: const Text(
            'Insecure: intended only for a deliberately trusted lab origin. '
            'A successful check will not prove the server identity.',
          ),
          value: allowInvalidCertificates,
          onChanged: busy
              ? null
              : (value) => setState(() {
                  allowInvalidCertificates = value;
                  checkResult = null;
                  error = null;
                }),
        ),
      ],
    ),
  );

  Widget _credentialStep(BuildContext context) => Form(
    key: credentialForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'API token',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          editing
              ? 'Leave both token fields blank to keep the encrypted saved token.'
              : 'Use a least-privilege Proxmox API token. The secret is stored in Android secure storage.',
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const Key('connection-token-id'),
          controller: tokenId,
          autocorrect: false,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(
            labelText: 'API token identifier',
            hintText: 'operator@pve!virthelm',
          ),
          textInputAction: TextInputAction.next,
          validator: _tokenIdError,
          onChanged: _invalidateCheck,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('connection-token-secret'),
          controller: tokenSecret,
          obscureText: !showSecret,
          enableSuggestions: false,
          autocorrect: false,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _next(),
          decoration: InputDecoration(
            labelText: 'API token secret',
            suffixIcon: IconButton(
              tooltip: showSecret ? 'Hide token' : 'Show token',
              onPressed: () => setState(() => showSecret = !showSecret),
              icon: Icon(
                showSecret
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          validator: _tokenSecretError,
          onChanged: _invalidateCheck,
        ),
        const SizedBox(height: 16),
        const MessageCard(
          icon: Icons.shield_outlined,
          title: 'Credential handling',
          text:
              'VirtHelm never displays the stored token after saving it. '
              'Testing this step performs read-only PVE version and inventory requests.',
        ),
      ],
    ),
  );

  Widget _verificationResult(BuildContext context) {
    final result = checkResult;
    if (result == null) return const SizedBox.shrink();
    final tls = result.certificateVerificationEnabled
        ? 'Certificate and hostname verification passed.'
        : 'TLS identity verification was disabled for this check.';
    if (result.inventoryAccessible) {
      return MessageCard(
        title: 'Connection verified',
        tone: MessageTone.success,
        icon: Icons.verified_outlined,
        text:
            'PVE ${result.serverVersion} responded. $tls '
            'Inventory access confirmed: ${result.nodeCount} node(s), '
            '${result.guestCount} workload(s).',
      );
    }
    return MessageCard(
      title: result.permissionLimited
          ? 'Server reached, inventory permission blocked'
          : 'Inventory could not be verified',
      tone: MessageTone.warning,
      icon: Icons.warning_amber_rounded,
      text:
          'PVE ${result.serverVersion} responded. $tls '
          '${result.inventoryMessage ?? 'The API token could not read cluster inventory.'} '
          'Saving remains disabled until the inventory check succeeds.',
    );
  }

  Widget _verifyStep(BuildContext context) {
    final address = normalizePveEndpoint(endpoint.text);
    final replacementToken =
        tokenId.text.trim().isNotEmpty || tokenSecret.text.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Verify connection',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Review the exact origin and TLS policy, then run a read-only check before saving.',
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alias.text.trim(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(address),
                const SizedBox(height: 12),
                Text(
                  allowInvalidCertificates
                      ? 'TLS UNVERIFIED — certificate and hostname verification disabled'
                      : 'TLS verification required',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: allowInvalidCertificates
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  editing && !replacementToken
                      ? 'Credential: keep encrypted saved token'
                      : 'Credential: ${editing ? 'replacement' : 'new'} API token',
                ),
              ],
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          MessageCard(
            title: 'Connection check failed',
            text: error!,
            tone: MessageTone.error,
          ),
        ],
        if (checkResult != null) ...[
          const SizedBox(height: 12),
          _verificationResult(context),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('connection-test'),
          onPressed: busy ? null : _runCheck,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fact_check_outlined),
          label: Text(
            busy
                ? 'Checking…'
                : checkResult == null
                ? 'Test connection'
                : 'Test again',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const Key('connection-save'),
          onPressed: busy || checkResult?.inventoryAccessible != true
              ? null
              : submit,
          icon: const Icon(Icons.save_outlined),
          label: Text(editing ? 'Save changes' : 'Save connection'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 10),
        Text(
          editing
              ? 'Saving performs the same verification again and disables any '
                    'scheduled background check for this connection. Re-enable '
                    'scheduled checks from Connections after reviewing the new settings.'
              : 'Saving performs the same verification again so a stale test result '
                    'cannot authorize a changed server or token.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasProfile = widget.controller.profiles.isNotEmpty;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: editing
            ? AppBar(title: const Text('Edit Proxmox connection'))
            : hasProfile
            ? AppBar(title: const Text('Add Proxmox connection'))
            : null,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!editing && !hasProfile) ...[
                      Container(
                        width: 68,
                        height: 68,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Icon(
                          Icons.dns_rounded,
                          size: 36,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Your infrastructure.\nIn your hands.',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Connect securely to Proxmox VE using a least-privilege API token.',
                      ),
                      const SizedBox(height: 24),
                    ],
                    _progress(context),
                    const SizedBox(height: 24),
                    if (step == 0)
                      _serverStep(context)
                    else if (step == 1)
                      _credentialStep(context)
                    else
                      _verifyStep(context),
                    if (step < 2) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          if (step > 0) ...[
                            Expanded(
                              child: OutlinedButton(
                                key: const Key('connection-back'),
                                onPressed: busy ? null : _back,
                                child: const Text('Back'),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: FilledButton(
                              key: const Key('connection-next'),
                              onPressed: busy ? null : _next,
                              child: const Text('Continue'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        key: const Key('connection-back'),
                        onPressed: busy ? null : _back,
                        child: const Text('Back'),
                      ),
                    ],
                    if (!hasProfile && !editing) ...[
                      const SizedBox(height: 24),
                      Text(
                        'VirtHelm is an independent, unofficial Proxmox VE client.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
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
