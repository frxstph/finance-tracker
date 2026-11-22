import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../domain/calc.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../state/app_state.dart';
import 'loan_form_page.dart';
import 'quick_add_page.dart';
import 'theme.dart';
import 'widgets/amount_field.dart';

/// Opens the calculator.
Future<void> showCalculator(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const CalculatorPage()),
  );
}

/// A calculator plus three money tools: loan payments, splitting a bill and
/// "Can I buy it?".
class CalculatorPage extends StatelessWidget {
  const CalculatorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Calculator'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              Tab(text: 'Calculator'),
              Tab(text: 'Loan'),
              Tab(text: 'Split'),
              Tab(text: 'Can I buy it?'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _CalculatorTab(),
            _LoanTab(),
            _SplitTab(),
            _AffordTab(),
          ],
        ),
      ),
    );
  }
}

final NumberFormat _plain = NumberFormat('#,##0.##########', 'en_US');

String _formatNumber(double v) => _plain.format(v);

// ---------------------------------------------------------------------------
// Calculator
// ---------------------------------------------------------------------------

class _CalculatorTab extends StatefulWidget {
  const _CalculatorTab();

  @override
  State<_CalculatorTab> createState() => _CalculatorTabState();
}

class _CalculatorTabState extends State<_CalculatorTab>
    with AutomaticKeepAliveClientMixin<_CalculatorTab> {
  String _line = '';

  /// Most recent first: "12+30" = "42".
  final List<MapEntry<String, String>> _history = <MapEntry<String, String>>[];

  @override
  bool get wantKeepAlive => true;

  static const String _opChars = '+−×÷';

  bool _endsWithOp() =>
      _line.isNotEmpty && _opChars.contains(_line[_line.length - 1]);

  void _press(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (key) {
        case 'C':
          _line = '';
        case '⌫':
          if (_line.isNotEmpty) _line = _line.substring(0, _line.length - 1);
        case '=':
          _equals();
        case '+':
        case '−':
        case '×':
        case '÷':
          if (_line.isEmpty) {
            if (key == '−') _line = '−';
          } else if (_endsWithOp()) {
            final last = _line[_line.length - 1];
            // Allow a minus after × or ÷ ("3×−2"), otherwise swap the sign.
            if (key == '−' && (last == '×' || last == '÷')) {
              _line += key;
            } else if (_line.length > 1) {
              _line = _line.substring(0, _line.length - 1) + key;
            }
          } else {
            _line += key;
          }
        case '.':
          final lastOp = _line.lastIndexOf(RegExp('[+−×÷]'));
          final current = _line.substring(lastOp + 1);
          if (!current.contains('.')) {
            _line += current.isEmpty ? '0.' : '.';
          }
        default:
          if (_line.length < 60) _line += key;
      }
    });
  }

  void _equals() {
    final v = evaluateExpression(_line);
    if (v == null) return;
    final result = _formatNumber(v);
    _history.insert(0, MapEntry<String, String>(_line, result));
    if (_history.length > 10) _history.removeLast();
    _line = result.replaceAll(',', '').replaceAll('-', '−');
  }

  void _useAmount(int centavos) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => QuickAddPage(initialAmount: centavos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final value = evaluateExpression(_line);
    final centavos = resultToCentavos(value);
    final muted = theme.colorScheme.onSurfaceVariant;

    Widget keyButton(String label, {Color? fill, Color? ink}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: 60,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: fill,
                foregroundColor: ink,
                padding: EdgeInsets.zero,
                textStyle: theme.textTheme.headlineSmall,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => _press(label),
              child: Text(label),
            ),
          ),
        ),
      );
    }

    final opFill = theme.colorScheme.secondaryContainer;
    final rows = <List<String>>[
      <String>['C', '⌫', '%', '÷'],
      <String>['7', '8', '9', '×'],
      <String>['4', '5', '6', '−'],
      <String>['1', '2', '3', '+'],
      <String>['00', '0', '.', '='],
    ];

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            children: <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value == null
                        ? (_line.isEmpty ? '0' : ' ')
                        : _formatNumber(value),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _line.isEmpty ? ' ' : _line,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: muted,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
              for (final h in _history)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _line =
                        h.value.replaceAll(',', '').replaceAll('-', '−')),
                    child: Text(
                      '${h.key} = ${h.value}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: muted,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: centavos == null ? null : () => _useAmount(centavos),
              icon: const Icon(Icons.add),
              label: Text(centavos == null
                  ? 'Use this amount'
                  : 'Use ${formatPeso(centavos)} in a new entry'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            children: <Widget>[
              for (final row in rows)
                Row(
                  children: <Widget>[
                    for (final k in row)
                      keyButton(
                        k,
                        fill: k == '='
                            ? theme.colorScheme.primary
                            : ('÷×−+%⌫C'.contains(k) ? opFill : null),
                        ink: k == '=' ? theme.colorScheme.onPrimary : null,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

/// A label and a value on one line.
class _ResultLine extends StatelessWidget {
  const _ResultLine(this.label, this.value, {this.color, this.strong = false});

  final String label;
  final String value;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (strong
            ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)
            : theme.textTheme.bodyLarge)
        ?.copyWith(fontFeatures: tabularFigures, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loan
// ---------------------------------------------------------------------------

class _LoanTab extends StatefulWidget {
  const _LoanTab();

  @override
  State<_LoanTab> createState() => _LoanTabState();
}

class _LoanTabState extends State<_LoanTab>
    with AutomaticKeepAliveClientMixin<_LoanTab> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _months = TextEditingController();
  InterestKind _kind = InterestKind.monthlyAddOn;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    _months.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final principal = parseCentavos(_amount.text);
    final rate = double.tryParse(_rate.text.trim().replaceAll(',', ''));
    final months = int.tryParse(_months.text.trim());
    final quote = principal == null || rate == null || months == null
        ? null
        : quoteLoan(
            principal: principal,
            ratePercent: rate,
            months: months,
            kind: _kind,
          );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        AmountField(
          controller: _amount,
          label: 'Amount you borrow',
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const Text('% a month (add-on)'),
              selected: _kind == InterestKind.monthlyAddOn,
              onSelected: (_) =>
                  setState(() => _kind = InterestKind.monthlyAddOn),
            ),
            ChoiceChip(
              label: const Text('% a year'),
              selected: _kind == InterestKind.yearly,
              onSelected: (_) => setState(() => _kind = InterestKind.yearly),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _rate,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Interest',
                  suffixText:
                      _kind == InterestKind.monthlyAddOn ? '% a month' : '% a year',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _months,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'Months',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _kind == InterestKind.monthlyAddOn
              ? 'Add-on: the monthly rate is charged on the full amount for '
                  'every month. Common for personal and app loans.'
              : 'Yearly: interest is charged on what is left, so it drops as '
                  'you pay. Common for bank loans.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (quote != null)
          _ResultCard(children: <Widget>[
            _ResultLine('Each month', formatPeso(quote.monthly), strong: true),
            _ResultLine('Total you pay back', formatPeso(quote.total)),
            _ResultLine('Total interest', formatPeso(quote.interest),
                color: debtColor(context)),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => showNewLoanForm(
                context,
                principal: quote.total,
                months: months,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add as a loan'),
            ),
          ])
        else
          Text(
            'Enter the amount, interest and months to see the payments.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Split
// ---------------------------------------------------------------------------

class _SplitTab extends StatefulWidget {
  const _SplitTab();

  @override
  State<_SplitTab> createState() => _SplitTabState();
}

class _SplitTabState extends State<_SplitTab>
    with AutomaticKeepAliveClientMixin<_SplitTab> {
  final TextEditingController _amount = TextEditingController();
  int _people = 2;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final total = parseCentavos(_amount.text);
    final split = total == null ? null : splitAmount(total, _people);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        AmountField(
          controller: _amount,
          label: 'Total',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
                child: Text('People', style: theme.textTheme.titleMedium)),
            IconButton.filledTonal(
              tooltip: 'Fewer people',
              onPressed:
                  _people > 1 ? () => setState(() => _people--) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '$_people',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'More people',
              onPressed:
                  _people < 99 ? () => setState(() => _people++) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (split != null)
          _ResultCard(children: <Widget>[
            _ResultLine('Each person pays', formatPeso(split.each),
                strong: true),
            if (split.extra > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'It doesn’t divide evenly: one person pays '
                  '${formatPeso(split.each + split.extra)}.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Can I buy it?
// ---------------------------------------------------------------------------

enum _When { today, payday, pick }

class _AffordTab extends StatefulWidget {
  const _AffordTab();

  @override
  State<_AffordTab> createState() => _AffordTabState();
}

class _AffordTabState extends State<_AffordTab>
    with AutomaticKeepAliveClientMixin<_AffordTab> {
  final TextEditingController _amount = TextEditingController();
  _When _when = _When.today;
  DateTime _picked = DateTime.now();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime _date(AppState state) {
    switch (_when) {
      case _When.today:
        return _today();
      case _When.payday:
        return state.safeToSpendNow.payday;
      case _When.pick:
        return _picked;
    }
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _picked.isBefore(today) ? today : _picked,
      firstDate: today,
      lastDate: DateTime(today.year + 2, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _picked = picked;
      _when = _When.pick;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final safe = state.safeToSpendNow;
    final amount = parseCentavos(_amount.text);
    final date = _date(state);
    final result =
        amount == null || amount <= 0 ? null : state.affordCheck(amount, date);
    final earliest = result == null || result.affordable
        ? null
        : state.earliestAffordableDay(amount!, date);
    final green = incomeColor(context);
    final red = debtColor(context);
    final where = result == null
        ? ''
        : '${result.lowestFirstDay}–${result.lowestLastDay} '
            '${shortMonthLabel(result.lowestMonth).split(' ').first}';
    final paydayLabel = safe.paydayName == null
        ? 'End of month'
        : 'After payday (${ordinalDay(safe.payday.day)})';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Check if you can buy something without running short later.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        AmountField(
          controller: _amount,
          label: 'How much is it?',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text('When would you buy it?', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const Text('Today'),
              selected: _when == _When.today,
              onSelected: (_) => setState(() => _when = _When.today),
            ),
            ChoiceChip(
              label: Text(paydayLabel),
              selected: _when == _When.payday,
              onSelected: (_) => setState(() => _when = _When.payday),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.event_outlined, size: 18),
              label: Text(_when == _When.pick
                  ? dayLabel(_picked)
                  : 'Pick a date'),
              selected: _when == _When.pick,
              onSelected: (_) => _pickDate(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (result != null) ...<Widget>[
          _ResultCard(children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  result.affordable
                      ? Icons.check_circle
                      : Icons.do_not_disturb_on_outlined,
                  color: result.affordable ? green : red,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.affordable
                        ? 'Yes, you can buy it'
                        : 'Not on ${dayLabel(date)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: result.affordable ? green : red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result.affordable
                  ? 'Even at your tightest week after it ($where) you’d '
                      'still have ${formatPeso(result.lowest)}.'
                  : 'You’d be ${formatPeso(-result.lowest)} short around '
                      '$where, before your money comes in.',
              style: theme.textTheme.bodyLarge,
            ),
            if (!result.affordable) ...<Widget>[
              const SizedBox(height: 12),
              if (earliest != null)
                FilledButton.tonalIcon(
                  onPressed: () => setState(() {
                    _picked = earliest;
                    _when = _When.pick;
                  }),
                  icon: const Icon(Icons.event_available),
                  label: Text('Earliest safe day: ${dayLabel(earliest)}'),
                )
              else
                Text(
                  'No safe day in the next 2 months at this price.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: red),
                ),
            ],
          ]),
          const SizedBox(height: 8),
          Text(
            'Assumes your monthly income arrives and every bill and loan '
            'payment is made on time.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
