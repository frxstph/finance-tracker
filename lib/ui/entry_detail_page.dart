import 'package:flutter/material.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../state/app_state.dart';
import 'quick_add_page.dart';
import 'theme.dart';
import 'widgets/dialogs.dart';

/// Shows one entry with its photo full width, plus edit and delete.
class EntryDetailPage extends StatelessWidget {
  const EntryDetailPage({super.key, required this.entryId});

  final int entryId;

  Future<void> _edit(BuildContext context, Entry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => QuickAddPage(existing: entry),
      ),
    );
  }

  Future<void> _delete(BuildContext context, Entry entry) async {
    final state = AppScope.read(context);
    final ok = await confirm(
      context,
      title: 'Delete this entry?',
      message: entry.hasPhoto
          ? 'The entry and its photo will be removed.'
          : 'The entry will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await state.deleteEntry(entry);
    } catch (e) {
      if (!context.mounted) return;
      showMessage(context, 'Could not delete: $e');
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final entry = state.entryById(entryId);
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This entry no longer exists.')),
      );
    }
    final theme = Theme.of(context);
    final isIncome = entry.type.isMoneyIn;
    final photo = state.photoFile(entry);
    final linked = entry.type == EntryType.bill
        ? state.billById(entry.billId)?.name
        : entry.type.needsLoan
            ? state.loanById(entry.loanId)?.name
            : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.type.label),
        actions: <Widget>[
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _edit(context, entry),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, entry),
          ),
        ],
      ),
      body: ListView(
        children: <Widget>[
          if (photo != null)
            Image.file(
              photo,
              width: double.infinity,
              fit: BoxFit.fitWidth,
              errorBuilder: (context, error, stackTrace) => const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Photo not found'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  isIncome
                      ? '+${formatPeso(entry.amount)}'
                      : formatPeso(entry.amount),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: isIncome ? incomeColor(context) : null,
                    fontFeatures: tabularFigures,
                  ),
                ),
                const SizedBox(height: 8),
                Text(state.titleFor(entry), style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          ListTile(
            leading: Icon(iconForType(entry.type)),
            title: Text(entry.type.label),
            subtitle: linked == null ? null : Text(linked),
          ),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(isValidDateKey(entry.date)
                ? dayLabel(parseDateKey(entry.date))
                : entry.date),
          ),
          if (entry.note.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes),
              title: Text(entry.note),
            ),
        ],
      ),
    );
  }
}
