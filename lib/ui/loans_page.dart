import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import '../state/app_state.dart';
import 'quick_add_page.dart';
import 'theme.dart';
import 'widgets/dialogs.dart';
import 'widgets/empty_state.dart';
import 'widgets/name_amount_dialog.dart';

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
        onAction: () => showNewLoanDialog(context),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: <Widget>[
        for (final l in loans)
          _LoanCard(
            loan: l,
            paid: state.loanPaid(l),
            balance: state.loanBalanceOf(l),
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
  });

  final Loan loan;
  final int paid;
  final int balance;

  void _pay(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => QuickAddPage(
          initialType: EntryType.loanPayment,
          initialLoanId: loan.id,
        ),
      ),
    );
  }

  Future<void> _onAction(BuildContext context, _LoanAction action) async {
    final state = AppScope.read(context);
    switch (action) {
      case _LoanAction.edit:
        await showEditLoanDialog(context, loan);
      case _LoanAction.delete:
        final ok = await confirm(
          context,
          title: 'Delete ${loan.name}?',
          message: 'This loan will be removed.',
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
            Text(
              'Paid ${formatPeso(paid)} of ${formatPeso(loan.principal)}',
              style: numbers,
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
