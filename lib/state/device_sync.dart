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

  /// What the widget shows: the Safe to spend amount ("₱650" + "a day"),
  /// the date it's from, the next payday (the widget counts the days
  /// itself) and the next bill or loan payment due. Always shows amounts.
  Map<String, Object?> widgetData() {
    final s = state.safeToSpendNow;
    final perDay = s.perDay ~/ 100 * 100;
    final String big;
    final String suffix;
    final String tone;
    if (s.short) {
      big = 'Hold off';
      suffix = 'spending';
      tone = 'red';
    } else if (perDay == 0) {
      big = 'Nothing';
      suffix = 'spare';
      tone = 'orange';
    } else {
      big = formatPeso(perDay);
      suffix = 'a day';
      tone = 'green';
    }
    final now = DateTime.now();
    return <String, Object?>{
      'big': big,
      'suffix': suffix,
      'tone': tone,
      'payday': s.paydayName == null
          ? null
          : DateFormat('yyyy-MM-dd').format(s.payday),
      'date': DateFormat('EEE d MMM').format(now),
      'nextDue': nextDueText(state.upcomingDues, now),
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

/// "Next: Water · Tue" for the soonest item due today or later; null when
/// nothing is due.
String? nextDueText(List<DueItem> dues, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DueItem? next;
  for (final d in dues) {
    final day = DateTime(d.date.year, d.date.month, d.date.day);
    if (day.isBefore(today)) continue;
    if (next == null || day.isBefore(next.date)) next = d;
  }
  if (next == null) return null;
  final day = DateTime(next.date.year, next.date.month, next.date.day);
  final diff = day.difference(today).inDays;
  final when = diff == 0
      ? 'Today'
      : diff == 1
          ? 'Tomorrow'
          : diff < 7
              ? DateFormat('EEE').format(day)
              : DateFormat('d MMM').format(day);
  return 'Next: ${next.label} · $when';
}
