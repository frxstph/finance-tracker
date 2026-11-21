import 'package:flutter/material.dart';

import '../../domain/money.dart';
import '../../state/app_state.dart';
import 'amount_field.dart';
import 'dialogs.dart';

/// "Count my cash": type what is actually in your wallet; the difference
/// from the app's cash becomes an adjustment (up or down) dated today.
Future<void> showCountCashDialog(BuildContext context) async {
  final state = AppScope.read(context);
  final actual = await showDialog<int>(
    context: context,
    builder: (_) => _CountCashDialog(appCash: state.cashNow),
  );
  if (actual == null || !context.mounted) return;
  try {
    final diff = await state.countCash(actual);
    if (!context.mounted) return;
    showMessage(
      context,
      diff == 0
          ? 'Already matches. Nothing changed.'
          : diff > 0
              ? 'Added ${formatPeso(diff)} to cash'
              : 'Took ${formatPeso(-diff)} from cash',
    );
  } catch (e) {
    if (!context.mounted) return;
    showMessage(context, 'Could not save: $e');
  }
}

class _CountCashDialog extends StatefulWidget {
  const _CountCashDialog({required this.appCash});

  final int appCash;

  @override
  State<_CountCashDialog> createState() => _CountCashDialogState();
}

class _CountCashDialogState extends State<_CountCashDialog> {
  final TextEditingController _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final value = parseCentavos(_amount.text);
    if (value == null) {
      setState(() => _error = 'Enter an amount');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = parseCentavos(_amount.text);
    final diff = value == null ? null : value - widget.appCash;
    String? diffText;
    if (diff != null) {
      diffText = diff == 0
          ? 'Matches the app'
          : diff > 0
              ? 'Adds ${formatPeso(diff)} as an adjustment'
              : 'Takes ${formatPeso(-diff)} off as an adjustment';
    }
    return AlertDialog(
      title: const Text('Count your cash'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('The app has ${formatPeso(widget.appCash)} up to today.'),
            const SizedBox(height: 16),
            AmountField(
              controller: _amount,
              label: 'Cash you actually have',
              autofocus: true,
              errorText: _error,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
            ),
            if (diffText != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(diffText, style: theme.textTheme.bodyMedium),
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
