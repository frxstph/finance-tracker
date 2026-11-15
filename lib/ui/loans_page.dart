import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/summary.dart';
import '../state/app_state.dart';
import 'loan_form_page.dart';
import 'pay_pages.dart';
import 'theme.dart';
import 'widgets/dialogs.dart';
import 'widgets/empty_state.dart';
import 'widgets/month_switcher.dart';
import 'widgets/photo_viewer.dart';

enum _LoanAction { edit, delete }

/// Each loan with what has been paid, the balance and a progress bar.
class LoansPage extends StatelessWidget {
  const LoansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final loans = state.loans;
    if (state.loaded && loans.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_outlined,
        message: 'Track what you owe and watch it go down.',
        actionLabel: 'Add your first loan',
        onAction: () => showNewLoanForm(context),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: <Widget>[
        const MonthSwitcher(),
        for (final l in loans)
          _LoanCard(
            loan: l,
            paid: state.loanPaid(l),
            balance: state.loanBalanceOf(l),
            due: state.loanDueOf(l),
            photo: state.loanPhotoFile(l),
            month: state.monthKeyValue,
          ),
      ],
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.loan,
    required this.paid,
    required this.balance,
    required this.due,
    required this.month,
    required this.photo,
  });

  /// Photo of the loan agreement, or null.
  final File? photo;

  final Loan loan;
  final int paid;
  final int balance;

  /// Still due in the selected month.
  final int due;

  /// Selected month, "yyyy-MM".
  final String month;

  /// "₱5,000 a month · 2 of 6 paid · Dec 2026 to May 2027"
  String _planLine() {
    if (loan.plan == LoanPlan.full) {
      return 'Pay in full by ${shortMonthLabel(loan.startMonth)}';
    }
    final n = loan.paymentCount;
    final last = monthKey(addMonths(parseMonthKey(loan.startMonth), n - 1));
    return '${formatPeso(loan.installment)} a month · '
        '${paymentsCovered(loan, paid)} of $n paid · '
        '${shortMonthLabel(loan.startMonth)} to ${shortMonthLabel(last)}';
  }

  /// "Due this month ₱5,000", or why nothing is due.
  String _dueLine() {
    if (due > 0) return 'Due this month ${formatPeso(due)}';
    if (monthsBetween(loan.startMonth, month) < 0) {
      return 'Starts ${shortMonthLabel(loan.startMonth)}';
    }
    return 'Nothing due this month';
  }

  void _pay(BuildContext context) {
    showPayLoan(context, loan);
  }

  Future<void> _onAction(BuildContext context, _LoanAction action) async {
    final state = AppScope.read(context);
    switch (action) {
      case _LoanAction.edit:
        await showEditLoanForm(context, loan);
      case _LoanAction.delete:
        final ok = await confirm(
          context,
          title: 'Delete ${loan.name}?',
          message: 'This loan and the money received for it will be '
              'removed.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (!ok) return;
        try {
          await state.deleteLoan(loan);
        } on ActionNotAllowed catch (e) {
          if (!context.mounted) return;
          showMessage(context, e.message);
        } catch (e) {
          if (!context.mounted) return;
          showMessage(context, 'Something went wrong: $e');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = loan.principal <= 0
        ? 1.0
        : (paid / loan.principal).clamp(0.0, 1.0).toDouble();
    final numbers =
        theme.textTheme.bodyMedium?.copyWith(fontFeatures: tabularFigures);
    final done = balance == 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (photo != null) ...<Widget>[
                  _Thumbnail(file: photo!, title: loan.name),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(loan.name, style: theme.textTheme.titleMedium),
                ),
                if (!done)
                  FilledButton.tonal(
                    onPressed: () => _pay(context),
                    child: const Text('Pay'),
                  ),
                PopupMenuButton<_LoanAction>(
                  tooltip: 'More',
                  onSelected: (a) => _onAction(context, a),
                  itemBuilder: (_) => const <PopupMenuEntry<_LoanAction>>[
                    PopupMenuItem<_LoanAction>(
                      value: _LoanAction.edit,
                      child: Text('Edit'),
                    ),
                    PopupMenuItem<_LoanAction>(
                      value: _LoanAction.delete,
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
            const SizedBox(height: 8),
            Text(_planLine(), style: numbers),
            Text(
              'Paid ${formatPeso(paid)} of ${formatPeso(loan.principal)}',
              style: numbers,
            ),
            if (!done)
              Text(
                _dueLine(),
                style: numbers?.copyWith(
                  color: due > 0 ? theme.colorScheme.primary : null,
                ),
              ),
            Text(
              done ? 'Paid off' : 'Balance ${formatPeso(balance)}',
              style: numbers?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.file, required this.title});

  final File file;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'View photo',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showPhotoViewer(context, file, title),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            file,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      ),
    );
  }
}
