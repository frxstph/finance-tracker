import 'package:flutter/material.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../state/app_state.dart';
import 'entry_detail_page.dart';
import 'quick_add_page.dart';
import 'widgets/empty_state.dart';
import 'widgets/entry_tile.dart';
import 'widgets/month_switcher.dart';

/// Entries for the selected month, newest first, grouped by day.
class EntriesPage extends StatelessWidget {
  const EntriesPage({super.key});

  void _openDetail(BuildContext context, Entry e) {
    final id = e.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EntryDetailPage(entryId: id)),
    );
  }

  void _openAdd(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const QuickAddPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final entries = state.monthEntries;

    final children = <Widget>[const MonthSwitcher()];
    if (state.loaded && entries.isEmpty) {
      children.add(EmptyState(
        icon: Icons.edit_note,
        message: 'Nothing recorded for this month yet.',
        actionLabel: 'Add an entry',
        onAction: () => _openAdd(context),
      ));
    } else {
      String? currentDay;
      final headerStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          );
      for (final e in entries) {
        if (e.date != currentDay) {
          currentDay = e.date;
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(_dayHeader(e.date), style: headerStyle),
          ));
        }
        children.add(EntryTile(entry: e, onTap: () => _openDetail(context, e)));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: children,
    );
  }

  String _dayHeader(String date) {
    if (!isValidDateKey(date)) return date;
    return dayLabel(parseDateKey(date));
  }
}
