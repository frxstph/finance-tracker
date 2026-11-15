import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../state/app_state.dart';
import '../theme.dart';

/// One entry row: type icon, title, amount, camera icon when it has a photo.
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, required this.onTap});

  final Entry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final isIncome = entry.type.isMoneyIn;
    final amountText =
        isIncome ? '+${formatPeso(entry.amount)}' : formatPeso(entry.amount);
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
        child: Icon(iconForType(entry.type), size: 20),
      ),
      title: Text(
        state.titleFor(entry),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(entry.type.label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (entry.hasPhoto) ...<Widget>[
            Icon(Icons.photo_camera_outlined,
                size: 16, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
          ],
          Text(
            amountText,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isIncome ? incomeColor(context) : null,
              fontWeight: isIncome ? FontWeight.w600 : null,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}
