import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_prefs.dart';
import '../data/backup.dart';
import '../data/device_bridge.dart';
import '../state/app_state.dart';
import '../state/lock_controller.dart';
import 'pin_pages.dart';
import 'theme.dart';
import 'widgets/dialogs.dart';

/// App lock, backups, CSV export and the app version.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;

  Future<void> _export() async {
    final state = AppScope.read(context);
    final lock = LockScope.read(context);
    setState(() => _busy = true);
    try {
      await lock.whileAway(state.exportBackup);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not export: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final state = AppScope.read(context);
    final FilePickerResult? result =
        await LockScope.read(context).whileAway(
      () => FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      ),
    );
    if (!mounted) return;
    final path =
        result == null || result.files.isEmpty ? null : result.files.first.path;
    if (path == null) return;

    setState(() => _busy = true);
    BackupContents? read;
    try {
      read = await state.readBackup(path);
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, e.message);
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, 'Could not read the backup: $e');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final BackupContents? contents = read;
    if (contents == null) return;

    final ok = await confirm(
      context,
      title: 'Restore this backup?',
      message: 'This replaces everything on this phone with the backup '
          '(${contents.bills.length} bills, ${contents.loans.length} loans, '
          '${contents.incomes.length} monthly incomes, '
          '${contents.entries.length} entries, '
          '${contents.receipts.length} photos).',
      confirmLabel: 'Restore',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await state.restoreBackup(contents);
      if (mounted) showMessage(context, 'Backup restored.');
    } on RestorePhotosException {
      if (mounted) {
        showMessage(context,
            'Data restored, but the receipt photos could not be replaced.');
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Restore failed. Nothing was changed. ($e)');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    final state = AppScope.read(context);
    final lock = LockScope.read(context);
    if (state.allEntries.isEmpty) {
      showMessage(context, 'No entries to export yet.');
      return;
    }
    setState(() => _busy = true);
    try {
      await lock.whileAway(state.exportCsv);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not export: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleLock(bool on) async {
    final lock = LockScope.read(context);
    if (on) {
      final pin = await askNewPin(context);
      if (pin == null || !mounted) return;
      await lock.setPin(pin.pin, pin.digits);
      if (mounted) showMessage(context, 'App lock is on.');
    } else {
      final ok = await askCurrentPin(context, title: 'Turn off app lock');
      if (!ok || !mounted) return;
      await lock.disable();
      if (mounted) showMessage(context, 'App lock is off.');
    }
  }

  Future<void> _changePin() async {
    final lock = LockScope.read(context);
    final ok = await askCurrentPin(context, title: 'Change PIN');
    if (!ok || !mounted) return;
    final pin = await askNewPin(context, digits: lock.digits);
    if (pin == null || !mounted) return;
    await lock.setPin(pin.pin, pin.digits);
    if (mounted) showMessage(context, 'PIN changed.');
  }

  Future<void> _toggleBiometrics(bool on) async {
    final lock = LockScope.read(context);
    if (on) {
      final ok = await lock
          .confirmBiometrics('Confirm to use fingerprint or face unlock');
      if (!ok || !mounted) return;
    }
    await lock.setBiometrics(on);
  }

  Future<void> _toggleReminders(bool on) async {
    final prefs = PrefsScope.of(context);
    if (!on) {
      await prefs.setReminders(false);
      return;
    }
    var allowed = await DeviceBridge.notificationsAllowed();
    if (!allowed) {
      final asked = await DeviceBridge.askNotifications();
      if (asked) await DeviceBridge.waitForResume();
      allowed = await DeviceBridge.notificationsAllowed();
    }
    if (!mounted) return;
    if (!allowed) {
      showMessage(
        context,
        'Notifications are off for this app. Turn them on in your phone’s '
        'settings, then try again.',
      );
      return;
    }
    await prefs.setReminders(true);
    if (mounted) showMessage(context, 'Reminders are on.');
  }

  @override
  Widget build(BuildContext context) {
    final lock = LockScope.of(context);
    final prefs = PrefsScope.of(context);
    final missing = AppScope.of(context).missingDueDays;
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            text,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          if (_busy) const LinearProgressIndicator(),
          heading('App lock'),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('Lock the app'),
            subtitle: Text(lock.enabled
                ? 'Asks for your ${lock.digits}-digit PIN when you open it'
                : 'Ask for a PIN when the app opens'),
            value: lock.enabled,
            onChanged: _busy ? null : _toggleLock,
          ),
          if (lock.enabled) ...<Widget>[
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Change PIN'),
              subtitle: const Text('Switch between 4 and 6 digits here too'),
              onTap: _changePin,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Use fingerprint or face'),
              subtitle: Text(lock.biometricsAvailable
                  ? 'Your PIN still works as a backup'
                  : 'Not set up on this phone'),
              value: lock.biometrics,
              onChanged: lock.biometricsAvailable ? _toggleBiometrics : null,
            ),
          ],
          const Divider(),
          heading('Reminders'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Due date reminders'),
            subtitle: Text(
              'The evening before and the morning a bill or loan is due'
              '${missing > 0 ? '. $missing ${missing == 1 ? 'item has' : 'items have'} no due day and won’t get one.' : ''}',
            ),
            value: prefs.reminders,
            onChanged: _toggleReminders,
          ),
          const Divider(),
          heading('Your data'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Export backup'),
            subtitle: const Text('Save a zip to Drive, Files or anywhere'),
            enabled: !_busy,
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restore backup'),
            subtitle: const Text('Replace everything with a backup zip'),
            enabled: !_busy,
            onTap: _restore,
          ),
          ListTile(
            leading: const Icon(Icons.table_view_outlined),
            title: const Text('Export entries (CSV)'),
            subtitle: const Text('Opens in Excel or Google Sheets'),
            enabled: !_busy,
            onTap: _exportCsv,
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Finance Tracker'),
            subtitle: Text('Version $appVersion · works offline'),
          ),
        ],
      ),
    );
  }
}
