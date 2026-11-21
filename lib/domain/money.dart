import 'package:intl/intl.dart';

/// Largest amount accepted from user input: ₱999,999,999,999.99.
const int _maxIntegerDigits = 12;

final RegExp _amountPattern =
    RegExp(r'^(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?$');

/// Characters that make an amount a sum: + - * / and the × ÷ signs.
final RegExp _operatorPattern = RegExp(r'[+\-*/×÷]');

/// True when [input] is a sum like "450+120" rather than a plain amount.
bool isAmountExpression(String input) {
  final s = input.trim();
  return s.length > 1 && _operatorPattern.hasMatch(s.substring(1));
}

/// Parses user input such as "1250", "1,250", "1250.5", "1,250.50" or
/// "₱1,250.50" into integer centavos. Also works out simple sums typed into
/// an amount box: "450+120+35", "1,500*3", "2000/4", "100+50×2" (× and ÷
/// before + and −). A number after × or ÷ is a plain multiplier or divisor.
///
/// Returns null for empty input, negatives (including a sum that comes out
/// below zero), garbage, badly placed commas, more than two decimals,
/// division by zero or a result too large. Zero parses to 0; callers decide
/// whether 0 is OK.
int? parseCentavos(String input) {
  var s = input.trim();
  if (s.startsWith('₱')) {
    s = s.substring(1).trim();
  }
  if (s.isEmpty) return null;
  if (isAmountExpression(s)) {
    return _evaluate(s.replaceAll('₱', '').replaceAll(' ', ''));
  }
  return _parsePlain(s);
}

const int _maxCentavos = 99999999999999; // ₱999,999,999,999.99

int? _evaluate(String s) {
  // Split into numbers and operators: n (op n)*
  final numbers = <int>[];
  final ops = <String>[];
  final buffer = StringBuffer();
  for (final ch in s.split('')) {
    if (_operatorPattern.hasMatch(ch)) {
      if (buffer.isEmpty) return null; // leading or doubled operator
      final n = _parsePlain(buffer.toString());
      if (n == null) return null;
      numbers.add(n);
      ops.add(ch);
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  if (buffer.isEmpty) return null; // trailing operator
  final last = _parsePlain(buffer.toString());
  if (last == null) return null;
  numbers.add(last);

  // × and ÷ first, then + and −. Values are centavos.
  final terms = <int>[numbers.first];
  final signs = <int>[1];
  for (var i = 0; i < ops.length; i++) {
    final op = ops[i];
    final n = numbers[i + 1];
    if (op == '*' || op == '×') {
      final a = terms.last;
      if (n != 0 && a > _maxCentavos * 100 ~/ n) return null;
      terms[terms.length - 1] = (a * n + 50) ~/ 100;
    } else if (op == '/' || op == '÷') {
      if (n == 0) return null;
      final a = terms.last;
      terms[terms.length - 1] = (a * 200 + n) ~/ (2 * n);
    } else {
      terms.add(n);
      signs.add(op == '+' ? 1 : -1);
    }
    if (terms.last > _maxCentavos) return null;
  }
  var total = 0;
  for (var i = 0; i < terms.length; i++) {
    total += signs[i] * terms[i];
  }
  if (total < 0 || total > _maxCentavos) return null;
  return total;
}

int? _parsePlain(String s) {
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
