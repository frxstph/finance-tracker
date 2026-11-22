import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/money.dart';

/// Calm green seed for Material 3 color schemes.
const Color seedColor = Color(0xFF2E7D5B);

/// App version shown in settings. Keep in sync with pubspec.yaml.
const String appVersion = '1.14.0';

ThemeData buildTheme(Brightness brightness) {
  final scheme =
      ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
  );
}

/// Tabular figures so amounts line up in lists.
const List<FontFeature> tabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// Green used for income amounts.
Color incomeColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF7FD6A0)
      : const Color(0xFF1B7A43);
}

/// Lists use one rule: money in is green with "+", money out is red with
/// "−", nothing is muted grey. Balances use [balanceColor].
Color flowColor(BuildContext context, int signedAmount) {
  if (signedAmount > 0) return incomeColor(context);
  if (signedAmount < 0) return debtColor(context);
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

/// A balance (cash at a point in time): dark text, red only when below 0.
Color balanceColor(BuildContext context, int amount) => amount < 0
    ? debtColor(context)
    : Theme.of(context).colorScheme.onSurface;

/// "+₱1,250", "−₱300" (true minus sign), "₱0".
String signedPeso(int amount) {
  if (amount > 0) return '+${formatPeso(amount)}';
  if (amount < 0) return '−${formatPeso(-amount)}';
  return formatPeso(0);
}

/// Orange for bills still to pay.
Color billsColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFFB066)
      : const Color(0xFFB85C00);
}

/// Red for debt and negative amounts.
Color debtColor(BuildContext context) => Theme.of(context).colorScheme.error;

IconData iconForType(EntryType type) {
  switch (type) {
    case EntryType.income:
      return Icons.arrow_downward;
    case EntryType.bill:
      return Icons.receipt_long;
    case EntryType.oneTime:
      return Icons.shopping_bag_outlined;
    case EntryType.daily:
      return Icons.local_cafe_outlined;
    case EntryType.loanPayment:
      return Icons.account_balance_outlined;
    case EntryType.loanReceived:
      return Icons.call_received;
    case EntryType.adjustIn:
    case EntryType.adjustOut:
      return Icons.tune;
  }
}
