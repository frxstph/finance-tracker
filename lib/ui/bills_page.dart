import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import '../state/app_state.dart';
import 'pay_pages.dart';
import 'theme.dart';
import 'widgets/dialogs.dart';
import 'widgets/empty_state.dart';
import 'widgets/month_switcher.dart';
import 'widgets/name_amount_dialog.dart';

enum _BillAction { edit, archive, unarchive, delete }

/// Active bills with paid/unpaid state for the selected month.
class BillsPage extends StatelessWidget {
  const BillsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final active = state.activeBills;
    final archived = state.archivedBills;

    if (state.loaded && active.isEmpty && archived.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'Keep track of what you pay every month.',
        actionLabel: 'Add your first bill',
        onAction: () => showNewBillDialog(context),
      );
    }

    final s = state.summary;
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        const MonthSwitcher(),
        if (active.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              s.billsLeftCount == 0
                  ? 'All bills paid this month'
                  : '${s.billsLeftCount} left · ${formatPeso(s.billsLeftAmount)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        for (final b in active)
          _BillTile(bill: b, paid: b.id != null && s.paidBillIds.contains(b.id)),
        if (active.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No active bills. Add one with the button above.'),
          ),
        if (archived.isNotEmpty)
          ExpansionTile(
            title: Text('Archived (${archived.length})'),
            children: <Widget>[
              for (final b in archived) _BillTile(bill: b, paid: false),
            ],
          ),
      ],
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
