import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/data/user_repository.dart';
import '../security/pin_hasher.dart';

/// Papan angka besar untuk memasukkan PIN.
///
/// [onCompleted] dipanggil otomatis begitu [pinLength] angka terisi; setelah
/// selesai, isian dikosongkan kembali. Mendukung keyboard fisik juga.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.onCompleted,
    this.subtitle,
    this.errorText,
  });

  final String title;
  final String? subtitle;
  final String? errorText;
  final Future<void> Function(String pin) onCompleted;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;

  Future<void> _add(String digit) async {
    if (_busy || _pin.length >= pinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length == pinLength) {
      setState(() => _busy = true);
      try {
        await widget.onCompleted(_pin);
      } finally {
        if (mounted) {
          setState(() {
            _pin = '';
            _busy = false;
          });
        }
      }
    }
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final char = event.character;
    if (char != null && RegExp(r'^\d$').hasMatch(char)) {
      _add(char);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasError = widget.errorText != null;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.subtitle!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          Semantics(
            label: 'PIN terisi ${_pin.length} dari $pinLength angka',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < pinLength; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length
                          ? (hasError ? scheme.error : scheme.primary)
                          : Colors.transparent,
                      border: Border.all(
                        color: hasError ? scheme.error : scheme.outline,
                        width: 2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: Center(
              child: _busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : hasError
                      ? Text(
                          widget.errorText!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : null,
            ),
          ),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (final d in row) _key(d)],
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 92, height: 80),
              _key('0'),
              _PadButton(
                onTap: _backspace,
                semanticLabel: 'Hapus',
                child: const Icon(Icons.backspace_outlined, size: 28),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _key(String digit) => _PadButton(
        onTap: () => _add(digit),
        semanticLabel: digit,
        child: Text(
          digit,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
        ),
      );
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.onTap,
    required this.child,
    required this.semanticLabel,
  });

  final VoidCallback onTap;
  final Widget child;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Material(
          color: scheme.surfaceContainerHigh,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 76, height: 72, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

/// Alur membuat PIN baru: masukkan PIN, lalu ulangi untuk konfirmasi.
class PinSetupFlow extends StatefulWidget {
  const PinSetupFlow({
    super.key,
    required this.onPinChosen,
    this.title = 'Buat PIN 6 angka',
    this.subtitle = 'PIN dipakai setiap kali masuk ke aplikasi',
  });

  final String title;
  final String subtitle;

  /// Dipanggil dengan PIN yang sudah dikonfirmasi. Bila melempar
  /// [UserRuleException], pesannya ditampilkan dan alur diulang.
  final Future<void> Function(String pin) onPinChosen;

  @override
  State<PinSetupFlow> createState() => _PinSetupFlowState();
}

class _PinSetupFlowState extends State<PinSetupFlow> {
  String? _first;
  String? _error;

  Future<void> _onEntered(String pin) async {
    if (_first == null) {
      final problem = validateNewPin(pin);
      setState(() {
        _error = problem;
        if (problem == null) _first = pin;
      });
      return;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _error = 'PIN tidak sama. Silakan buat ulang.';
      });
      return;
    }
    try {
      await widget.onPinChosen(pin);
    } on UserRuleException catch (e) {
      if (mounted) {
        setState(() {
          _first = null;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _first != null;
    return PinPad(
      key: ValueKey(confirming),
      title: confirming ? 'Ulangi PIN' : widget.title,
      subtitle: confirming ? 'Masukkan PIN yang sama sekali lagi' : widget.subtitle,
      errorText: _error,
      onCompleted: _onEntered,
    );
  }
}
