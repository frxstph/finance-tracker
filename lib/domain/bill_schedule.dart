import 'dates.dart';
import 'models.dart';

/// Whole days since 1970-01-01 for a calendar date (no time zone effects).
int _dayNumber(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// How many times [bill] is due in [month] ("yyyy-MM"), from its schedule.
///
/// - Monthly: once a month from the start month (every month when there is
///   no start date), stopping after [Bill.times] months.
/// - Weekly / daily: every 7 days / every day from the start date, stopping
///   after [Bill.times] payments.
/// - One time: once, in the month of its due date.
int billDueCount(Bill bill, String month) {
  final rawStart = bill.startDate;
  final start =
      rawStart != null && isValidDateKey(rawStart) ? parseDateKey(rawStart) : null;
  final times = bill.times;

  switch (bill.frequency) {
    case BillFrequency.monthly:
      if (start == null) return 1;
      final k = monthsBetween(monthKey(start), month);
      if (k < 0) return 0;
      if (times != null && k >= times) return 0;
      return 1;
    case BillFrequency.once:
      if (start == null) return 0;
      return monthKey(start) == month ? 1 : 0;
    case BillFrequency.weekly:
    case BillFrequency.daily:
      if (start == null) return 0;
      final step = bill.frequency == BillFrequency.weekly ? 7 : 1;
      final first = parseMonthKey(month);
      final last = DateTime(first.year, first.month + 1, 0);
      final s = _dayNumber(start);
      final a = _dayNumber(first);
      final z = _dayNumber(last);
      if (z < s) return 0;
      final firstIndex = a <= s ? 0 : (a - s + step - 1) ~/ step;
      var lastIndex = (z - s) ~/ step;
      if (times != null && lastIndex > times - 1) lastIndex = times - 1;
      final n = lastIndex - firstIndex + 1;
      return n < 0 ? 0 : n;
  }
}

/// Why a bill has nothing due in [month]: it starts later, or it is done.
/// Null when something is due.
String? billNotDueReason(Bill bill, String month) {
  if (billDueCount(bill, month) > 0) return null;
  final rawStart = bill.startDate;
  if (rawStart != null &&
      isValidDateKey(rawStart) &&
      rawStart.substring(0, 7).compareTo(month) > 0) {
    return bill.frequency == BillFrequency.once
        ? 'Due ${shortMonthLabel(rawStart.substring(0, 7))}'
        : 'Starts ${shortMonthLabel(rawStart.substring(0, 7))}';
  }
  return bill.frequency == BillFrequency.once ? 'Not this month' : 'Finished';
}

/// "₱500 a week", plus how long it runs: "· 4 times", "· until Mar 2027".
String billScheduleLabel(Bill bill, String Function(int) money) {
  final base = '${money(bill.amount)} ${bill.frequency.per}';
  final times = bill.times;
  if (bill.frequency == BillFrequency.once || times == null) return base;
  return '$base · ${times == 1 ? 'once' : '$times times'}';
}
