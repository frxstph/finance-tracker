import 'package:flutter/material.dart';

import '../../domain/dates.dart';
import '../../state/app_state.dart';

/// "‹ November 2026 ›" — changes the selected month for the whole app.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final isThisMonth =
        monthKey(state.month) == monthKey(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: state.showPreviousMonth,
          ),
          Expanded(
            child: GestureDetector(
              onTap: isThisMonth ? null : state.showThisMonth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    monthLabel(state.month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (!isThisMonth)
                    Text(
                      'Tap to go to this month',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: state.showNextMonth,
          ),
        ],
      ),
    );
  }
}
