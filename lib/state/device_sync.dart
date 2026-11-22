import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../data/app_prefs.dart';
import '../data/device_bridge.dart';
import '../domain/money.dart';
import '../domain/reminders.dart';
import 'app_state.dart';
import 'lock_controller.dart';

/// Keeps the phone's side up to date: the home screen widget and the
/// scheduled due date reminders. Runs a second after anything changes, and
/// whenever the app comes back to the front (the date may have changed).
class DeviceSync {
  DeviceSync({required this.state, required this.lock, required this.prefs}) {
    state.addListener(_soon);
    lock.addListener(_soon);
    prefs.addListener(_soon);
    _lifecycle = AppLifecycleListener(onResume: _soon);
    _soon();
  }

  final AppState state;
  final LockController lock;
  final AppPrefs prefs;
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  String? _lastWidget;
  String? _lastReminders;

  void _soon() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), _push);
  }

  Future<void> _push() async {
    if (!state.loaded) return;
    final widget = widgetData();
    final w = jsonEncode(widget);
    if (w != _lastWidget) {
      _lastWidget = w;
      await DeviceBridge.updateWidget(widget);
    }
    final reminders = prefs.reminders
        ? buildReminders(state.upcomingDues, DateTime.now())
        : const <Reminder>[];
    final list = <Map<String, Object?>>[
      for (final r in reminders)
        <String, Object?>{
          'id': r.id,
          'at': r.at.millisecondsSinceEpoch,
          'title': r.title,
          'body': r.body,
        },
    ];
    final rj = jsonEncode(list);
    if (rj != _lastReminders) {
      _lastReminders = rj;
      await DeviceBridge.setReminders(list);
    }
  }

  /// What the widget shows: the same headline as the Safe to spend card,
  /// the next payday (the widget counts the days itself), and the date the
  /// numbers are from. Amounts are hidden while App lock is on.
  Map<String, Object?> widgetData() {
    final s = state.safeToSpendNow;
    final perDay = s.perDay ~/ 100 * 100;
    final String headline;
    final String tone;
    if (s.short) {
      headline = 'Hold off spending';
      tone = 'red';
    } else if (perDay == 0) {
      headline = 'Nothing spare';
      tone = 'orange';
    } else {
      headline = '${formatPeso(perDay)} a day';
      tone = 'green';
    }
    final now = DateTime.now();
    return <String, Object?>{
      'headline': headline,
      'tone': tone,
      'payday': s.paydayName == null
          ? null
          : DateFormat('yyyy-MM-dd').format(s.payday),
      'asOf': 'As of ${DateFormat('EEE d MMM').format(now)}',
      'hidden': lock.enabled,
    };
  }

  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    state.removeListener(_soon);
    lock.removeListener(_soon);
    prefs.removeListener(_soon);
  }
}
