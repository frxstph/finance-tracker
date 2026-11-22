import 'package:flutter/material.dart';

import '../state/lock_controller.dart';
import 'lock_screen.dart';

/// A new PIN and its length.
class NewPin {
  const NewPin(this.pin, this.digits);

  final String pin;
  final int digits;
}

/// Asks for a new PIN: pick 4 or 6 digits, type it, then type it again.
/// Returns null when cancelled.
Future<NewPin?> askNewPin(BuildContext context, {int digits = 4}) {
  return Navigator.of(context).push<NewPin>(
    MaterialPageRoute<NewPin>(
      fullscreenDialog: true,
      builder: (_) => _NewPinPage(initialDigits: digits),
    ),
  );
}

/// Asks for the current PIN. Returns true when it was right.
Future<bool> askCurrentPin(BuildContext context, {required String title}) {
  return Navigator.of(context)
      .push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => _CurrentPinPage(title: title),
        ),
      )
      .then((ok) => ok ?? false);
}

class _NewPinPage extends StatefulWidget {
  const _NewPinPage({required this.initialDigits});

  final int initialDigits;

  @override
  State<_NewPinPage> createState() => _NewPinPageState();
}

class _NewPinPageState extends State<_NewPinPage> {
  late int _digits = widget.initialDigits == 6 ? 6 : 4;
  String _pin = '';
  String? _first;
  String? _error;

  void _press(String d) {
    if (_pin.length >= _digits) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length < _digits) return;
    final first = _first;
    if (first == null) {
      setState(() {
        _first = _pin;
        _pin = '';
      });
    } else if (first == _pin) {
      Navigator.of(context).pop(NewPin(_pin, _digits));
    } else {
      setState(() {
        _first = null;
        _pin = '';
        _error = 'The two PINs didn’t match. Start again.';
      });
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confirming = _first != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Set a PIN')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                if (!confirming)
                  Center(
                    child: SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(value: 4, label: Text('4 digits')),
                        ButtonSegment<int>(value: 6, label: Text('6 digits')),
                      ],
                      selected: <int>{_digits},
                      onSelectionChanged: (v) => setState(() {
                        _digits = v.first;
                        _pin = '';
                        _error = null;
                      }),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  _error ??
                      (confirming
                          ? 'Type the same PIN again'
                          : 'Type a $_digits-digit PIN'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: _error != null ? theme.colorScheme.error : null,
                  ),
                ),
                const SizedBox(height: 24),
                Center(child: PinDots(length: _digits, filled: _pin.length)),
                const SizedBox(height: 32),
                PinPad(onDigit: _press, onBackspace: _backspace),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentPinPage extends StatefulWidget {
  const _CurrentPinPage({required this.title});

  final String title;

  @override
  State<_CurrentPinPage> createState() => _CurrentPinPageState();
}

class _CurrentPinPageState extends State<_CurrentPinPage> {
  String _pin = '';
  String? _error;
  int _tries = 0;

  void _press(LockController lock, String d) {
    if (_pin.length >= lock.digits) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length < lock.digits) return;
    if (lock.checkPin(_pin)) {
      Navigator.of(context).pop(true);
      return;
    }
    _tries++;
    if (_tries >= LockController.maxTries) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _pin = '';
      _error = 'Wrong PIN. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = LockScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(
                  _error ?? 'Enter your current PIN',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: _error != null ? theme.colorScheme.error : null,
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: PinDots(length: lock.digits, filled: _pin.length),
                ),
                const SizedBox(height: 32),
                PinPad(
                  onDigit: (d) => _press(lock, d),
                  onBackspace: () {
                    if (_pin.isEmpty) return;
                    setState(() => _pin = _pin.substring(0, _pin.length - 1));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
