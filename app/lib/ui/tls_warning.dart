import 'package:flutter/material.dart';

class TlsWarning extends StatelessWidget {
  const TlsWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'INSECURE: certificate verification disabled.',
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
