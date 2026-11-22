import 'package:flutter/material.dart';

/// One action at the bottom of an [InfoCard].
class InfoCardAction {
  const InfoCardAction(this.label, this.onPressed, {this.muted = false});

  final String label;
  final VoidCallback onPressed;

  /// Grey instead of green, for "Later" and similar.
  final bool muted;
}

/// The Dashboard's message cards (Safe to spend, the due-day banner) share
/// one layout so they line up:
///
///   [icon] Title
///   Headline (optional, big)
///   Body text
///   Action   Action
///
/// Body text and actions start at the same left edge as the icon, and the
/// actions always sit at the bottom left.
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.headline,
    this.headlineColor,
    this.actions = const <InfoCardAction>[],
    this.color,
    this.onTap,
    this.trailing,
    this.margin,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String? headline;
  final Color? headlineColor;
  final List<InfoCardAction> actions;

  /// Card background; null uses the normal card colour.
  final Color? color;

  /// Makes the whole card tappable.
  final VoidCallback? onTap;

  /// Small widget at the right end of the title row, such as a pill.
  final Widget? trailing;

  /// Space around the card; defaults to the Dashboard's.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionStyle = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      alignment: Alignment.centerLeft,
      textStyle: theme.textTheme.labelLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    );
    return Card(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 8),
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, actions.isEmpty ? 14 : 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 20, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: trailing,
                      ),
                    ),
                  ],
                ],
              ),
              if (headline != null) ...<Widget>[
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    headline!,
                    maxLines: 1,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: headlineColor,
                    ),
                  ),
                ),
              ],
              SizedBox(height: headline == null ? 6 : 2),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (actions.isNotEmpty)
                Wrap(
                  spacing: 20,
                  children: <Widget>[
                    for (final a in actions)
                      TextButton(
                        style: a.muted
                            ? actionStyle.copyWith(
                                foregroundColor: WidgetStatePropertyAll<Color>(
                                    theme.colorScheme.onSurfaceVariant),
                              )
                            : actionStyle,
                        onPressed: a.onPressed,
                        child: Text(a.label),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
