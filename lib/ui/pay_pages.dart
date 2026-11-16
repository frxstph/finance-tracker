import 'package:flutter/material.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/summary.dart';
import '../state/app_state.dart';
import 'confirm_payment_page.dart';

/// Date a payment for the selected month defaults to: today when that month
/// is this month, otherwise its first day (so it counts for that month).
DateTime _defaultPayDate(AppState state) {
  final now = DateTime.now();
  return monthKey(now) == state.monthKeyValue ? now : state.month;
}

Future<void> _open(BuildContext context, ConfirmPaymentPage page) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => page),
  );
}

/// Default date for receiving [source] in the selected month: today in the
/// current month, otherwise its usual day in the selected month.
DateTime _defaultReceiveDate(AppState state, IncomeSource source) {
  final now = DateTime.now();
  if (monthKey(now) == state.monthKeyValue) return now;
  return dayInMonth(state.month, source.day);
}

/// Receive [source] for the selected month: usual amount, photo, confirm.
Future<void> showReceiveIncome(BuildContext context, IncomeSource source) {
  final state = AppScope.read(context);
  return _open(
    context,
    ConfirmPaymentPage(
      title: 'Receive ${source.name}',
      what: 'Monthly income · every ${ordinalDay(source.day)}',
      initialAmount: source.amount,
      initialDate: _defaultReceiveDate(state, source),
      photoLabel: 'Add photo (optional)',
      confirmLabel: 'Confirm received',
      doneVerb: 'Received',
      dateLabel: 'Date received',
      afterLine: (amount) => amount == source.amount
          ? 'Usual amount'
          : 'Usual amount ${formatPeso(source.amount)}',
      buildEntry: (amount, date) => Entry(
        type: EntryType.income,
        amount: amount,
        date: date,
        incomeId: source.id,
        createdAt: DateTime.now().toIso8601String(),
      ),
    ),
  );
}

/// Pay [bill] for the selected month: its usual amount, photo, confirm.
Future<void> showPayBill(BuildContext context, Bill bill) {
  final state = AppScope.read(context);
  return _open(
    context,
    ConfirmPaymentPage(
      title: 'Pay ${bill.name}',
      what: 'Monthly bill · ${monthLabel(state.month)}',
      initialAmount: bill.amount,
      initialDate: _defaultPayDate(state),
      photoLabel: 'Add photo of receipt',
      afterLine: (amount) => amount == bill.amount
          ? 'Usual amount'
          : 'Usual amount ${formatPeso(bill.amount)}',
      buildEntry: (amount, date) => Entry(
        type: EntryType.bill,
        amount: amount,
        date: date,
        billId: bill.id,
        createdAt: DateTime.now().toIso8601String(),
      ),
    ),
  );
}

/// "Due this month", "Payment 2 of 6 · Jan 2027" or "Full payment · due …".
String _loanWhat(AppState state, Loan loan) {
  if (state.loanDueOf(loan) > 0) return 'Due this month';
  if (loan.plan == LoanPlan.full) {
    return 'Full payment · due ${shortMonthLabel(loan.startMonth)}';
  }
  final covered = paymentsCovered(loan, state.loanPaid(loan));
  final next =
      covered + 1 > loan.paymentCount ? loan.paymentCount : covered + 1;
  final month = monthKey(addMonths(parseMonthKey(loan.startMonth), next - 1));
  return 'Payment $next of ${loan.paymentCount} · ${shortMonthLabel(month)}';
}

/// Pay [loan]: this month's payment (or the next one), photo, confirm.
Future<void> showPayLoan(BuildContext context, Loan loan) {
  final state = AppScope.read(context);
  final balance = state.loanBalanceOf(loan);
  return _open(
    context,
    ConfirmPaymentPage(
      title: 'Pay ${loan.name}',
      what: _loanWhat(state, loan),
      initialAmount: state.loanPaymentSuggestion(loan),
      afterLine: (amount) {
        final left = balance - amount < 0 ? 0 : balance - amount;
        return 'Balance after this: ${formatPeso(left)}';
      },
      buildEntry: (amount, date) => Entry(
        type: EntryType.loanPayment,
        amount: amount,
        date: date,
        loanId: loan.id,
        createdAt: DateTime.now().toIso8601String(),
      ),
    ),
  );
}
