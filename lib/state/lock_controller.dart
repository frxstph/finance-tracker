import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

import '../data/lock_store.dart';

/// App lock: a 4 or 6 digit PIN, optionally fingerprint or face.
///
/// Locks when the app starts and when it comes back after being away for
/// [relockAfter]. Wrong PINs: after [maxTries] in a row, wait [cooldown].
class LockController extends ChangeNotifier with WidgetsBindingObserver {
  LockController(this._store);

  final LockStore _store;
  final LocalAuthentication _auth = LocalAuthentication();
  static const MethodChannel _window = MethodChannel('finance_tracker/window');

  static const Duration relockAfter = Duration(minutes: 1);
  static const int maxTries = 5;
  static const Duration cooldown = Duration(seconds: 30);

  LockSettings _settings = const LockSettings();
  bool _locked = false;
  bool _biometricsAvailable = false;
  DateTime? _wentAway;
  int _wrongTries = 0;
  DateTime? _waitUntil;

  /// While true the app doesn't lock on return (the camera, gallery or a
  /// share sheet is open on our behalf).
  bool _expectingReturn = false;

  bool get enabled => _settings.enabled;
  bool get locked => _locked && _settings.enabled;
  int get digits => _settings.digits;
  bool get biometrics => _settings.biometrics && _biometricsAvailable;
  bool get biometricsAvailable => _biometricsAvailable;

  /// When wrong PINs have to wait, until when.
  DateTime? get waitUntil {
    final w = _waitUntil;
    if (w == null || DateTime.now().isAfter(w)) return null;
    return w;
  }

  Future<void> load() async {
    _settings = await _store.load();
    _locked = _settings.enabled;
    try {
      _biometricsAvailable = await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      _biometricsAvailable = false;
    }
    await _applyPreview();
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
  }

  Future<void> _applyPreview() async {
    try {
      await _window.invokeMethod<void>('hidePreview', _settings.enabled);
    } catch (_) {
      // Older Android or no channel: nothing to hide.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wentAway ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _wentAway;
      _wentAway = null;
      if (_expectingReturn) return;
      if (enabled &&
          away != null &&
          DateTime.now().difference(away) >= relockAfter) {
        _locked = true;
        notifyListeners();
      }
    }
  }

  /// Runs [task] (camera, gallery, file picker, share) without locking when
  /// the app comes back from it.
  Future<T> whileAway<T>(Future<T> Function() task) async {
    _expectingReturn = true;
    try {
      return await task();
    } finally {
      _expectingReturn = false;
    }
  }

  /// Checks [pin]; unlocks when right.
  bool tryPin(String pin) {
    if (waitUntil != null) return false;
    final hash = _settings.pinHash;
    final salt = _settings.salt;
    if (hash == null || salt == null) return true;
    if (hashPin(pin, salt) == hash) {
      _wrongTries = 0;
      _locked = false;
      notifyListeners();
      return true;
    }
    _wrongTries++;
    if (_wrongTries >= maxTries) {
      _wrongTries = 0;
      _waitUntil = DateTime.now().add(cooldown);
    }
    notifyListeners();
    return false;
  }

  /// True when [pin] is the current PIN (for turning the lock off or
  /// changing it). Doesn't change the lock state.
  bool checkPin(String pin) {
    final hash = _settings.pinHash;
    final salt = _settings.salt;
    return hash != null && salt != null && hashPin(pin, salt) == hash;
  }

  /// Shows the fingerprint / face prompt. Returns true when it unlocked.
  Future<bool> unlockWithBiometrics() async {
    if (!biometrics) return false;
    final ok = await confirmBiometrics('Unlock Finance Tracker');
    if (ok) {
      _wrongTries = 0;
      _locked = false;
      notifyListeners();
    }
    return ok;
  }

  /// Fingerprint / face prompt with [reason]; false on cancel or error.
  Future<bool> confirmBiometrics(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  /// Turns the lock on, or changes the PIN, keeping the biometrics choice.
  Future<void> setPin(String pin, int digits) async {
    if (!isValidPin(pin, digits)) {
      throw ArgumentError('PIN must be $digits digits');
    }
    final salt = newSalt();
    _settings = LockSettings(
      pinHash: hashPin(pin, salt),
      salt: salt,
      digits: digits,
      biometrics: _settings.enabled && _settings.biometrics,
    );
    await _store.save(_settings);
    _locked = false;
    await _applyPreview();
    notifyListeners();
  }

  Future<void> setBiometrics(bool on) async {
    if (!enabled) return;
    _settings = LockSettings(
      pinHash: _settings.pinHash,
      salt: _settings.salt,
      digits: _settings.digits,
      biometrics: on,
    );
    await _store.save(_settings);
    notifyListeners();
  }

  /// Turns the lock off (the caller has already checked the PIN).
  Future<void> disable() async {
    _settings = const LockSettings();
    await _store.save(_settings);
    _locked = false;
    await _applyPreview();
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Gives the widget tree access to the [LockController].
class LockScope extends InheritedNotifier<LockController> {
  const LockScope({
    super.key,
    required LockController controller,
    required super.child,
  }) : super(notifier: controller);

  static LockController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LockScope>();
    assert(scope != null, 'No LockScope above this widget');
    return scope!.notifier!;
  }

  static LockController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<LockScope>();
    assert(scope != null, 'No LockScope above this widget');
    return scope!.notifier!;
  }
}
