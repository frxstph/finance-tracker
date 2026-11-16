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

  /// "1 of 6 paid" for a monthly plan.
  String _countText() {
    if (loan.plan == LoanPlan.full) return 'Pay in full';
    return '${paymentsCovered(loan, paid)} of ${loan.paymentCount} paid';
  }

  /// "Nov 2026 – Apr 2027", or "by Nov 2026" for pay in full.
  String _spanText() {
    if (loan.plan == LoanPlan.full) {
      return 'by ${shortMonthLabel(loan.startMonth)}';
    }
    final last = monthKey(
        addMonths(parseMonthKey(loan.startMonth), loan.paymentCount - 1));
    return '${shortMonthLabel(loan.startMonth)} – ${shortMonthLabel(last)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final progress = loan.principal <= 0
        ? 1.0
        : (paid / loan.principal).clamp(0.0, 1.0).toDouble();
    final small = theme.textTheme.bodyMedium
        ?.copyWith(fontFeatures: tabularFigures, color: muted);
    final done = balance == 0;
    final green = incomeColor(context);

    // Status pill: what this month asks of you.
    final String pillText;
    final Color pillColor;
    if (done) {
      pillText = 'Paid off';
      pillColor = green;
    } else if (due > 0) {
      pillText = 'Due this month · ${formatPeso(due)}';
      pillColor = billsColor(context);
    } else if (monthsBetween(loan.startMonth, month) < 0) {
      pillText = 'Starts ${shortMonthLabel(loan.startMonth)}';
      pillColor = muted;
    } else {
      pillText = 'Nothing due this month';
      pillColor = green;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Name and actions
            Row(
              children: <Widget>[
                if (photo != null) ...<Widget>[
                  _Thumbnail(file: photo!, title: loan.name),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    loan.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
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

            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // The one number to read first
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatPeso(balance),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFeatures: tabularFigures,
                              color: done ? green : debtColor(context),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('left of ${formatPeso(loan.principal)}',
                            style: small),
                      ),
                    ],
                  ),

                  // Progress and its numbers
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child:
                        LinearProgressIndicator(value: progress, minHeight: 8),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${formatPeso(paid)} paid · ${_countText()}',
                          style: small,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (loan.plan == LoanPlan.monthly)
                        Text('${formatPeso(loan.installment)} / month',
                            style: small),
                    ],
                  ),

                  // This month
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: pillColor.withAlpha(36),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          pillText,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: pillColor,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ),
                      Text(_spanText(), style: small),
                    ],
                  ),
                ],
              ),
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
