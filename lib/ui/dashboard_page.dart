import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/summary.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/month_switcher.dart';
import 'widgets/stat_card.dart';

/// Home screen. "Now" shows the selected month as recorded; "If all paid"
/// shows where cash and net position land if every expected income arrives
/// and every bill and loan payment is made, month by month up to the
/// selected one.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _forecast = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    final forecast = _forecast ? state.forecast : null;

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        const MonthSwitcher(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const Text('Now'),
                selected: !_forecast,
                onSelected: (_) => setState(() => _forecast = false),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.auto_graph, size: 18),
                label: const Text('If all paid'),
                selected: _forecast,
                onSelected: (_) => setState(() => _forecast = true),
              ),
            ],
          ),
        ),
        if (_forecast && forecast == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'This month is over, so this shows what actually happened.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (forecast != null) ...<Widget>[
          _ForecastCards(f: forecast),
          const SizedBox(height: 8),
          _ForecastSteps(
            f: forecast,
            projectedStart: forecast.month != state.currentMonthKey,
          ),
        ] else
          const _NowCards(),
        const SizedBox(height: 8),
        const _BreakdownCard(),
      ],
    );
  }
}

/// Two rows of two equal cards.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: cards[0]),
              Expanded(child: cards[1]),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: cards[2]),
              Expanded(child: cards[3]),
            ],
          ),
        ],
      ),
    );
  }
}

/// Green when above zero, red when below, plain at zero.
Color? _signColor(BuildContext context, int v) =>
    v > 0 ? incomeColor(context) : (v < 0 ? debtColor(context) : null);

class _NowCards extends StatelessWidget {
  const _NowCards();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).summary;
    final leftParts = <String>[
      if (s.billsLeftCount > 0)
        '${s.billsLeftCount} ${s.billsLeftCount == 1 ? 'bill' : 'bills'}',
      if (s.loanDueCount > 0)
        '${s.loanDueCount} ${s.loanDueCount == 1 ? 'loan' : 'loans'} due',
    ];
    final leftDetail = leftParts.isEmpty ? 'All paid' : leftParts.join(', ');
    return _CardGrid(cards: <Widget>[
      StatCard(
        label: 'Cash on hand',
        icon: Icons.account_balance_wallet_outlined,
        value: formatPeso(s.cash),
        valueColor: _signColor(context, s.cash),
        detail: 'Started month with ${formatPeso(s.openingCash)}',
      ),
      StatCard(
        label: 'Still owed',
        icon: Icons.account_balance_outlined,
        value: formatPeso(s.stillOwed),
        valueColor: s.stillOwed > 0 ? debtColor(context) : null,
        detail: 'All loans',
      ),
      StatCard(
        label: 'Left to pay',
        icon: Icons.receipt_long_outlined,
        value: formatPeso(s.leftToPayAmount),
        valueColor: s.leftToPayAmount > 0 ? billsColor(context) : null,
        detail: leftDetail,
      ),
      StatCard(
        label: 'Net position',
        icon: Icons.balance_outlined,
        value: formatPeso(s.netPosition),
        valueColor: _signColor(context, s.netPosition),
        detail: 'After loans and bills',
      ),
    ]);
  }
}

class _ForecastCards extends StatelessWidget {
  const _ForecastCards({required this.f});

  final ForecastMonth f;

  @override
  Widget build(BuildContext context) {
    return _CardGrid(cards: <Widget>[
      StatCard(
        label: 'Cash at month end',
        icon: Icons.account_balance_wallet_outlined,
        value: formatPeso(f.endCash),
        valueColor: _signColor(context, f.endCash),
        detail: 'If all paid',
      ),
      StatCard(
        label: 'Owed after',
        icon: Icons.account_balance_outlined,
        value: formatPeso(f.owedAfter),
        valueColor: f.owedAfter > 0 ? debtColor(context) : null,
        detail: 'After this month’s payments',
      ),
      StatCard(
        label: 'Still coming in',
        icon: Icons.arrow_downward,
        value: formatPeso(f.incomeToCome),
        valueColor: f.incomeToCome > 0 ? incomeColor(context) : null,
        detail: 'Monthly income',
      ),
      StatCard(
        label: 'Net position',
        icon: Icons.balance_outlined,
        value: formatPeso(f.netPosition),
        valueColor: _signColor(context, f.netPosition),
        detail: 'Month end, after loans',
      ),
    ]);
  }
}

/// The forecast as a sum: start, plus and minus each part, equals the end.
class _ForecastSteps extends StatelessWidget {
  const _ForecastSteps({required this.f, required this.projectedStart});

  final ForecastMonth f;
  final bool projectedStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        theme.textTheme.bodyLarge?.copyWith(fontFeatures: tabularFigures);
    final bold = style?.copyWith(fontWeight: FontWeight.w600);

    Widget row(String label, int amount,
        {Color? color, bool strong = false, bool signed = true}) {
      final sign = signed && amount > 0 ? '+' : '';
      return ListTile(
        dense: true,
        title: Text(label, style: strong ? bold : null),
        trailing: Text(
          '$sign${formatPeso(amount)}',
          style: (strong ? bold : style)?.copyWith(color: color),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('How it adds up', style: theme.textTheme.titleSmall),
            ),
            row(projectedStart ? 'Cash at start (forecast)' : 'Cash at start',
                f.startCash,
                signed: false),
            if (f.recorded != 0)
              row('Already recorded this month', f.recorded),
            row('Income still to come', f.incomeToCome,
                color: incomeColor(context)),
            row('Bills to pay', -f.billsToPay, color: billsColor(context)),
            row('Loan payments', -f.loanPayments, color: debtColor(context)),
            const Divider(indent: 16, endIndent: 16),
            row('Cash at month end', f.endCash,
                color: _signColor(context, f.endCash),
                strong: true,
                signed: false),
          ],
        ),
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard();

  static const List<EntryType> _order = <EntryType>[
    EntryType.income,
    EntryType.loanReceived,
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
      case EntryType.loanReceived:
        return 'Loans received';
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
