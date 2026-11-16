import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import '../state/app_state.dart';
import 'pay_pages.dart';
import 'theme.dart';
import 'widgets/dialogs.dart';
import 'widgets/month_switcher.dart';
import 'widgets/name_amount_dialog.dart';

enum _BillAction { edit, archive, unarchive, delete }

enum _IncomeAction { edit, archive, unarchive, delete }

/// The Monthly tab: money that comes in every month (with its day) and
/// bills that go out every month, each with this month's status.
class BillsPage extends StatelessWidget {
  const BillsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final s = state.summary;
    final active = state.activeBills;
    final archived = state.archivedBills;
    final incomes = state.activeIncomes;
    final archivedIncomes = state.archivedIncomes;
    final sectionStyle = theme.textTheme.titleMedium;
    final noteStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: tabularFigures,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        const MonthSwitcher(),

        // Income
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text('Monthly income', style: sectionStyle),
        ),
        if (incomes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Text(
              s.incomesLeft.isEmpty
                  ? 'All received this month'
                  : '${s.incomesLeft.length} still to come · '
                      '${formatPeso(s.incomeLeftAmount)}',
              style: noteStyle,
            ),
          ),
        for (final i in incomes)
          _IncomeTile(
            source: i,
            received: i.id != null && s.receivedIncomeIds.contains(i.id),
          ),
        if (incomes.isEmpty)
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add monthly income'),
            subtitle: const Text('Salary on the 19th, pay on the 15th…'),
            onTap: () => showNewIncomeDialog(context),
          ),
        if (archivedIncomes.isNotEmpty)
          ExpansionTile(
            title: Text('Archived income (${archivedIncomes.length})'),
            children: <Widget>[
              for (final i in archivedIncomes)
                _IncomeTile(source: i, received: false),
            ],
          ),
        const Divider(height: 32),

        // Bills
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text('Monthly bills', style: sectionStyle),
        ),
        if (active.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Text(
              s.billsLeftCount == 0
                  ? 'All bills paid this month'
                  : '${s.billsLeftCount} left · ${formatPeso(s.billsLeftAmount)}',
              style: noteStyle,
            ),
          ),
        for (final b in active)
          _BillTile(bill: b, paid: b.id != null && s.paidBillIds.contains(b.id)),
        if (active.isEmpty)
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add a monthly bill'),
            subtitle: const Text('Rent, electricity, internet…'),
            onTap: () => showNewBillDialog(context),
          ),
        if (archived.isNotEmpty)
          ExpansionTile(
            title: Text('Archived bills (${archived.length})'),
            children: <Widget>[
              for (final b in archived) _BillTile(bill: b, paid: false),
            ],
          ),
      ],
    );
  }
}

class _IncomeTile extends StatelessWidget {
  const _IncomeTile({required this.source, required this.received});

  final IncomeSource source;
  final bool received;

  Future<void> _onAction(BuildContext context, _IncomeAction action) async {
    final state = AppScope.read(context);
    try {
      switch (action) {
        case _IncomeAction.edit:
          await showEditIncomeDialog(context, source);
        case _IncomeAction.archive:
          await state.setIncomeActive(source, false);
        case _IncomeAction.unarchive:
          await state.setIncomeActive(source, true);
        case _IncomeAction.delete:
          final ok = await confirm(
            context,
            title: 'Delete ${source.name}?',
            message: 'This monthly income will be removed.',
            confirmLabel: 'Delete',
            destructive: true,
          );
          if (!ok) return;
          await state.deleteIncome(source);
      }
    } on ActionNotAllowed catch (e) {
      if (!context.mounted) return;
      showMessage(context, e.message);
    } catch (e) {
      if (!context.mounted) return;
      showMessage(context, 'Something went wrong: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget trailingState;
    if (!source.active) {
      trailingState = const SizedBox.shrink();
    } else if (received) {
      trailingState = Chip(
        avatar: Icon(Icons.check, size: 16, color: incomeColor(context)),
        label: const Text('Received'),
        visualDensity: VisualDensity.compact,
      );
    } else {
      trailingState = FilledButton.tonal(
        onPressed: () => showReceiveIncome(context, source),
        child: const Text('Receive'),
      );
    }

    return ListTile(
      title: Text(source.name),
      subtitle: Text(
        '${formatPeso(source.amount)} · every ${ordinalDay(source.day)}',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFeatures: tabularFigures,
        ),
      ),
      onTap: () => showEditIncomeDialog(context, source),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          trailingState,
          PopupMenuButton<_IncomeAction>(
            tooltip: 'More',
            onSelected: (a) => _onAction(context, a),
            itemBuilder: (_) => <PopupMenuEntry<_IncomeAction>>[
              const PopupMenuItem<_IncomeAction>(
                value: _IncomeAction.edit,
                child: Text('Edit'),
              ),
              if (source.active)
                const PopupMenuItem<_IncomeAction>(
                  value: _IncomeAction.archive,
                  child: Text('Archive'),
                )
              else
                const PopupMenuItem<_IncomeAction>(
                  value: _IncomeAction.unarchive,
                  child: Text('Unarchive'),
                ),
              const PopupMenuItem<_IncomeAction>(
                value: _IncomeAction.delete,
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill, required this.paid});

  final Bill bill;
  final bool paid;

  void _pay(BuildContext context) {
    showPayBill(context, bill);
  }

  Future<void> _onAction(BuildContext context, _BillAction action) async {
    final state = AppScope.read(context);
    try {
      switch (action) {
        case _BillAction.edit:
          await showEditBillDialog(context, bill);
        case _BillAction.archive:
          await state.setBillActive(bill, false);
        case _BillAction.unarchive:
          await state.setBillActive(bill, true);
        case _BillAction.delete:
          final ok = await confirm(
            context,
            title: 'Delete ${bill.name}?',
            message: 'This bill will be removed.',
            confirmLabel: 'Delete',
            destructive: true,
          );
          if (!ok) return;
          await state.deleteBill(bill);
      }
    } on ActionNotAllowed catch (e) {
      if (!context.mounted) return;
      showMessage(context, e.message);
    } catch (e) {
      if (!context.mounted) return;
      showMessage(context, 'Something went wrong: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget trailingState;
    if (!bill.active) {
      trailingState = const SizedBox.shrink();
    } else if (paid) {
      trailingState = Chip(
        avatar: Icon(Icons.check, size: 16, color: incomeColor(context)),
        label: const Text('Paid'),
        visualDensity: VisualDensity.compact,
      );
    } else {
      trailingState = FilledButton.tonal(
        onPressed: () => _pay(context),
        child: const Text('Pay'),
      );
    }

    return ListTile(
      title: Text(bill.name),
      subtitle: Text(
        '${formatPeso(bill.amount)} a month',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFeatures: tabularFigures,
        ),
      ),
      onTap: () => showEditBillDialog(context, bill),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          trailingState,
          PopupMenuButton<_BillAction>(
            tooltip: 'More',
            onSelected: (a) => _onAction(context, a),
            itemBuilder: (_) => <PopupMenuEntry<_BillAction>>[
              const PopupMenuItem<_BillAction>(
                value: _BillAction.edit,
                child: Text('Edit'),
              ),
              if (bill.active)
                const PopupMenuItem<_BillAction>(
                  value: _BillAction.archive,
                  child: Text('Archive'),
                )
              else
                const PopupMenuItem<_BillAction>(
                  value: _BillAction.unarchive,
                  child: Text('Unarchive'),
                ),
              const PopupMenuItem<_BillAction>(
                value: _BillAction.delete,
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
