import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../due_days_page.dart';
import '../theme.dart';

/// "3 bills and 1 loan have no due day…" with a button to set them. Shows
/// nothing when everything has a due day.
class DueDayNudge extends StatelessWidget {
  const DueDayNudge({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final bills = state.billsWithoutDueDay.length;
    final loans = state.loansWithoutDueDay.length;
    if (bills + loans == 0) return const SizedBox.shrink();
    final parts = <String>[
      if (bills > 0) '$bills ${bills == 1 ? 'bill' : 'bills'}',
      if (loans > 0) '$loans ${loans == 1 ? 'loan' : 'loans'}',
    ];
    final what = parts.join(' and ');
    final theme = Theme.of(context);
    final orange = billsColor(context);
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: orange.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.event_busy_outlined, color: orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$what ${bills + loans == 1 ? 'has' : 'have'} no due day, so '
              'plans may look short. Set them for accurate results.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () => showDueDaysPage(context),
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }
}
