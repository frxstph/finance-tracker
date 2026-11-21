import 'package:flutter/material.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/summary.dart';
import '../state/app_state.dart';
import 'entry_detail_page.dart';
import 'quick_add_page.dart';
import 'theme.dart';
import 'widgets/empty_state.dart';
import 'widgets/entry_tile.dart';
import 'widgets/month_switcher.dart';

/// Which entries the list shows.
enum EntryFilter {
  all('All'),
  income('Income'),
  spending('Spending'),
  oneTime('One-time'),
  loans('Loan payments'),
  adjustments('Adjustments');

  const EntryFilter(this.label);

  final String label;

  bool matches(EntryType t) {
    switch (this) {
      case EntryFilter.all:
        return true;
      case EntryFilter.income:
        return t == EntryType.income || t == EntryType.loanReceived;
      case EntryFilter.spending:
        return t == EntryType.bill ||
            t == EntryType.oneTime ||
            t == EntryType.daily;
      case EntryFilter.oneTime:
        return t == EntryType.oneTime;
      case EntryFilter.loans:
        return t == EntryType.loanPayment;
      case EntryFilter.adjustments:
        return t.isAdjustment;
    }
  }
}

/// Entries newest first, grouped by day: one month or all months, filtered
/// by kind (income, spending, one-time, loan payments), with a total.
class EntriesPage extends StatefulWidget {
  const EntriesPage({super.key});

  @override
  State<EntriesPage> createState() => _EntriesPageState();
}

class _EntriesPageState extends State<EntriesPage> {
  EntryFilter _filter = EntryFilter.all;
  bool _allMonths = false;

  void _openDetail(Entry e) {
    final id = e.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EntryDetailPage(entryId: id)),
    );
  }

  void _openAdd() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const QuickAddPage(),
      ),
    );
  }

  /// "Net +₱1,250 · 12 entries" for All, "₱3,400 · 5 entries" otherwise.
  String _totalLine(List<Entry> entries) {
    final n = entries.length;
    final count = '$n ${n == 1 ? 'entry' : 'entries'}';
    if (_filter == EntryFilter.all || _filter == EntryFilter.adjustments) {
      final net = entries.fold<int>(0, (sum, e) => sum + signedAmount(e));
      final sign = net > 0 ? '+' : '';
      return 'Net $sign${formatPeso(net)} · $count';
    }
    final total = entries.fold<int>(0, (sum, e) => sum + e.amount);
    return 'Total ${formatPeso(total)} · $count';
  }

  Color? _totalColor(BuildContext context) {
    switch (_filter) {
      case EntryFilter.income:
        return incomeColor(context);
      case EntryFilter.spending:
      case EntryFilter.oneTime:
      case EntryFilter.loans:
        return debtColor(context);
      case EntryFilter.all:
      case EntryFilter.adjustments:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final source = _allMonths ? state.allEntries : state.monthEntries;
    final entries = <Entry>[
      for (final e in source)
        if (_filter.matches(e.type)) e,
    ];

    final children = <Widget>[
      if (!_allMonths) const MonthSwitcher(),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            FilterChip(
              label: const Text('All months'),
              selected: _allMonths,
              onSelected: (v) => setState(() => _allMonths = v),
            ),
            const SizedBox(width: 8),
            for (final f in EntryFilter.values) ...<Widget>[
              ChoiceChip(
                label: Text(f.label),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          _totalLine(entries),
          style: theme.textTheme.titleSmall?.copyWith(
            color: _totalColor(context),
            fontFeatures: tabularFigures,
          ),
        ),
      ),
    ];

    if (state.loaded && entries.isEmpty) {
      final nothingAtAll = source.isEmpty;
      children.add(EmptyState(
        icon: Icons.edit_note,
        message: nothingAtAll
            ? (_allMonths
                ? 'Nothing recorded yet.'
                : 'Nothing recorded for this month yet.')
            : 'No ${_filter.label.toLowerCase()} entries here.',
        actionLabel: 'Add an entry',
        onAction: _openAdd,
      ));
    } else {
      String? currentDay;
      final headerStyle = theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
      );
      for (final e in entries) {
        if (e.date != currentDay) {
          currentDay = e.date;
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(_dayHeader(e.date), style: headerStyle),
          ));
        }
        children.add(EntryTile(entry: e, onTap: () => _openDetail(e)));
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
