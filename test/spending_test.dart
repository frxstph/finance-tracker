import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/spending.dart';
import 'package:flutter_test/flutter_test.dart';

Entry _e(EntryType t, int amount, String date) =>
    Entry(type: t, amount: amount, note: '', date: date, createdAt: '${date}T09:00:00');

void main() {
  final today = DateTime(2026, 11, 23);
  final entries = <Entry>[
    _e(EntryType.daily, 10000, '2026-11-23'),
    _e(EntryType.daily, 5000, '2026-11-23'),
    _e(EntryType.oneTime, 20000, '2026-11-01'),
    _e(EntryType.bill, 50000, '2026-11-10'),
    _e(EntryType.loanPayment, 67970, '2026-11-15'),
    _e(EntryType.income, 400000, '2026-11-15'),
    _e(EntryType.adjustOut, 3000, '2026-11-16'),
    _e(EntryType.daily, 8000, '2026-10-25'),
    _e(EntryType.daily, 7000, '2026-10-24'), // 31 days back: outside 30 days
    _e(EntryType.daily, 4000, '2026-10-05'),
    _e(EntryType.bill, 30000, '2026-08-10'),
  ];

  test('30 days: one bar a day, everyday only, oldest first', () {
    final bars = last30Days(entries, today);
    expect(bars.length, 30);
    expect(bars.first.day, DateTime(2026, 10, 25));
    expect(bars.last.day, DateTime(2026, 11, 23));
    expect(bars.last.amount, 15000);
    expect(bars.first.amount, 8000);
    expect(bars.fold<int>(0, (s, b) => s + b.amount), 43000);
  });

  test('totals split everyday from bills and loans; income and adjustments out',
      () {
    final t = totalsBetween(entries, DateTime(2026, 11, 1), today);
    expect(t.everyday, 35000);
    expect(t.billsLoans, 117970);
  });

  test('weeks: four blocks against last month, current one in progress', () {
    final w = weekBars(entries, today);
    expect(w.map((b) => b.label), <String>['1–7', '8–14', '15–21', '22–30']);
    expect(w[0].thisMonth, 20000);
    expect(w[3].thisMonth, 15000);
    expect(w[3].inProgress, isTrue);
    expect(w[0].lastMonth, 4000);
    expect(w[3].lastMonth, 15000); // Oct 22–31: 24th + 25th
    expect(w.where((b) => b.future), isEmpty);
  });

  test('month to date compares with the same days last month', () {
    final m = monthToDate(entries, today);
    expect(m.thisMonth, 35000);
    expect(m.lastMonth, 4000); // Oct 1–23
  });

  test('months: 12 ending this month', () {
    final m = monthBars(entries, today);
    expect(m.length, 12);
    expect(m.first.start, DateTime(2025, 12, 1));
    expect(m.last.start, DateTime(2026, 11, 1));
    expect(m.last.inProgress, isTrue);
    expect(m.last.everyday, 35000);
    expect(m.last.billsLoans, 117970);
    expect(m[8].billsLoans, 30000); // August
    expect(m.map((b) => b.label).join(), 'DJFMAMJJASON');
  });

  test('quarters of this year', () {
    final q = quarterBars(entries, today);
    expect(q.map((b) => b.label), <String>['Q1', 'Q2', 'Q3', 'Q4']);
    expect(q[2].billsLoans, 30000);
    expect(q[3].inProgress, isTrue);
    expect(q[3].everyday, 35000 + 8000 + 7000 + 4000);
    expect(q.where((b) => b.future), isEmpty);
  });

  test('compactPeso', () {
    expect(compactPeso(8220000), '₱82.2k');
    expect(compactPeso(95000), '₱950');
    expect(compactPeso(130000000), '₱1.3M');
  });
}
