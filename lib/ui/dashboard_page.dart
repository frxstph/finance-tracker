import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/calc.dart';
import '../domain/dates.dart';
import '../domain/summary.dart';
import '../domain/weeks.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/month_switcher.dart';
import 'widgets/count_cash_dialog.dart';
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
          const SizedBox(height: 8),
          _WeekBlocksCard(
            month: forecast.month,
            blocks: state.weeksFor(forecast),
          ),
        ] else ...<Widget>[
          if (state.monthKeyValue == state.currentMonthKey)
            _SafeToSpendCard(s: state.safeToSpendNow),
          const _NowCards(),
        ],
        const SizedBox(height: 8),
        const _BreakdownCard(),
      ],
    );
  }
}

/// "Safe to spend: ₱650 a day until payday", tap for how it is worked out.
class _SafeToSpendCard extends StatelessWidget {
  const _SafeToSpendCard({required this.s});

  final SafeToSpend s;

  String _until() {
    final when = dayLabel(s.payday);
    final days = '${s.days} ${s.days == 1 ? 'day' : 'days'}';
    final name = s.paydayName;
    return name == null
        ? 'until $when, end of month · $days'
        : 'until $name on $when · $days';
  }

  void _explain(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        Widget line(String label, String value, {Color? color, bool bold = false}) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(label)),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFeatures: tabularFigures,
                    color: color,
                    fontWeight: bold ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          );
        }

        return AlertDialog(
          title: const Text('Safe to spend'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              line('Cash now', formatPeso(s.cashNow),
                  color: balanceColor(dialogContext, s.cashNow)),
              line('Due before payday', signedPeso(-s.dueBeforePayday),
                  color: flowColor(dialogContext, -s.dueBeforePayday)),
              const Divider(),
              line('Free to use', formatPeso(s.free),
                  color: balanceColor(dialogContext, s.free), bold: true),
              line('Days until payday', '${s.days}'),
              const Divider(),
              line('Each day', formatPeso(s.perDay),
                  color: s.perDay > 0 ? incomeColor(dialogContext) : null,
                  bold: true),
              const SizedBox(height: 12),
              Text(
                'Bills and loan payments due before payday are set aside '
                'first. Overdue ones count as due today. Add your monthly '
                'income and due days so this stays accurate.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final short = s.free < 0;
    final color = short ? debtColor(context) : incomeColor(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _explain(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: <Widget>[
              Icon(Icons.savings_outlined, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Safe to spend', style: theme.textTheme.labelLarge),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        short
                            ? 'Short by ${formatPeso(-s.free)}'
                            : '${formatPeso(s.perDay)} a day',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                          color: color,
                        ),
                      ),
                    ),
                    Text(
                      _until(),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
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
        detail: 'Tap to count your cash',
        onTap: () => showCountCashDialog(context),
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

    // A flow line (+ green / − red) or, with balance, a dark total.
    Widget row(String label, int amount,
        {bool strong = false, bool balance = false}) {
      return ListTile(
        dense: true,
        title: Text(label, style: strong ? bold : null),
        trailing: Text(
          balance ? formatPeso(amount) : signedPeso(amount),
          style: (strong ? bold : style)?.copyWith(
            color: balance
                ? balanceColor(context, amount)
                : flowColor(context, amount),
          ),
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
                balance: true),
            if (f.recorded != 0)
              row('Already recorded this month', f.recorded),
            row('Income still to come', f.incomeToCome),
            row('Bills to pay', -f.billsToPay),
            row('Loan payments', -f.loanPayments),
            const Divider(indent: 16, endIndent: 16),
            row('Cash at month end', f.endCash, strong: true, balance: true),
          ],
        ),
      ),
    );
  }
}

/// "If all paid", block by block: 1–7, 8–14, 15–21, 22–end. Warns about the
/// first block that ends with cash below zero.
class _WeekBlocksCard extends StatelessWidget {
  const _WeekBlocksCard({required this.month, required this.blocks});

  final String month;
  final List<WeekBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final monthShort = shortMonthLabel(month).split(' ').first;
    final small = theme.textTheme.bodyMedium
        ?.copyWith(fontFeatures: tabularFigures);

    WeekBlock? short;
    for (final b in blocks) {
      if (!b.past && b.endCash < 0) {
        short = b;
        break;
      }
    }


    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text('Week by week', style: theme.textTheme.titleSmall),
      ),
    ];

    final s = short;
    if (s != null) {
      final red = debtColor(context);
      children.add(Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: red.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, color: red, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Short by ${formatPeso(-s.endCash)} on days '
                '${s.firstDay}–${s.lastDay}. Move a payment later or keep '
                'cash aside.',
                style: theme.textTheme.bodyMedium?.copyWith(color: red),
              ),
            ),
          ],
        ),
      ));
    }

    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (i > 0) {
        children.add(const Divider(indent: 16, endIndent: 16, height: 16));
      }
      final headerStyle = theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: b.past ? muted : null,
      );
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Text(
          '${b.firstDay}–${b.lastDay} $monthShort${b.past ? ' · done' : ''}',
          style: headerStyle,
        ),
      ));
      final rows = <Widget>[
        if (b.recorded != 0)
          _weekRow(context, 'Already recorded', signedPeso(b.recorded), small,
              flowColor(context, b.recorded)),
        for (final item in b.items)
          _weekRow(
            context,
            item.dayKnown
                ? '${ordinalDay(item.day)} · ${item.label}'
                : '${item.label} · no due day',
            signedPeso(item.amount),
            small,
            flowColor(context, item.amount),
          ),
      ];
      if (rows.isEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
          child: Text('Nothing due', style: small?.copyWith(color: muted)),
        ));
      }
      children.addAll(rows);
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Cash after',
                style: small?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              formatPeso(b.endCash),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: tabularFigures,
                color: balanceColor(context, b.endCash),
              ),
            ),
          ],
        ),
      ));
    }
    children.add(const SizedBox(height: 8));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _weekRow(BuildContext context, String label, String amount,
      TextStyle? style, Color? color) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 1, 16, 1),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: style?.copyWith(color: muted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(amount, style: style?.copyWith(color: color)),
        ],
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
      case EntryType.adjustIn:
      case EntryType.adjustOut:
        return 'Adjustments';
    }
  }

  Widget _flowTile(
      BuildContext context, IconData icon, String label, int signed) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(
        signedPeso(signed),
        style: theme.textTheme.bodyLarge?.copyWith(
          fontFeatures: tabularFigures,
          color: flowColor(context, signed),
        ),
      ),
    );
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
              _flowTile(
                context,
                iconForType(t),
                _label(t),
                t.isMoneyIn ? (s.breakdown[t] ?? 0) : -(s.breakdown[t] ?? 0),
              ),
            if (s.adjustments != 0)
              _flowTile(context, iconForType(EntryType.adjustIn),
                  _label(EntryType.adjustIn), s.adjustments),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              dense: true,
              title: Text('Net this month',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              trailing: Text(
                signedPeso(s.monthChange),
                style: amountStyle?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: flowColor(context, s.monthChange),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
