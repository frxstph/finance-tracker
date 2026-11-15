import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/dialogs.dart';

/// Export and restore backups, plus the app version.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;

  Future<void> _export() async {
    final state = AppScope.read(context);
    setState(() => _busy = true);
    try {
      await state.exportBackup();
    } catch (e) {
      if (mounted) showMessage(context, 'Could not export: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final state = AppScope.read(context);
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          if (_busy) const LinearProgressIndicator(),
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
