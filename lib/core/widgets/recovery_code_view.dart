import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Menampilkan kode pemulihan dan meminta pengguna mencatatnya.
class RecoveryCodeView extends StatefulWidget {
  const RecoveryCodeView({
    super.key,
    required this.code,
    required this.onDone,
    this.doneLabel = 'Lanjut',
    this.footer,
  });

  final String code;
  final VoidCallback onDone;
  final String doneLabel;
  final Widget? footer;

  @override
  State<RecoveryCodeView> createState() => _RecoveryCodeViewState();
}

class _RecoveryCodeViewState extends State<RecoveryCodeView> {
  bool _noted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.key_rounded, size: 56, color: scheme.primary),
        const SizedBox(height: 12),
        Text(
          'Kode Pemulihan',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Jika Pemilik lupa PIN, kode ini dipakai untuk membuat PIN baru. '
          'Tulis di kertas dan simpan di tempat aman — jangan disimpan di HP ini.',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(
            widget.code,
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.code));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Kode disalin')),
            );
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Salin kode'),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _noted,
          onChanged: (v) => setState(() => _noted = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('Saya sudah mencatat kode ini'),
        ),
        if (widget.footer != null) ...[
          const SizedBox(height: 8),
          widget.footer!,
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _noted ? widget.onDone : null,
          child: Text(widget.doneLabel),
        ),
      ],
    );
  }
}
