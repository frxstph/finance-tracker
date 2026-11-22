import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Talks to the Android side (ci/android/*.kt): the home screen widget and
/// due date notifications. Every call is safe to make when the native side
/// is missing (tests, older builds): it just does nothing.
class DeviceBridge {
  static const MethodChannel _channel = MethodChannel('finance_tracker/window');

  /// Sends what the Safe to spend widget shows and redraws it.
  static Future<void> updateWidget(Map<String, Object?> data) async {
    try {
      await _channel.invokeMethod<void>('updateWidget', data);
    } catch (_) {}
  }

  /// Replaces every scheduled reminder with [reminders].
  static Future<void> setReminders(List<Map<String, Object?>> reminders) async {
    try {
      await _channel.invokeMethod<void>('setReminders', reminders);
    } catch (_) {}
  }

  /// True when the app may show notifications.
  static Future<bool> notificationsAllowed() async {
    try {
      return await _channel.invokeMethod<bool>('notificationsAllowed') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Asks Android 13+ for notification permission. Returns true when it
  /// shows the question (the answer comes back when the app resumes).
  static Future<bool> askNotifications() async {
    try {
      return await _channel.invokeMethod<bool>('askNotifications') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Waits until the app is back in front (after a system dialog), or
  /// [timeout].
  static Future<void> waitForResume(
      {Duration timeout = const Duration(seconds: 30)}) async {
    final done = Completer<void>();
    final listener = AppLifecycleListener(onResume: () {
      if (!done.isCompleted) done.complete();
    });
    try {
      await done.future.timeout(timeout, onTimeout: () {});
    } finally {
      listener.dispose();
    }
  }
}
