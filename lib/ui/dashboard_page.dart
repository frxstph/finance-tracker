import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
import 'widgets/due_day_nudge.dart';
import 'widgets/info_card.dart';
import 'widgets/stat_card.dart';

/// Home screen. "Today" shows the selected month as recorded; "Plan ahead"
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
          child: Row(
            children: <Widget>[
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('Today'),
                      selected: !_forecast,
                      onSelected: (_) => setState(() => _forecast = false),
                    ),
                    ChoiceChip(
                      avatar: const Icon(Icons.auto_graph, size: 18),
                      label: const Text('Plan ahead'),
                      selected: _forecast,
                      onSelected: (_) => setState(() => _forecast = true),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const _TodayDate(),
            ],
          ),
        ),
        if (_forecast)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'If your monthly income comes in and every bill and loan is '
              'paid on time.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const DueDayNudge(),
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
            _SafeToSpendCard(
              s: state.safeToSpendNow,
              missingDueDays: state.missingDueDays,
            ),
          const _NowCards(),
        ],
        const SizedBox(height: 8),
        const _BreakdownCard(),
      ],
    );
  }
}

/// Today's date, "22" over "Sun", at the end of the Today / Plan ahead row.
/// Always today, whichever month is being looked at.
class _TodayDate extends StatelessWidget {
  const _TodayDate();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final day = DateFormat('EEE').format(now);
    return Semantics(
      label: 'Today is ${DateFormat('EEEE d MMMM').format(now)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${now.day}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          Text(
            day,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Safe to spend, said in one sentence: "₱650 a day until payday" or
/// "Hold off spending: you'll be ₱6,458 short around 1–7 Dec". Tap for how
/// it is worked out.
class _SafeToSpendCard extends StatelessWidget {
  const _SafeToSpendCard({required this.s, required this.missingDueDays});

  final SafeToSpend s;
  final int missingDueDays;

  String get _payday {
    final name = s.paydayName;
    return name == null
        ? 'the end of the month'
        : '$name on the ${ordinalDay(s.payday.day)}';
  }

  /// "before payday" or "around 1–7 Dec".
  String get _where {
    if (s.free <= s.lowestAhead) return 'before payday';
    final mon = shortMonthLabel(s.lowestMonth).split(' ').first;
    return 'around ${s.lowestFirstDay}–${s.lowestLastDay} $mon';
  }

  void _explain(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        Widget line(String label, String value,
            {Color? color, bool bold = false}) {
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

        final laterIsLower = s.lowestAhead < s.free;
        final mon = shortMonthLabel(s.lowestMonth).split(' ').first;
        return AlertDialog(
          title: const Text('How this is worked out'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                line('Cash now', formatPeso(s.cashNow),
                    color: balanceColor(dialogContext, s.cashNow)),
                line('Due before payday', signedPeso(-s.dueBeforePayday),
                    color: flowColor(dialogContext, -s.dueBeforePayday)),
                const Divider(),
                line('Left before payday', formatPeso(s.free),
                    color: balanceColor(dialogContext, s.free)),
                if (laterIsLower) ...<Widget>[
                  line(
                    'Lowest later (${s.lowestFirstDay}–${s.lowestLastDay} $mon)',
                    formatPeso(s.lowestAhead),
                    color: balanceColor(dialogContext, s.lowestAhead),
                  ),
                  Text(
                    'Even after payday, bills in that week bring your cash '
                    'down to this, so the app plans around it.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const Divider(),
                if (s.short)
                  line('Short by', formatPeso(-s.budget),
                      color: debtColor(dialogContext), bold: true)
                else ...<Widget>[
                  line('You can spend', formatPeso(s.budget), bold: true),
                  line('Each day for ${s.days} '
                      '${s.days == 1 ? 'day' : 'days'}',
                      formatPeso(s.perDay),
                      color: s.perDay > 0 ? incomeColor(dialogContext) : null,
                      bold: true),
                ],
                const SizedBox(height: 12),
                Text(
                  s.short
                      ? 'To fix it: spend only on essentials, move a payment '
                          'later, or add income you expect.'
                      : 'Spend up to this each day and every bill and loan '
                          'payment until the end of next month is still '
                          'covered.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (missingDueDays > 0) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '$missingDueDays ${missingDueDays == 1 ? 'item has' : 'items have'} '
                    'no due day and ${missingDueDays == 1 ? 'is' : 'are'} '
                    'counted on the 1st. Set due days for a truer number.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: billsColor(dialogContext)),
                  ),
                ],
              ],
            ),
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

  /// "Payday in 8 days", "Payday tomorrow", "Payday today"; null when
  /// there is no monthly income to count down to.
  String? get _countdown {
    if (s.paydayName == null) return null;
    if (s.days <= 0) return 'Payday today';
    if (s.days == 1) return 'Payday tomorrow';
    return 'Payday in ${s.days} days';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final short = s.short;
    // A daily budget reads better in whole pesos; round down to stay safe.
    final perDay = s.perDay ~/ 100 * 100;
    final nothing = !short && perDay == 0;
    final color = short
        ? debtColor(context)
        : nothing
            ? billsColor(context)
            : incomeColor(context);
    final String headline;
    final String sentence;
    if (short) {
      headline = 'Hold off spending';
      sentence = 'You’ll be ${formatPeso(-s.budget)} short $_where, even '
          'if every bill is paid on time.';
    } else if (nothing) {
      headline = 'Nothing spare';
      sentence = 'Everything you have is needed until $_payday.';
    } else {
      headline = '${formatPeso(perDay)} a day';
      sentence = s.keptForLater > 0
          ? 'Until $_payday. Bills after payday are already covered.'
          : 'Until $_payday, with all bills covered.';
    }
    final countdown = _countdown;
    return InfoCard(
      icon: short ? Icons.front_hand_outlined : Icons.savings_outlined,
      iconColor: color,
      title: 'Safe to spend',
      trailing: countdown == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.event_outlined,
                      size: 14, color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 4),
                  Text(
                    countdown,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
      headline: headline,
      headlineColor: color,
      body: sentence,
      onTap: () => _explain(context),
      actions: <InfoCardAction>[
        InfoCardAction('See how', () => _explain(context)),
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
        detail: 'Tap to count',
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
        label: 'Month-end cash',
        icon: Icons.account_balance_wallet_outlined,
        value: formatPeso(f.endCash),
        valueColor: _signColor(context, f.endCash),
        detail: 'After all bills',
      ),
      StatCard(
        label: 'Loans left',
        icon: Icons.account_balance_outlined,
        value: formatPeso(f.owedAfter),
        valueColor: f.owedAfter > 0 ? debtColor(context) : null,
        detail: 'After this month',
      ),
      StatCard(
        label: 'Pay to come',
        icon: Icons.arrow_downward,
        value: formatPeso(f.incomeToCome),
        valueColor: f.incomeToCome > 0 ? incomeColor(context) : null,
        detail: 'This month',
      ),
      StatCard(
        label: 'Net position',
        icon: Icons.balance_outlined,
        value: formatPeso(f.netPosition),
        valueColor: _signColor(context, f.netPosition),
        detail: 'Cash minus loans',
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

/// "Plan ahead", block by block: 1–7, 8–14, 15–21, 22–end. Warns about the
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
