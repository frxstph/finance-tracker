import 'dart:async';

import 'package:flutter/material.dart';

import '../state/lock_controller.dart';

/// Covers the whole app while it's locked: PIN dots, a number pad, and a
/// fingerprint / face button when that's turned on.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Offer fingerprint / face straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lock = LockScope.read(context);
      if (lock.biometrics) lock.unlockWithBiometrics();
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && LockScope.read(context).waitUntil != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _press(LockController lock, String digit) {
    if (lock.waitUntil != null || _pin.length >= lock.digits) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == lock.digits) {
      final ok = lock.tryPin(_pin);
      if (!ok) {
        setState(() {
          _pin = '';
          _error = lock.waitUntil != null ? null : 'Wrong PIN. Try again.';
        });
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _forgot() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forgot your PIN?'),
        content: const Text(
          'The PIN can’t be reset, because nothing is stored online. To get '
          'back in, clear this app’s data in your phone’s settings (or '
          'reinstall it), then restore your latest backup from Settings.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lock = LockScope.of(context);
    final theme = Theme.of(context);
    final wait = lock.waitUntil;
    final seconds =
        wait == null ? 0 : wait.difference(DateTime.now()).inSeconds + 1;
    final message = wait != null
        ? 'Too many tries. Wait $seconds s.'
        : _error ?? 'Enter your PIN';
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.lock_outline,
                    size: 40, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('Finance Tracker', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: _error != null || wait != null
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                PinDots(length: lock.digits, filled: _pin.length),
                const SizedBox(height: 32),
                PinPad(
                  onDigit: (d) => _press(lock, d),
                  onBackspace: _backspace,
                  extra: lock.biometrics
                      ? IconButton(
                          tooltip: 'Use fingerprint or face',
                          iconSize: 32,
                          onPressed: lock.unlockWithBiometrics,
                          icon: const Icon(Icons.fingerprint),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _forgot,
                  child: const Text('Forgot PIN?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of [length] dots, the first [filled] filled in.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, required this.filled});

  final int length;
  final int filled;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: '$filled of $length digits entered',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < length; i++)
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? color : Colors.transparent,
                border: Border.all(color: color, width: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// 1–9, then [extra] (or a blank), 0 and backspace.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.extra,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget key(String d) => SizedBox(
          width: 76,
          height: 76,
          child: TextButton(
            style: TextButton.styleFrom(
              shape: const CircleBorder(),
              textStyle: theme.textTheme.headlineMedium,
            ),
            onPressed: () => onDigit(d),
            child: Text(d),
          ),
        );
    Widget cell(Widget? child) =>
        SizedBox(width: 76, height: 76, child: Center(child: child));
    Widget row(List<Widget> cells) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: cells,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        row(<Widget>[key('1'), key('2'), key('3')]),
        row(<Widget>[key('4'), key('5'), key('6')]),
        row(<Widget>[key('7'), key('8'), key('9')]),
        row(<Widget>[
          cell(extra),
          key('0'),
          cell(IconButton(
            tooltip: 'Delete',
            iconSize: 28,
            onPressed: onBackspace,
            icon: const Icon(Icons.backspace_outlined),
          )),
        ]),
      ],
    );
  }
}
