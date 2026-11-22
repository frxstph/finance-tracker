/// Turns the text read from a receipt photo into a best guess of the total,
/// the date and the store. Pure Dart so it can be unit tested; the phone's
/// text recognition (data/receipt_reader.dart) supplies the lines.
///
/// Nothing here is trusted blindly: the Check and save screen shows every
/// guess for the person to confirm or fix.
class ReceiptGuess {
  const ReceiptGuess({
    this.amount,
    this.date,
    this.store,
    this.lines = const <String>[],
    this.error,
  });

  /// Total in centavos, or null when no total could be found.
  final int? amount;

  /// Date printed on the receipt, or null.
  final DateTime? date;

  /// Store name from the top of the receipt, or null.
  final String? store;

  /// The text the phone read, row by row (shown under "See the text it
  /// read").
  final List<String> lines;

  /// Why reading failed, when it did.
  final String? error;

  bool get isEmpty => amount == null && date == null && store == null;

  /// True when the phone couldn't read any text at all.
  bool get noText => lines.isEmpty;
}

/// Labels that mark the amount actually paid, best first.
const List<String> _totalLabels = <String>[
  'grand total',
  'total amount due',
  'amount due',
  'total due',
  'total amount',
  'amount payable',
  'net amount',
  'total sales',
  'total',
  // E-wallet and bank screens: "Amount  - PHP 2,000.00".
  'amount paid',
  'amount sent',
  'amount',
];

/// Lines with these words hold other amounts (cash handed over, change,
/// tax lines, item counts), never the total.
const List<String> _notTotal = <String>[
  'subtotal',
  'sub total',
  'sub-total',
  'cash',
  'tender',
  'change',
  'vat',
  'vatable',
  'discount',
  'savings',
  'qty',
  'quantity',
  'items',
  'item(s)',
  'points',
  'balance',
  'card',
  'gcash',
  'maya',
];

/// Lines near the top that are not the store's name.
const List<String> _notStore = <String>[
  'paid via',
  'balance',
  'deposit accounts',
  'savings account',
  'transaction history',
  'recent transactions',
  'official receipt',
  'sales invoice',
  'invoice',
  'receipt',
  'vat reg',
  'non-vat',
  'tin',
  'welcome',
  'thank',
  'tel',
  'phone',
  'cashier',
  'date',
  'time',
  'branch',
  'store #',
  'pos',
  'or no',
  'si no',
  'min',
  'sn',
];

/// "1,248.50", "₱1,248.50", "P 1 248.50", "PHP1248.50", "1248,50".
final RegExp _money = RegExp(
  r'(?:₱|php|p)?\s*(\d{1,3}(?:[ ,]\d{3})+|\d+)[.,](\d{2})(?!\d)',
  caseSensitive: false,
);

/// Reads every amount with two decimals on [line], in centavos.
List<int> amountsIn(String line) {
  final out = <int>[];
  for (final m in _money.allMatches(line)) {
    final whole = m.group(1)!.replaceAll(RegExp(r'[ ,]'), '');
    final pesos = int.tryParse(whole);
    final cents = int.tryParse(m.group(2)!);
    if (pesos == null || cents == null) continue;
    if (whole.length > 9) continue; // a reference number, not money
    out.add(pesos * 100 + cents);
  }
  return out;
}

/// True when [lower] holds one of [words] as a whole word, so "min" (the
/// machine number) doesn't match "Mini Mart".
bool _hasAny(String lower, List<String> words) {
  for (final w in words) {
    var from = 0;
    while (true) {
      final i = lower.indexOf(w, from);
      if (i < 0) break;
      final before = i == 0 ? '' : lower[i - 1];
      final end = i + w.length;
      final after = end >= lower.length ? '' : lower[end];
      if (!_isLetter(before) && !_isLetter(after)) return true;
      from = i + 1;
    }
  }
  return false;
}

bool _isLetter(String ch) =>
    ch.isNotEmpty && ch.codeUnitAt(0) >= 97 && ch.codeUnitAt(0) <= 122;

/// The total: the amount on (or right after) the best "total" line; if no
/// line is labelled, the largest amount that isn't cash, change or tax.
int? findTotal(List<String> lines) {
  final lower = <String>[for (final l in lines) l.toLowerCase()];
  for (final label in _totalLabels) {
    for (var i = 0; i < lines.length; i++) {
      final l = lower[i];
      if (!l.contains(label)) continue;
      if ((label == 'total' || label == 'amount') && _hasAny(l, _notTotal)) {
        continue;
      }
      final here = amountsIn(lines[i]);
      if (here.isNotEmpty) return here.last;
      // Labels and amounts are often read as separate lines: look at the
      // next couple of lines for a lone amount.
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        if (_hasAny(lower[j], _notTotal)) break;
        final next = amountsIn(lines[j]);
        if (next.isNotEmpty) return next.first;
      }
    }
  }
  int? best;
  for (var i = 0; i < lines.length; i++) {
    if (_hasAny(lower[i], _notTotal)) continue;
    // "Available balance" on one row and "PHP 13,063.66" on the next: the
    // amount belongs to the excluded label above it.
    if (i > 0 &&
        _hasAny(lower[i - 1], _notTotal) &&
        amountsIn(lines[i - 1]).isEmpty) {
      continue;
    }
    // "11.21.26" is a date, not ₱11.21.
    if (_ymd.hasMatch(lines[i]) || _dmyOrMdy.hasMatch(lines[i])) continue;
    for (final a in amountsIn(lines[i])) {
      if (best == null || a > best) best = a;
    }
  }
  return best;
}

const Map<String, int> _months = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

final RegExp _ymd = RegExp(r'\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b');
final RegExp _dmyOrMdy = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})\b');
final RegExp _monthFirst = RegExp(
  r'\b([a-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(20\d{2}|\d{2})\b',
  caseSensitive: false,
);
/// "NOV 19" with no year (bank app history): this year, or last year if
/// that would be in the future.
final RegExp _monthDayOnly = RegExp(
  r'^\s*([a-z]{3})[a-z]*\.?\s+(\d{1,2})\s*$',
  caseSensitive: false,
);
final RegExp _dayFirst = RegExp(
  r'\b(\d{1,2})[\s-]+([a-z]{3})[a-z]*\.?[\s-]+(20\d{2}|\d{2})\b',
  caseSensitive: false,
);

DateTime? _valid(int y, int m, int d, DateTime today) {
  if (y < 100) y += 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime(y, m, d);
  if (date.month != m || date.day != d) return null; // e.g. 31 Feb
  final day = DateTime(today.year, today.month, today.day);
  if (date.isAfter(day)) return null; // receipts aren't from the future
  if (day.difference(date).inDays > 400) return null;
  return date;
}

/// The first believable date on the receipt: not in the future and not
/// more than about a year old. Slash dates are read month first (as on
/// Philippine receipts) unless that can't be a date.
DateTime? findDate(List<String> lines, DateTime today) {
  for (final line in lines) {
    for (final m in _ymd.allMatches(line)) {
      final d = _valid(int.parse(m.group(1)!), int.parse(m.group(2)!),
          int.parse(m.group(3)!), today);
      if (d != null) return d;
    }
    for (final m in _monthFirst.allMatches(line)) {
      final month = _months[m.group(1)!.toLowerCase()];
      if (month == null) continue;
      final d = _valid(
          int.parse(m.group(3)!), month, int.parse(m.group(2)!), today);
      if (d != null) return d;
    }
    for (final m in _dayFirst.allMatches(line)) {
      final month = _months[m.group(2)!.toLowerCase()];
      if (month == null) continue;
      final d = _valid(
          int.parse(m.group(3)!), month, int.parse(m.group(1)!), today);
      if (d != null) return d;
    }
    for (final m in _dmyOrMdy.allMatches(line)) {
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      final y = int.parse(m.group(3)!);
      final d = _valid(y, a, b, today) ?? _valid(y, b, a, today);
      if (d != null) return d;
    }
  }
  for (final line in lines) {
    final m = _monthDayOnly.firstMatch(line);
    if (m == null) continue;
    final month = _months[m.group(1)!.toLowerCase()];
    if (month == null) continue;
    final day = int.parse(m.group(2)!);
    final d = _valid(today.year, month, day, today) ??
        _valid(today.year - 1, month, day, today);
    if (d != null) return d;
  }
  return null;
}

String _titleCase(String s) {
  return s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.length <= 2 && w == w.toUpperCase()
          ? w
          : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

final RegExp _clock = RegExp(r'\b\d{1,2}:\d{2}\b');

/// The store: the first line near the top that reads like a name, before
/// any amount appears (below that it's items or account details).
String? findStore(List<String> lines) {
  for (final raw in lines.take(6)) {
    final line = raw.trim();
    if (amountsIn(line).isNotEmpty) break;
    if (_clock.hasMatch(line)) continue; // a phone's status bar
    if (line.length < 3 || line.length > 40) continue;
    final lower = line.toLowerCase();
    if (_hasAny(lower, _notStore)) continue;
    final letters = RegExp(r'[a-zA-Z]').allMatches(line).length;
    final digits = RegExp(r'\d').allMatches(line).length;
    if (letters < 3 || digits > letters ~/ 2) continue;
    return line == line.toUpperCase() ? _titleCase(line) : line;
  }
  return null;
}

/// Reads [lines] (top to bottom) into a [ReceiptGuess].
ReceiptGuess parseReceipt(List<String> lines, {DateTime? today}) {
  final clean = <String>[
    for (final l in lines)
      if (l.trim().isNotEmpty) l.trim(),
  ];
  return ReceiptGuess(
    amount: findTotal(clean),
    date: findDate(clean, today ?? DateTime.now()),
    store: findStore(clean),
    lines: clean,
  );
}
