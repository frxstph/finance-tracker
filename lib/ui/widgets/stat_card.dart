import 'package:flutter/material.dart';

import '../theme.dart';

/// One dashboard number with a label and an optional detail line.
///
/// Every card has the same height: one label line, a fixed-height value that
/// shrinks long amounts to fit, and one detail line.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.valueColor,
    this.icon,
  });

  final String label;
  final String value;
  final String? detail;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.headlineSmall?.copyWith(
      color: valueColor,
      fontWeight: FontWeight.w600,
      fontFeatures: tabularFigures,
    );
    final valueHeight = (valueStyle?.fontSize ?? 24) * 1.4;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: valueHeight,
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: valueStyle, maxLines: 1),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail ?? '',
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
