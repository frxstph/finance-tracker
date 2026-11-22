import 'dart:math' as math;

import 'dates.dart';
import 'models.dart';
import 'summary.dart';
import 'weeks.dart';

// ---------------------------------------------------------------------------
// Plain calculator
// ---------------------------------------------------------------------------

const String _ops = '+-*/×÷−';

bool _isOp(String ch) => _ops.contains(ch);

/// Works out a calculator line such as "1,250+300×2", "-5+2", "50%" or
/// "200×15%". × and ÷ come before + and −. "%" divides the number before it
/// by 100. Commas and spaces are ignored. Returns null for an unfinished or
/// impossible line (a trailing operator, two operators in a row other than a
/// minus sign, division by zero).
double? evaluateExpression(String input) {
  final s = input.replaceAll(',', '').replaceAll(' ', '').replaceAll('−', '-');
  if (s.isEmpty) return null;

  final numbers = <double>[];
  final ops = <String>[];
  var i = 0;
  var expectNumber = true;
  while (i < s.length) {
    final ch = s[i];
    if (expectNumber) {
      var sign = 1.0;
      if (ch == '-' || ch == '+') {
        sign = ch == '-' ? -1 : 1;
        i++;
        if (i >= s.length) return null;
      }
      final start = i;
      while (i < s.length && (_isDigit(s[i]) || s[i] == '.')) {
        i++;
      }
      if (start == i) return null;
      final value = double.tryParse(s.substring(start, i));
      if (value == null) return null;
      var n = sign * value;
      while (i < s.length && s[i] == '%') {
        n = n / 100;
        i++;
      }
      numbers.add(n);
      expectNumber = false;
    } else {
      if (!_isOp(ch)) return null;
      ops.add(ch);
      i++;
      expectNumber = true;
    }
  }
  if (expectNumber) return null;

  final terms = <double>[numbers.first];
  for (var k = 0; k < ops.length; k++) {
    final op = ops[k];
    final n = numbers[k + 1];
    if (op == '*' || op == '×') {
      terms[terms.length - 1] = terms.last * n;
    } else if (op == '/' || op == '÷') {
      if (n == 0) return null;
      terms[terms.length - 1] = terms.last / n;
    } else {
      terms.add(op == '+' ? n : -n);
    }
  }
  final total = terms.fold<double>(0, (a, b) => a + b);
  if (total.isNaN || total.isInfinite) return null;
  return total;
}

bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;

/// A calculator result as centavos for "Use this amount", or null when it
/// is not a positive amount.
int? resultToCentavos(double? value) {
  if (value == null || value <= 0 || value > 999999999999) return null;
  final c = (value * 100).round();
  return c > 0 ? c : null;
}

// ---------------------------------------------------------------------------
// Loan quote
// ---------------------------------------------------------------------------

/// How a lender states interest.
enum InterestKind {
  /// "3% a month": each month adds that share of the amount borrowed, for
  /// every month of the loan (common for Philippine personal loans).
  monthlyAddOn,

  /// "18% a year" on the balance that is left (a standard amortized loan).
  yearly,
}

class LoanQuote {
  const LoanQuote({
    required this.monthly,
    required this.total,
    required this.interest,
  });

  /// Payment each month, in centavos.
  final int monthly;

  /// Everything paid back, in centavos.
  final int total;

  /// [total] minus the amount borrowed.
  final int interest;
}

/// Monthly payment, total and interest for borrowing [principal] centavos at
/// [ratePercent] over [months]. Null when the inputs make no sense.
LoanQuote? quoteLoan({
  required int principal,
  required double ratePercent,
  required int months,
  required InterestKind kind,
}) {
  if (principal <= 0 || months <= 0 || ratePercent < 0 || months > 600) {
    return null;
  }
  switch (kind) {
    case InterestKind.monthlyAddOn:
      final interest = (principal * ratePercent / 100 * months).round();
      final total = principal + interest;
      final monthly = (total + months - 1) ~/ months;
      return LoanQuote(monthly: monthly, total: total, interest: interest);
    case InterestKind.yearly:
      final r = ratePercent / 100 / 12;
      final double payment = r == 0
          ? principal / months
          : principal * r / (1 - math.pow(1 + r, -months));
      final monthly = payment.ceil();
      final total = monthly * months;
      return LoanQuote(
          monthly: monthly, total: total, interest: total - principal);
  }
}

// ---------------------------------------------------------------------------
// Split
// ---------------------------------------------------------------------------

class SplitResult {
  const SplitResult({required this.each, required this.extra});

  /// What everyone pays, in centavos.
  final int each;

  /// Centavos left over after an even split, paid by one person.
  final int extra;
}

SplitResult? splitAmount(int total, int people) {
  if (total <= 0 || people <= 0) return null;
  final each = total ~/ people;
  return SplitResult(each: each, extra: total - each * people);
}

// ---------------------------------------------------------------------------
// Can I afford this?
// ---------------------------------------------------------------------------

class AffordResult {
  const AffordResult({
    required this.lowest,
    required this.lowestMonth,
    required this.lowestFirstDay,
    required this.lowestLastDay,
    required this.monthEnd,
  });

  /// Lowest block-end cash from the purchase to the end of the next month,
  /// with the purchase taken out.
  final int lowest;

  /// Where that low point is: month "yyyy-MM" and its day range.
  final String lowestMonth;
  final int lowestFirstDay;
  final int lowestLastDay;

  /// Cash at the end of the purchase month, after the purchase.
  final int monthEnd;

  bool get affordable => lowest >= 0;
}

/// Whether spending [amount] centavos on [date] keeps every week block from
/// then until the end of the next month at or above ₱0, assuming everything
/// else in "If all paid" happens. Dates before [today] count as today.
AffordResult canAfford({
  required int amount,
  required DateTime date,
  required DateTime today,
  required List<Entry> entries,
  required List<Bill> bills,
  required List<Loan> loans,
  List<IncomeSource> incomes = const <IncomeSource>[],
}) {
  final on = date.isBefore(DateTime(today.year, today.month, today.day))
      ? today
      : date;
  final current = monthKey(today);
  final month = monthKey(on);
  final next = monthKey(addMonths(parseMonthKey(month), 1));
  final months = forecastMonths(
    fromMonth: current,
    toMonth: next,
    entries: entries,
    bills: bills,
    loans: loans,
    incomes: incomes,
  );

  int? lowest;
  var lowMonth = month;
  var lowFirst = 1;
  var lowLast = 7;
  var monthEnd = 0;
  for (final f in months) {
    if (f.month.compareTo(month) < 0) continue;
    final blocks = weekBlocks(
      forecast: f,
      entries: entries,
      bills: bills,
      loans: loans,
      incomes: incomes,
      today: today,
    );
    for (final b in blocks) {
      if (f.month == month && b.lastDay < on.day) continue;
      var cash = b.endCash - amount;
      if (f.month == month && b.firstDay <= on.day) {
        // The week of the purchase: check the day itself (income later in
        // the week has not arrived yet) and every day after it.
        var run = b.startCash + b.recorded;
        for (final item in b.items) {
          if (item.day <= on.day) run += item.amount;
        }
        var low = run;
        for (final item in b.items) {
          if (item.day > on.day) {
            run += item.amount;
            if (run < low) low = run;
          }
        }
        cash = low - amount;
      }
      if (lowest == null || cash < lowest) {
        lowest = cash;
        lowMonth = f.month;
        lowFirst = b.firstDay;
        lowLast = b.lastDay;
      }
    }
    if (f.month == month) monthEnd = f.endCash - amount;
  }
  return AffordResult(
    lowest: lowest ?? -amount,
    lowestMonth: lowMonth,
    lowestFirstDay: lowFirst,
    lowestLastDay: lowLast,
    monthEnd: monthEnd,
  );
}

/// The first day from [from] (exclusive) up to [maxDays] days later on which
/// spending [amount] is affordable, or null when none is.
DateTime? earliestAffordable({
  required int amount,
  required DateTime from,
  required DateTime today,
  required List<Entry> entries,
  required List<Bill> bills,
  required List<Loan> loans,
  List<IncomeSource> incomes = const <IncomeSource>[],
  int maxDays = 62,
}) {
  final start = DateTime(from.year, from.month, from.day);
  for (var i = 1; i <= maxDays; i++) {
    final d = DateTime(start.year, start.month, start.day + i);
    final r = canAfford(
      amount: amount,
      date: d,
      today: today,
      entries: entries,
      bills: bills,
      loans: loans,
      incomes: incomes,
    );
    if (r.affordable) return d;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Safe to spend
// ---------------------------------------------------------------------------

class SafeToSpend {
  const SafeToSpend({
    required this.cashNow,
    required this.dueBeforePayday,
    required this.days,
    required this.payday,
    required this.paydayName,
    required this.lowestAhead,
    required this.lowestMonth,
    required this.lowestFirstDay,
    required this.lowestLastDay,
  });

  /// Cash recorded up to today.
  final int cashNow;

  /// Bills and loan payments due from today until the day before payday
  /// (overdue ones included), plus anything already recorded for those days.
  final int dueBeforePayday;

  /// Days from today up to the day before payday, today included (at least
  /// 1).
  final int days;

  /// Next payday, or the last day of the month when no monthly income is
  /// set up.
  final DateTime payday;

  /// The income expected on [payday], or null when there is none.
  final String? paydayName;

  /// The lowest week-block end cash from today through the end of the month
  /// after payday's month, in "If all paid", and where it is. Anything spent
  /// before payday comes out of every one of those blocks.
  final int lowestAhead;
  final String lowestMonth;
  final int lowestFirstDay;
  final int lowestLastDay;

  /// Cash free after what is due before payday. Negative means short.
  int get free => cashNow - dueBeforePayday;

  /// What can be spent before payday without any week going below ₱0, now
  /// or after payday: the smaller of [free] and [lowestAhead].
  int get budget => free < lowestAhead ? free : lowestAhead;

  /// Kept back from [free] for bills that come after payday.
  int get keptForLater => free > budget ? free - budget : 0;

  /// Short now (before payday) or later (a week after payday).
  bool get short => budget < 0;

  /// What can be spent each day until payday, never below 0.
  int get perDay => budget <= 0 ? 0 : budget ~/ days;
}

/// How much can be spent each day until the next monthly income arrives,
/// after setting aside every bill and loan payment due before it, and
/// keeping back enough that no week until the end of the month after
/// payday's month goes below ₱0 ("If all paid").
SafeToSpend safeToSpend({
  required DateTime today,
  required List<Entry> entries,
  required List<Bill> bills,
  required List<Loan> loans,
  List<IncomeSource> incomes = const <IncomeSource>[],
}) {
  final day0 = DateTime(today.year, today.month, today.day);
  final todayKey = dateKey(day0);
  final current = monthKey(day0);
  final next = monthKey(addMonths(parseMonthKey(current), 1));

  // Cash up to today.
  var cash = 0;
  for (final e in entries) {
    if (e.date.compareTo(todayKey) <= 0) cash += signedAmount(e);
  }

  // Next payday: the earliest monthly income still to come, this month
  // (not yet received, on or after today) or next month.
  final receivedThisMonth = <int>{
    for (final e in entries)
      if (e.type == EntryType.income &&
          e.incomeId != null &&
          isInMonth(e.date, current))
        e.incomeId!,
  };
  DateTime? payday;
  String? paydayName;
  for (final s in incomes) {
    if (!s.active) continue;
    final thisMonth = dayInMonth(day0, s.day);
    final DateTime when;
    if (!thisMonth.isBefore(day0) &&
        !(s.id != null && receivedThisMonth.contains(s.id))) {
      when = thisMonth;
    } else {
      when = dayInMonth(parseMonthKey(next), s.day);
    }
    if (payday == null || when.isBefore(payday)) {
      payday = when;
      paydayName = s.name;
    }
  }
  payday ??= DateTime(day0.year, day0.month + 1, 0);

  final days = math.max(1, payday.difference(day0).inDays);
  final lastCovered = payday.subtract(const Duration(days: 1));

  // What goes out before payday: planned bill and loan payments (overdue
  // ones count today) and anything recorded after today in that window.
  final horizon = monthKey(addMonths(DateTime(payday.year, payday.month), 1));
  final months = forecastMonths(
    fromMonth: current,
    toMonth: horizon,
    entries: entries,
    bills: bills,
    loans: loans,
    incomes: incomes,
  );
  var due = 0;
  int? lowest;
  var lowMonth = current;
  var lowFirst = 1;
  var lowLast = 7;
  for (final f in months) {
    final blocks = weekBlocks(
      forecast: f,
      entries: entries,
      bills: bills,
      loans: loans,
      incomes: incomes,
      today: day0,
    );
    final first = parseMonthKey(f.month);
    for (final b in blocks) {
      if (!b.past && (lowest == null || b.endCash < lowest)) {
        lowest = b.endCash;
        lowMonth = f.month;
        lowFirst = b.firstDay;
        lowLast = b.lastDay;
      }
      for (final item in b.items) {
        if (item.amount >= 0) continue;
        final d = DateTime(first.year, first.month, item.day);
        if (d.isAfter(lastCovered)) continue;
        due += -item.amount;
      }
    }
  }
  final lastKey = dateKey(lastCovered);
  for (final e in entries) {
    if (e.date.compareTo(todayKey) > 0 && e.date.compareTo(lastKey) <= 0) {
      due -= signedAmount(e);
    }
  }
  if (due < 0) due = 0;

  return SafeToSpend(
    cashNow: cash,
    dueBeforePayday: due,
    days: days,
    payday: payday,
    paydayName: paydayName,
    lowestAhead: lowest ?? cash,
    lowestMonth: lowMonth,
    lowestFirstDay: lowFirst,
    lowestLastDay: lowLast,
  );
}
