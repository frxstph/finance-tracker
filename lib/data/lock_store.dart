import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App lock settings, kept in their own small file (not in the database,
/// so backups never carry a PIN to another phone). The PIN itself is never
/// stored: only a salted SHA-256 of it.
class LockSettings {
  const LockSettings({
    this.pinHash,
    this.salt,
    this.digits = 4,
    this.biometrics = false,
  });

  final String? pinHash;
  final String? salt;

  /// 4 or 6.
  final int digits;
  final bool biometrics;

  bool get enabled => pinHash != null && salt != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'pinHash': pinHash,
        'salt': salt,
        'digits': digits,
        'biometrics': biometrics,
      };

  static LockSettings fromJson(Map<String, Object?> json) {
    final digits = json['digits'];
    return LockSettings(
      pinHash: json['pinHash'] as String?,
      salt: json['salt'] as String?,
      digits: digits == 6 ? 6 : 4,
      biometrics: json['biometrics'] == true,
    );
  }
}

/// Salted SHA-256 of [pin].
String hashPin(String pin, String salt) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();

/// A random salt for a new PIN.
String newSalt() {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
}

/// True when [pin] is all digits and 4 or 6 long.
bool isValidPin(String pin, int digits) =>
    (digits == 4 || digits == 6) &&
    pin.length == digits &&
    RegExp(r'^\d+$').hasMatch(pin);

class LockStore {
  LockStore._(this._file);

  final File _file;

  static Future<LockStore> open() async {
    final dir = await getApplicationSupportDirectory();
    return LockStore._(File(p.join(dir.path, 'app_lock.json')));
  }

  Future<LockSettings> load() async {
    try {
      if (!await _file.exists()) return const LockSettings();
      final json = jsonDecode(await _file.readAsString());
      if (json is Map<String, Object?>) return LockSettings.fromJson(json);
    } catch (_) {
      // A damaged file means no lock rather than a phone you can't open.
    }
    return const LockSettings();
  }

  Future<void> save(LockSettings settings) async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(_file.path);
  }
}
