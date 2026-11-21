import 'bill_schedule.dart';
import 'dates.dart';
import 'models.dart';
import 'summary.dart';

/// What a planned item in a week block is.
enum WeekItemKind { income, bill, loan }

/// One expected payment or income placed on a day of the month.
class WeekItem {
  const WeekItem({
    required this.day,
    required this.label,
    required this.amount,
    required this.kind,
    this.dayKnown = true,
  });

  /// Day of the month it is counted on. Items that are overdue, or have no
  /// due day, are counted on today (or the 1st for a future month).
  final int day;

  final String label;

  /// + for money in, − for money out, in centavos.
  final int amount;

  final WeekItemKind kind;

  /// False when the item has no due day of its own.
  final bool dayKnown;
}

/// One fixed block of a month: days 1–7, 8–14, 15–21 or 22 to the end.
class WeekBlock {
  const WeekBlock({
    required this.firstDay,
    required this.lastDay,
    required this.startCash,
    required this.recorded,
    required this.items,
    required this.past,
  });

  final int firstDay;
  final int lastDay;

  /// Cash at the start of the block.
  final int startCash;

  /// Money in minus money out already recorded in these days.
  final int recorded;

  /// Expected income and payments, by day.
  final List<WeekItem> items;

  /// True when the whole block is before today.
  final bool past;

  int get planned => items.fold<int>(0, (sum, i) => sum + i.amount);

  /// Cash at the end of the block if everything planned happens.
  int get endCash => startCash + recorded + planned;
}

/// The fixed day ranges of a month with [lastDay] days.
List<List<int>> blockRanges(int lastDay) => <List<int>>[
      <int>[1, 7],
      <int>[8, 14],
      <int>[15, 21],
      <int>[22, lastDay],
    ];

/// Splits one month of the "if everything is paid" [forecast] into four
/// fixed blocks, so you can see the weeks where cash runs low before payday
/// even when the month as a whole works out.
///
/// Uses the same items as [forecastMonths]: recorded entries on their day,
/// monthly income not yet received on its day, each bill payment still due
/// on its due day, and each loan payment the forecast expects on the loan's
/// due day. Anything overdue or without a due day is counted on [today] in
/// the current month, or on the 1st of a later month. The last block ends
/// at the forecast's end cash.
List<WeekBlock> weekBlocks({
  required ForecastMonth forecast,
  required List<Entry> entries,
  required List<Bill> bills,
  required List<Loan> loans,
  List<IncomeSource> incomes = const <IncomeSource>[],
  required DateTime today,
}) {
  final month = forecast.month;
  final first = parseMonthKey(month);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  final floor = monthKey(today) == month ? today.day : 1;

  int place(int? day) {
    var d = day ?? floor;
    if (d < floor) d = floor;
    if (d > lastDay) d = lastDay;
    return d;
  }

  // Recorded money by day, and what is already paid or received.
  final recordedByDay = <int, int>{};
  final billPayments = <int, int>{};
  final receivedIncomes = <int>{};
  for (final e in entries) {
    if (!isInMonth(e.date, month) || e.date.length < 10) continue;
    final day = int.tryParse(e.date.substring(8, 10)) ?? 1;
    recordedByDay[day] = (recordedByDay[day] ?? 0) + signedAmount(e);
    if (e.type == EntryType.bill && e.billId != null) {
      billPayments[e.billId!] = (billPayments[e.billId!] ?? 0) + 1;
    }
    if (e.type == EntryType.income && e.incomeId != null) {
      receivedIncomes.add(e.incomeId!);
    }
  }

  final items = <WeekItem>[];
  for (final s in incomes) {
    if (!s.active || (s.id != null && receivedIncomes.contains(s.id))) {
      continue;
    }
    items.add(WeekItem(
      day: place(dayInMonth(first, s.day).day),
      label: s.name,
      amount: s.amount,
      kind: WeekItemKind.income,
    ));
  }
  for (final b in bills) {
    if (!b.active) continue;
    final days = billDueDays(b, month);
    final paid = billPayments[b.id] ?? 0;
    for (var i = paid; i < days.length; i++) {
      items.add(WeekItem(
        day: place(days[i]),
        label: b.name,
        amount: -b.amount,
        kind: WeekItemKind.bill,
        dayKnown: days[i] != null,
      ));
    }
  }
  for (final loan in loans) {
    final id = loan.id;
    if (id == null) continue;
    final due = forecast.loanDues[id] ?? 0;
    if (due <= 0) continue;
    final dueDay = loan.dueDay;
    items.add(WeekItem(
      day: place(dueDay == null ? null : dayInMonth(first, dueDay).day),
      label: loan.name,
      amount: -due,
      kind: WeekItemKind.loan,
      dayKnown: dueDay != null,
    ));
  }
  items.sort((a, b) => a.day.compareTo(b.day));

  final blocks = <WeekBlock>[];
  var cash = forecast.startCash;
  for (final range in blockRanges(lastDay)) {
    final from = range[0];
    final to = range[1];
    var recorded = 0;
    for (var d = from; d <= to; d++) {
      recorded += recordedByDay[d] ?? 0;
    }
    final block = WeekBlock(
      firstDay: from,
      lastDay: to,
      startCash: cash,
      recorded: recorded,
      items: <WeekItem>[
        for (final i in items)
          if (i.day >= from && i.day <= to) i,
      ],
      past: to < floor,
    );
    blocks.add(block);
    cash = block.endCash;
  }
  return blocks;
}
