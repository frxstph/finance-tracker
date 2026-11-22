import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Small on/off settings kept in their own file (not in backups).
class AppPrefs extends ChangeNotifier {
  AppPrefs._(this._file);

  final File _file;
  bool _reminders = false;

  /// Due date reminders on or off. Off until turned on in Settings, since
  /// it needs notification permission.
  bool get reminders => _reminders;

  static Future<AppPrefs> open() async {
    final dir = await getApplicationSupportDirectory();
    final prefs = AppPrefs._(File(p.join(dir.path, 'prefs.json')));
    try {
      if (await prefs._file.exists()) {
        final json = jsonDecode(await prefs._file.readAsString());
        if (json is Map<String, Object?>) {
          prefs._reminders = json['reminders'] == true;
        }
      }
    } catch (_) {
      // Unreadable: keep the defaults.
    }
    return prefs;
  }

  Future<void> setReminders(bool on) async {
    _reminders = on;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(<String, Object?>{
      'reminders': _reminders,
    }), flush: true);
    await tmp.rename(_file.path);
  }
}

/// Gives the widget tree access to [AppPrefs].
class PrefsScope extends InheritedNotifier<AppPrefs> {
  const PrefsScope({super.key, required AppPrefs prefs, required super.child})
      : super(notifier: prefs);

  static AppPrefs of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PrefsScope>();
    assert(scope != null, 'No PrefsScope above this widget');
    return scope!.notifier!;
  }
}
