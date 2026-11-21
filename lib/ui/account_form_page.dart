import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/app_state.dart';
import 'widgets/dialogs.dart';
import 'widgets/photo_section.dart';

/// Opens the form to add or edit a payment account.
Future<void> showAccountForm(BuildContext context, {PayAccount? existing}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AccountFormPage(existing: existing),
    ),
  );
}

/// Name, details (account name and number) and the QR code image.
class AccountFormPage extends StatefulWidget {
  const AccountFormPage({super.key, this.existing});

  final PayAccount? existing;

  @override
  State<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends State<AccountFormPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _details = TextEditingController();
  PhotoChange _photoChange = PhotoChange.keep;
  String? _newPhotoPath;
  String? _nameError;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    if (a != null) {
      _name.text = a.name;
      _details.text = a.details;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _details.dispose();
    super.dispose();
  }

  File? _previewFile(AppState state) {
    switch (_photoChange) {
      case PhotoChange.replace:
        final path = _newPhotoPath;
        return path == null ? null : File(path);
      case PhotoChange.remove:
        return null;
      case PhotoChange.keep:
        final a = widget.existing;
        return a == null ? null : state.accountPhotoFile(a);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    setState(() => _nameError = name.isEmpty ? 'Enter a name' : null);
    if (name.isEmpty) return;
    final account = (widget.existing ?? PayAccount(name: name)).copyWith(
      name: name,
      details: _details.text.trim(),
    );
    setState(() => _saving = true);
    try {
      await AppScope.read(context).saveAccount(
        account,
        photoChange: _photoChange,
        newPhotoPath: _newPhotoPath,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Could not save: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit account' : 'New account'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _name,
            autofocus: !_isEditing,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'GCash, BPI savings, Maya',
              errorText: _nameError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _details,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Details (optional)',
              hintText: 'Account name and number',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          PhotoSection(
            file: _previewFile(state),
            addLabel: 'Add QR code',
            onPicked: (path) {
              if (!mounted) return;
              setState(() {
                _photoChange = PhotoChange.replace;
                _newPhotoPath = path;
              });
            },
            onRemove: () => setState(() {
              _photoChange = PhotoChange.remove;
              _newPhotoPath = null;
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: in GCash, BPI or Maya, save your "Receive money" QR as a '
            'screenshot, then choose it from your gallery here.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
