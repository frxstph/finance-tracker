import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../due_days_page.dart';
import '../theme.dart';
import 'info_card.dart';

/// "4 loans need a due day" with Set due days / Later. Same layout as the
/// Safe to spend card. Shows nothing when everything has a due day or the
/// person tapped Later.
class DueDayNudge extends StatelessWidget {
  const DueDayNudge({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.showDueDayNudge) return const SizedBox.shrink();
    final bills = state.billsWithoutDueDay.length;
    final loans = state.loansWithoutDueDay.length;
    final parts = <String>[
      if (bills > 0) '$bills ${bills == 1 ? 'bill' : 'bills'}',
      if (loans > 0) '$loans ${loans == 1 ? 'loan' : 'loans'}',
    ];
    final one = bills + loans == 1;
    final orange = billsColor(context);
    return InfoCard(
      margin: margin,
      icon: Icons.event_busy_outlined,
      iconColor: orange,
      color: Color.alphaBlend(
        orange.withAlpha(28),
        Theme.of(context).colorScheme.surface,
      ),
      title: '${parts.join(' and ')} ${one ? 'needs' : 'need'} a due day',
      body: 'Plans may look short until you set ${one ? 'it' : 'them'}.',
      actions: <InfoCardAction>[
        InfoCardAction('Set due days', () => showDueDaysPage(context)),
        InfoCardAction('Later', state.hideDueDayNudge, muted: true),
      ],
    );
  }
}
