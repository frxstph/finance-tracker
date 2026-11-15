import 'package:intl/intl.dart';

/// Largest amount accepted from user input: ₱999,999,999,999.99.
const int _maxIntegerDigits = 12;

final RegExp _amountPattern =
    RegExp(r'^(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?$');

/// Parses user input such as "1250", "1,250", "1250.5", "1,250.50" or
/// "₱1,250.50" into integer centavos.
///
/// Returns null for empty input, negatives, garbage, badly placed commas or
/// more than two decimals. Zero parses to 0; callers decide whether 0 is OK.
int? parseCentavos(String input) {
  var s = input.trim();
  if (s.startsWith('₱')) {
    s = s.substring(1).trim();
  }
  if (s.isEmpty) return null;
  final match = _amountPattern.firstMatch(s);
  if (match == null) return null;
  final whole = match.group(1)!.replaceAll(',', '');
  if (whole.length > _maxIntegerDigits) return null;
  final frac = match.group(2) ?? '';
  final pesos = int.parse(whole);
  final cents = frac.isEmpty ? 0 : int.parse(frac.padRight(2, '0'));
  return pesos * 100 + cents;
}

final NumberFormat _groupedWhole = NumberFormat('#,##0', 'en_US');

/// Formats centavos as "₱1,250.50", dropping ".00" for whole amounts
/// ("₱1,250"). Negative amounts become "-₱1,250".
String formatPeso(int centavos) {
  final negative = centavos < 0;
  final abs = centavos.abs();
  final pesos = abs ~/ 100;
  final cents = abs % 100;
  final buffer = StringBuffer();
  if (negative) buffer.write('-');
  buffer.write('₱');
  buffer.write(_groupedWhole.format(pesos));
  if (cents != 0) {
    buffer.write('.');
    buffer.write(cents.toString().padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Plain editable text for an amount field: 125050 -> "1250.50",
/// 125000 -> "1250". Never negative.
String centavosToInput(int centavos) {
  final abs = centavos.abs();
  final pesos = abs ~/ 100;
  final cents = abs % 100;
  if (cents == 0) return pesos.toString();
  return '$pesos.${cents.toString().padLeft(2, '0')}';
}
