import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../domain/models.dart';

/// Calm green seed for Material 3 color schemes.
const Color seedColor = Color(0xFF2E7D5B);

/// App version shown in settings. Keep in sync with pubspec.yaml.
const String appVersion = '1.9.0';

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
