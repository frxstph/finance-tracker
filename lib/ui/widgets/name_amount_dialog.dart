import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../state/app_state.dart';
import 'amount_field.dart';
import 'dialogs.dart';

typedef NameAmount = ({String name, int amount});

/// A small dialog asking for a name and an amount. Returns null on cancel.
class NameAmountDialog extends StatefulWidget {
  const NameAmountDialog({
    super.key,
    required this.title,
    required this.nameLabel,
    required this.amountLabel,
    this.initialName = '',
    this.initialAmount,
  });

  final String title;
  final String nameLabel;
  final String amountLabel;
  final String initialName;
  final int? initialAmount;

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
  String? _nameError;
  String? _amountError;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final amount = parseCentavos(_amount.text);
    setState(() {
      _nameError = name.isEmpty ? 'Enter a name' : null;
      _amountError =
          amount == null || amount <= 0 ? 'Enter an amount above ₱0' : null;
    });
    if (name.isEmpty || amount == null || amount <= 0) return;
    final NameAmount result = (name: name, amount: amount);
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
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
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
}) {
  return showDialog<NameAmount>(
    context: context,
    builder: (_) => NameAmountDialog(
      title: title,
      nameLabel: nameLabel,
      amountLabel: amountLabel,
      initialName: initialName,
      initialAmount: initialAmount,
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
