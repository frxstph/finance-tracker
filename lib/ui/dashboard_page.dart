import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/month_switcher.dart';
import 'widgets/stat_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final s = state.summary;
    final danger = Theme.of(context).colorScheme.error;
    final billsDetail = s.billsLeftCount == 0
        ? 'All paid'
        : '${s.billsLeftCount} ${s.billsLeftCount == 1 ? 'bill' : 'bills'} unpaid';

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        const MonthSwitcher(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: StatCard(
                      label: 'Cash on hand',
                      icon: Icons.account_balance_wallet_outlined,
                      value: formatPeso(s.cash),
                      valueColor: s.cash < 0 ? danger : null,
                      detail: 'This month only',
                    ),
                  ),
                  Expanded(
                    child: StatCard(
                      label: 'Still owed',
                      icon: Icons.account_balance_outlined,
                      value: formatPeso(s.stillOwed),
                      detail: 'All loans',
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: StatCard(
                      label: 'Bills left',
                      icon: Icons.receipt_long_outlined,
                      value: formatPeso(s.billsLeftAmount),
                      detail: billsDetail,
                    ),
                  ),
                  Expanded(
                    child: StatCard(
                      label: 'Net position',
                      icon: Icons.balance_outlined,
                      value: formatPeso(s.netPosition),
                      valueColor: s.netPosition < 0 ? danger : null,
                      detail: 'Cash minus still owed',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const _BreakdownCard(),
      ],
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard();

  static const List<EntryType> _order = <EntryType>[
    EntryType.income,
    EntryType.bill,
    EntryType.oneTime,
    EntryType.daily,
    EntryType.loanPayment,
  ];

  String _label(EntryType t) {
    switch (t) {
      case EntryType.income:
        return 'Income';
      case EntryType.bill:
        return 'Bills';
      case EntryType.oneTime:
        return 'One-time';
      case EntryType.daily:
        return 'Daily';
      case EntryType.loanPayment:
        return 'Loan payments';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).summary;
    final theme = Theme.of(context);
    final amountStyle =
        theme.textTheme.bodyLarge?.copyWith(fontFeatures: tabularFigures);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('This month', style: theme.textTheme.titleSmall),
            ),
            for (final t in _order)
              ListTile(
                dense: true,
                leading: Icon(iconForType(t)),
                title: Text(_label(t)),
                trailing: Text(
                  formatPeso(s.breakdown[t] ?? 0),
                  style: amountStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
