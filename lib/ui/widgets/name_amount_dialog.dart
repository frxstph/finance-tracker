import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../state/app_state.dart';
import 'amount_field.dart';
import 'dialogs.dart';

typedef NameAmount = ({String name, int amount, int? day});

/// A small dialog asking for a name and an amount, and with [askDay] a day of
/// the month. Returns null on cancel.
class NameAmountDialog extends StatefulWidget {
  const NameAmountDialog({
    super.key,
    required this.title,
    required this.nameLabel,
    required this.amountLabel,
    this.initialName = '',
    this.initialAmount,
    this.askDay = false,
    this.initialDay,
  });

  final String title;
  final String nameLabel;
  final String amountLabel;
  final String initialName;
  final int? initialAmount;
  final bool askDay;
  final int? initialDay;

  @override
  State<NameAmountDialog> createState() => _NameAmountDialogState();
}

class _NameAmountDialogState extends State<NameAmountDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _amount = TextEditingController(
    text: widget.initialAmount == null
        ? ''
        : centavosToInput(widget.initialAmount!),
  );
  late final TextEditingController _day = TextEditingController(
    text: widget.initialDay == null ? '' : '${widget.initialDay}',
  );
  String? _nameError;
  String? _amountError;
  String? _dayError;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _day.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final amount = parseCentavos(_amount.text);
    final day = int.tryParse(_day.text.trim());
    final dayOk = !widget.askDay || (day != null && day >= 1 && day <= 31);
    setState(() {
      _nameError = name.isEmpty ? 'Enter a name' : null;
      _amountError =
          amount == null || amount <= 0 ? 'Enter an amount above ₱0' : null;
      _dayError = dayOk ? null : 'Enter a day from 1 to 31';
    });
    if (name.isEmpty || amount == null || amount <= 0 || !dayOk) return;
    final NameAmount result =
        (name: name, amount: amount, day: widget.askDay ? day : null);
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: widget.nameLabel,
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            AmountField(
              controller: _amount,
              label: widget.amountLabel,
              errorText: _amountError,
              textInputAction:
                  widget.askDay ? TextInputAction.next : TextInputAction.done,
              onSubmitted: (_) {
                if (!widget.askDay) _submit();
              },
            ),
            if (widget.askDay) ...<Widget>[
              const SizedBox(height: 16),
              TextField(
                controller: _day,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Day of the month it comes in',
                  hintText: '19',
                  helperText: '30 or 31 means the last day in short months',
                  errorText: _dayError,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

Future<NameAmount?> _ask(
  BuildContext context, {
  required String title,
  required String nameLabel,
  required String amountLabel,
  String initialName = '',
  int? initialAmount,
  bool askDay = false,
  int? initialDay,
}) {
  return showDialog<NameAmount>(
    context: context,
    builder: (_) => NameAmountDialog(
      title: title,
      nameLabel: nameLabel,
      amountLabel: amountLabel,
      initialName: initialName,
      initialAmount: initialAmount,
      askDay: askDay,
      initialDay: initialDay,
    ),
  );
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (!context.mounted) return;
    showMessage(context, 'Could not save: $e');
  }
}

Future<void> showNewBillDialog(BuildContext context) async {
  final state = AppScope.read(context);
  final r = await _ask(context,
      title: 'New bill', nameLabel: 'Name', amountLabel: 'Monthly amount');
  if (r == null || !context.mounted) return;
  await _run(context,
      () => state.saveBill(Bill(name: r.name, amount: r.amount)));
}

Future<void> showEditBillDialog(BuildContext context, Bill bill) async {
  final state = AppScope.read(context);
  final r = await _ask(context,
      title: 'Edit bill',
      nameLabel: 'Name',
      amountLabel: 'Monthly amount',
      initialName: bill.name,
      initialAmount: bill.amount);
  if (r == null || !context.mounted) return;
  await _run(context,
      () => state.saveBill(bill.copyWith(name: r.name, amount: r.amount)));
}

Future<void> showNewIncomeDialog(BuildContext context) async {
  final state = AppScope.read(context);
  final r = await _ask(context,
      title: 'New monthly income',
      nameLabel: 'Name',
      amountLabel: 'Usual amount',
      askDay: true);
  if (r == null || !context.mounted) return;
  await _run(
      context,
      () => state.saveIncome(
          IncomeSource(name: r.name, amount: r.amount, day: r.day ?? 1)));
}

Future<void> showEditIncomeDialog(
    BuildContext context, IncomeSource source) async {
  final state = AppScope.read(context);
  final r = await _ask(context,
      title: 'Edit monthly income',
      nameLabel: 'Name',
      amountLabel: 'Usual amount',
      initialName: source.name,
      initialAmount: source.amount,
      askDay: true,
      initialDay: source.day);
  if (r == null || !context.mounted) return;
  await _run(
      context,
      () => state.saveIncome(source.copyWith(
          name: r.name, amount: r.amount, day: r.day ?? source.day)));
}
