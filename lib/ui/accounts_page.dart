import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;

import '../domain/models.dart';
import '../state/app_state.dart';
import 'account_form_page.dart';
import 'widgets/dialogs.dart';
import 'widgets/empty_state.dart';

/// Opens "My accounts".
Future<void> showAccountsPage(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AccountsPage()),
  );
}

/// Where people can send you money: each account's QR code, ready to scan
/// from your phone, with its details to copy or share.
class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final accounts = state.accounts;
    return Scaffold(
      appBar: AppBar(title: const Text('My accounts')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-account',
        onPressed: () => showAccountForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add account'),
      ),
      body: accounts.isEmpty
          ? ListView(
              children: <Widget>[
                EmptyState(
                  icon: Icons.qr_code_2,
                  message: 'Save your GCash, BPI or Maya QR code so people '
                      'can scan it straight from your phone.',
                  actionLabel: 'Add an account',
                  onAction: () => showAccountForm(context),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: <Widget>[
                for (final a in accounts)
                  _AccountCard(account: a, photo: state.accountPhotoFile(a)),
              ],
            ),
    );
  }
}

enum _AccountAction { edit, delete }

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.photo});

  final PayAccount account;
  final File? photo;

  Future<void> _share(BuildContext context) async {
    final text = account.details.isEmpty
        ? account.name
        : '${account.name}\n${account.details}';
    final file = photo;
    try {
      await SharePlus.instance.share(ShareParams(
        text: text,
        files: file == null ? null : <XFile>[XFile(file.path)],
      ));
    } catch (e) {
      if (!context.mounted) return;
      showMessage(context, 'Could not share: $e');
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: account.details));
    if (!context.mounted) return;
    showMessage(context, 'Details copied');
  }

  Future<void> _onAction(BuildContext context, _AccountAction action) async {
    switch (action) {
      case _AccountAction.edit:
        await showAccountForm(context, existing: account);
      case _AccountAction.delete:
        final state = AppScope.read(context);
        final ok = await confirm(
          context,
          title: 'Delete ${account.name}?',
          message: 'Its QR code and details will be removed from the app.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (!ok) return;
        await state.deleteAccount(account);
    }
  }

  void _showFull(BuildContext context, File file) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            title: Text(account.name),
          ),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Image.file(file, fit: BoxFit.contain),
                  ),
                ),
                if (account.details.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Text(
                      account.details,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.black, fontSize: 18, height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = photo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    account.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () => _share(context),
                ),
                PopupMenuButton<_AccountAction>(
                  tooltip: 'More',
                  onSelected: (a) => _onAction(context, a),
                  itemBuilder: (_) => const <PopupMenuEntry<_AccountAction>>[
                    PopupMenuItem<_AccountAction>(
                      value: _AccountAction.edit,
                      child: Text('Edit'),
                    ),
                    PopupMenuItem<_AccountAction>(
                      value: _AccountAction.delete,
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 8),
                  if (file != null)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showFull(context, file),
                      child: Container(
                        height: 240,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Image.file(
                          file,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(child: Text('QR image not found')),
                        ),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () =>
                          showAccountForm(context, existing: account),
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Add QR code'),
                    ),
                  if (file != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      'Tap the code to show it full screen',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (account.details.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: SelectableText(
                            account.details,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy details',
                          icon: const Icon(Icons.copy),
                          onPressed: () => _copy(context),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
