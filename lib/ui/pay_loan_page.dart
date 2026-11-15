import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/summary.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/amount_field.dart';
import 'widgets/dialogs.dart';
import 'widgets/photo_section.dart';

/// The short "confirm payment" screen behind a loan's Pay button: the amount
/// is already filled in (this month's payment), you add a photo and confirm.
class PayLoanPage extends StatefulWidget {
  const PayLoanPage({super.key, required this.loan});

  final Loan loan;

  @override
  State<PayLoanPage> createState() => _PayLoanPageState();
}

class _PayLoanPageState extends State<PayLoanPage> {
  final TextEditingController _amount = TextEditingController();
  bool _editingAmount = false;
  bool _ready = false;
  String? _amountError;
  String? _photoPath;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    final state = AppScope.read(context);
    _amount.text = centavosToInput(state.loanPaymentSuggestion(widget.loan));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// "Due this month", "Payment 2 of 6 · Jan 2027" or "Due Dec 2026".
  String _whatLine(AppState state) {
    final loan = widget.loan;
    if (state.loanDueOf(loan) > 0) return 'Due this month';
    if (loan.plan == LoanPlan.full) {
      return 'Full payment · due ${shortMonthLabel(loan.startMonth)}';
    }
    final covered = paymentsCovered(loan, state.loanPaid(loan));
    final next = covered + 1 > loan.paymentCount ? loan.paymentCount : covered + 1;
    final month =
        monthKey(addMonths(parseMonthKey(loan.startMonth), next - 1));
    return 'Payment $next of ${loan.paymentCount} · ${shortMonthLabel(month)}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _confirm() async {
    if (_saving) return;
    final amount = parseCentavos(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() {
        _editingAmount = true;
        _amountError = 'Enter an amount above ₱0';
      });
      return;
    }
    final state = AppScope.read(context);
    final entry = Entry(
      type: EntryType.loanPayment,
      amount: amount,
      date: dateKey(_date),
      loanId: widget.loan.id,
      createdAt: DateTime.now().toIso8601String(),
    );
    setState(() => _saving = true);
    try {
      await state.saveEntry(
        entry,
        photoChange:
            _photoPath == null ? PhotoChange.keep : PhotoChange.replace,
        newPhotoPath: _photoPath,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Could not save: $e');
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text('Paid ${formatPeso(amount)} on ${widget.loan.name}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final balance = state.loanBalanceOf(widget.loan);
    final amount = parseCentavos(_amount.text) ?? 0;
    final after = balance - amount < 0 ? 0 : balance - amount;
    final numbers = theme.textTheme.bodyLarge
        ?.copyWith(fontFeatures: tabularFigures);
    final photo = _photoPath == null ? null : File(_photoPath!);

    return Scaffold(
      appBar: AppBar(title: Text('Pay ${widget.loan.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          Text(
            _whatLine(state),
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (_editingAmount)
            AmountField(
              controller: _amount,
              autofocus: true,
              errorText: _amountError,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _amountError = null),
              onSubmitted: (_) => setState(() => _editingAmount = false),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    formatPeso(amount),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _editingAmount = true),
                  child: const Text('Change'),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Text('Balance after this: ${formatPeso(after)}', style: numbers),
          const SizedBox(height: 24),
          PhotoSection(
            file: photo,
            addLabel: 'Add photo of payment',
            onPicked: (path) {
              if (!mounted) return;
              setState(() => _photoPath = path);
            },
            onRemove: () => setState(() => _photoPath = null),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(dayLabel(_date)),
            subtitle: const Text('Date paid'),
            onTap: _pickDate,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _saving ? null : _confirm,
            icon: const Icon(Icons.check),
            label: const Text('Confirm payment'),
          ),
        ),
      ),
    );
  }
}
