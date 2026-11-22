import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/money.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/dialogs.dart';

/// Opens the screen to give bills and loans their due day.
Future<void> showDueDaysPage(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const DueDaysPage(),
    ),
  );
}

/// One screen listing every bill and loan with no due day, each with a
/// "day of the month" box, so plans and warnings place them correctly.
class DueDaysPage extends StatefulWidget {
  const DueDaysPage({super.key});

  @override
  State<DueDaysPage> createState() => _DueDaysPageState();
}

class _DueDaysPageState extends State<DueDaysPage> {
  final Map<String, TextEditingController> _days =
      <String, TextEditingController>{};
  bool _saving = false;

  TextEditingController _controller(String key) =>
      _days.putIfAbsent(key, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _days.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? _day(String key) {
    final n = int.tryParse(_days[key]?.text.trim() ?? '');
    return n != null && n >= 1 && n <= 31 ? n : null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final state = AppScope.read(context);
    final bills = <int, int>{};
    final loans = <int, int>{};
    for (final b in state.billsWithoutDueDay) {
      final d = _day('b${b.id}');
      if (d != null && b.id != null) bills[b.id!] = d;
    }
    for (final l in state.loansWithoutDueDay) {
      final d = _day('l${l.id}');
      if (d != null && l.id != null) loans[l.id!] = d;
    }
    if (bills.isEmpty && loans.isEmpty) {
      showMessage(context, 'Enter at least one day from 1 to 31');
      return;
    }
    setState(() => _saving = true);
    try {
      await state.setDueDays(bills: bills, loans: loans);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Could not save: $e');
      return;
    }
    if (!mounted) return;
    final n = bills.length + loans.length;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
        SnackBar(content: Text('Due days set for $n ${n == 1 ? 'item' : 'items'}')));
  }

  Widget _row(BuildContext context, String key, String name, String amount) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name, style: theme.textTheme.titleMedium),
                Text(amount,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: tabularFigures,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _controller(key),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: const InputDecoration(
                labelText: 'Day',
                hintText: '1–31',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final bills = state.billsWithoutDueDay;
    final loans = state.loansWithoutDueDay;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set due days'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Which day of the month is each one usually paid? Until it has '
            'a day, the app counts it on the 1st, before your pay comes in, '
            'which can make you look short when you aren’t.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          if (bills.isEmpty && loans.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text('Everything has a due day.',
                  style: theme.textTheme.titleMedium),
            ),
          if (bills.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text('Bills', style: theme.textTheme.titleSmall),
            for (final b in bills)
              _row(context, 'b${b.id}', b.name,
                  '${formatPeso(b.amount)} a month'),
          ],
          if (loans.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text('Loans', style: theme.textTheme.titleSmall),
            for (final l in loans)
              _row(context, 'l${l.id}', l.name,
                  '${formatPeso(state.loanPaymentSuggestion(l))} a payment'),
          ],
          const SizedBox(height: 16),
          Text(
            'Leave a box empty to skip it. You can change days later by '
            'editing the bill or loan.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
