import 'models.dart';

/// Builds a CSV of [entries] for Excel or Google Sheets: oldest first, one
/// row each. Amount is a plain number (no ₱ or commas) so sheets can add it
/// up; money out is negative. [linkedName] names the bill, loan or monthly
/// income an entry belongs to ('' when none).
String entriesToCsv(
  List<Entry> entries,
  String Function(Entry entry) linkedName,
) {
  final sorted = List<Entry>.of(entries)
    ..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
    });
  final out = StringBuffer()
    ..write('Date,Type,Amount,In or out,For,Note,Has photo\r\n');
  for (final e in sorted) {
    final signed = e.type.isMoneyIn ? e.amount : -e.amount;
    out
      ..write(csvField(e.date))
      ..write(',')
      ..write(csvField(e.type.label))
      ..write(',')
      ..write(plainAmount(signed))
      ..write(',')
      ..write(e.type.isMoneyIn ? 'In' : 'Out')
      ..write(',')
      ..write(csvField(linkedName(e)))
      ..write(',')
      ..write(csvField(e.note))
      ..write(',')
      ..write(e.photo == null ? 'No' : 'Yes')
      ..write('\r\n');
  }
  return out.toString();
}

/// Centavos as "1250.50" / "-300.00".
String plainAmount(int centavos) {
  final sign = centavos < 0 ? '-' : '';
  final abs = centavos.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

/// Quotes a field when it holds a comma, quote or line break. A leading
/// = + - or @ gets a ' in front so a sheet never runs it as a formula.
String csvField(String value) {
  var v = value;
  if (v.isNotEmpty && '=+-@'.contains(v[0])) v = "'$v";
  if (v.contains(RegExp(r'[",\r\n]'))) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}
