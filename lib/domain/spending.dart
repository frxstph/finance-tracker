import 'models.dart';

/// Totals for the Spending chart on the Dashboard. Everyday spending is
/// Daily + One-time entries; bills and loans are Bill + Loan payment
/// entries. Income, loans received and adjustments are not spending.

bool isEveryday(EntryType t) => t == EntryType.daily || t == EntryType.oneTime;

bool isBillOrLoan(EntryType t) =>
    t == EntryType.bill || t == EntryType.loanPayment;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? _entryDay(Entry e) {
  final d = DateTime.tryParse(e.date);
  return d == null ? null : _day(d);
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Everyday and bills/loans totals for entries dated [from]..[to] (both
/// days included).
({int everyday, int billsLoans}) totalsBetween(
  List<Entry> entries,
  DateTime from,
  DateTime to,
) {
  final a = _day(from);
  final b = _day(to);
  var everyday = 0;
  var billsLoans = 0;
  for (final e in entries) {
    final d = _entryDay(e);
    if (d == null || d.isBefore(a) || d.isAfter(b)) continue;
    if (isEveryday(e.type)) everyday += e.amount;
    if (isBillOrLoan(e.type)) billsLoans += e.amount;
  }
  return (everyday: everyday, billsLoans: billsLoans);
}

class DayBar {
  const DayBar(this.day, this.amount);
  final DateTime day;

  /// Everyday spending that day, in centavos.
  final int amount;
}

/// One bar per day for the 30 days ending [today], oldest first.
List<DayBar> last30Days(List<Entry> entries, DateTime today) {
  final end = _day(today);
  final start = end.subtract(const Duration(days: 29));
  final byDay = <DateTime, int>{};
  for (final e in entries) {
    if (!isEveryday(e.type)) continue;
    final d = _entryDay(e);
    if (d == null || d.isBefore(start) || d.isAfter(end)) continue;
    byDay[d] = (byDay[d] ?? 0) + e.amount;
  }
  return <DayBar>[
    for (var i = 0; i < 30; i++)
      () {
        final d = DateTime(start.year, start.month, start.day + i);
        return DayBar(d, byDay[d] ?? 0);
      }(),
  ];
}

/// One quarter-month block: this month beside last month.
class WeekBar {
  const WeekBar({
    required this.label,
    required this.thisMonth,
    required this.lastMonth,
    required this.inProgress,
    required this.future,
  });

  /// "1–7", "8–14", "15–21", "22–30".
  final String label;
  final int thisMonth;
  final int lastMonth;

  /// Today falls in this block.
  final bool inProgress;

  /// Hasn't started yet this month.
  final bool future;
}

const List<int> _blockStarts = <int>[1, 8, 15, 22];

/// The four quarter-month blocks of [today]'s month (everyday spending),
/// each beside the same block of the month before.
List<WeekBar> weekBars(List<Entry> entries, DateTime today) {
  final y = today.year;
  final m = today.month;
  final lastY = m == 1 ? y - 1 : y;
  final lastM = m == 1 ? 12 : m - 1;
  final endThis = _daysInMonth(y, m);
  final endLast = _daysInMonth(lastY, lastM);
  final out = <WeekBar>[];
  for (var i = 0; i < 4; i++) {
    final s = _blockStarts[i];
    final eThis = i == 3 ? endThis : _blockStarts[i + 1] - 1;
    final eLast = i == 3 ? endLast : _blockStarts[i + 1] - 1;
    out.add(WeekBar(
      label: '$s–$eThis',
      thisMonth: totalsBetween(
              entries, DateTime(y, m, s), DateTime(y, m, eThis))
          .everyday,
      lastMonth: totalsBetween(
              entries, DateTime(lastY, lastM, s), DateTime(lastY, lastM, eLast))
          .everyday,
      inProgress: today.day >= s && today.day <= eThis,
      future: today.day < s,
    ));
  }
  return out;
}

/// Everyday spending this month up to [today], and last month up to the
/// same day (or its last day, when it's shorter).
({int thisMonth, int lastMonth}) monthToDate(
    List<Entry> entries, DateTime today) {
  final y = today.year;
  final m = today.month;
  final lastY = m == 1 ? y - 1 : y;
  final lastM = m == 1 ? 12 : m - 1;
  final lastDay = today.day.clamp(1, _daysInMonth(lastY, lastM));
  return (
    thisMonth: totalsBetween(entries, DateTime(y, m, 1), today).everyday,
    lastMonth: totalsBetween(
            entries, DateTime(lastY, lastM, 1), DateTime(lastY, lastM, lastDay))
        .everyday,
  );
}

/// A month or a quarter: everyday spending with bills and loans on top.
class PeriodBar {
  const PeriodBar({
    required this.label,
    required this.start,
    required this.everyday,
    required this.billsLoans,
    required this.inProgress,
    required this.future,
  });

  final String label;
  final DateTime start;
  final int everyday;
  final int billsLoans;
  final bool inProgress;
  final bool future;

  int get total => everyday + billsLoans;
}

const List<String> _monthLetters = <String>[
  'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D',
];

/// The 12 months ending with [today]'s month, oldest first.
List<PeriodBar> monthBars(List<Entry> entries, DateTime today) {
  final out = <PeriodBar>[];
  for (var i = 11; i >= 0; i--) {
    final start = DateTime(today.year, today.month - i, 1);
    final end = DateTime(start.year, start.month + 1, 0);
    final t = totalsBetween(entries, start, end);
    out.add(PeriodBar(
      label: _monthLetters[start.month - 1],
      start: start,
      everyday: t.everyday,
      billsLoans: t.billsLoans,
      inProgress: i == 0,
      future: false,
    ));
  }
  return out;
}

/// Q1–Q4 of [today]'s year.
List<PeriodBar> quarterBars(List<Entry> entries, DateTime today) {
  final current = (today.month - 1) ~/ 3;
  return <PeriodBar>[
    for (var q = 0; q < 4; q++)
      () {
        final start = DateTime(today.year, q * 3 + 1, 1);
        final end = DateTime(today.year, q * 3 + 4, 0);
        final t = totalsBetween(entries, start, end);
        return PeriodBar(
          label: 'Q${q + 1}',
          start: start,
          everyday: t.everyday,
          billsLoans: t.billsLoans,
          inProgress: q == current,
          future: q > current,
        );
      }(),
  ];
}

/// "₱82.2k", "₱950", "₱1.3M" for labels over bars.
String compactPeso(int centavos) {
  final pesos = centavos / 100;
  if (pesos >= 1000000) return '₱${(pesos / 1000000).toStringAsFixed(1)}M';
  if (pesos >= 10000) return '₱${(pesos / 1000).toStringAsFixed(1)}k';
  if (pesos >= 1000) return '₱${(pesos / 1000).toStringAsFixed(1)}k';
  return '₱${pesos.round()}';
}
