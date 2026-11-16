import 'package:finance_tracker/domain/bill_schedule.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/summary.dart';
import 'package:flutter_test/flutter_test.dart';

const Bill legacy = Bill(id: 1, name: 'Old', amount: 100000);
const Bill weekly = Bill(
  id: 2,
  name: 'Weekly',
  amount: 50000,
  frequency: BillFrequency.weekly,
  startDate: '2026-11-02',
);
const Bill weekly6 = Bill(
  id: 3,
  name: 'Weekly x6',
  amount: 50000,
  frequency: BillFrequency.weekly,
  times: 6,
  startDate: '2026-11-02',
);
const Bill daily20 = Bill(
  id: 4,
  name: 'Daily x20',
  amount: 1000,
  frequency: BillFrequency.daily,
  times: 20,
  startDate: '2026-11-16',
);
const Bill monthly3 = Bill(
  id: 5,
  name: 'Monthly x3',
  amount: 80000,
  times: 3,
  startDate: '2026-11-16',
);
const Bill once = Bill(
  id: 6,
  name: 'Once',
  amount: 1200000,
  frequency: BillFrequency.once,
  startDate: '2026-12-05',
);

Entry pay(int billId, int amount, String date) => Entry(
      id: date.hashCode ^ billId,
      type: EntryType.bill,
      amount: amount,
      date: date,
      billId: billId,
      createdAt: '${date}T08:00:00.000',
    );

void main() {
  test('old monthly bills with no start are due every month', () {
    expect(billDueCount(legacy, '2020-01'), 1);
    expect(billDueCount(legacy, '2026-11'), 1);
  });

  test('weekly: every 7 days from the start, across month ends', () {
    expect(billDueCount(weekly, '2026-10'), 0);
    expect(billDueCount(weekly, '2026-11'), 5, reason: '2, 9, 16, 23, 30');
    expect(billDueCount(weekly, '2026-12'), 4, reason: '7, 14, 21, 28');
  });

  test('a set number of times stops the schedule', () {
    expect(billDueCount(weekly6, '2026-11'), 5);
    expect(billDueCount(weekly6, '2026-12'), 1, reason: 'the 6th is Dec 7');
    expect(billDueCount(weekly6, '2027-01'), 0);
    expect(billDueCount(daily20, '2026-11'), 15, reason: '16th to 30th');
    expect(billDueCount(daily20, '2026-12'), 5);
    expect(billDueCount(daily20, '2027-01'), 0);
    expect(billDueCount(monthly3, '2026-10'), 0);
    expect(billDueCount(monthly3, '2026-11'), 1);
    expect(billDueCount(monthly3, '2027-01'), 1);
    expect(billDueCount(monthly3, '2027-02'), 0);
  });

  test('one-time bills are due only in their month', () {
    expect(billDueCount(once, '2026-11'), 0);
    expect(billDueCount(once, '2026-12'), 1);
    expect(billDueCount(once, '2027-01'), 0);
  });

  test('why nothing is due', () {
    expect(billNotDueReason(monthly3, '2026-10'), 'Starts Nov 2026');
    expect(billNotDueReason(monthly3, '2027-02'), 'Finished');
    expect(billNotDueReason(once, '2026-11'), 'Due Dec 2026');
    expect(billNotDueReason(once, '2027-01'), 'Not this month');
    expect(billNotDueReason(weekly, '2026-11'), isNull);
  });

  test('left to pay counts each payment still due this month', () {
    final s = computeSummary(
      month: '2026-11',
      entries: <Entry>[
        pay(2, 50000, '2026-11-02'),
        pay(2, 50000, '2026-11-09'),
      ],
      bills: const <Bill>[weekly, once],
      loans: const <Loan>[],
    );
    final st = s.billStatus[2]!;
    expect(st.due, 5);
    expect(st.paid, 2);
    expect(st.left, 3);
    expect(s.billsLeftCount, 1, reason: 'the one-time bill is not due yet');
    expect(s.billsLeftAmount, 150000);
  });

  test('forecast pays every due payment of each schedule', () {
    final months = forecastMonths(
      fromMonth: '2026-11',
      toMonth: '2026-12',
      entries: const <Entry>[],
      bills: const <Bill>[weekly6, once],
      loans: const <Loan>[],
    );
    expect(months[0].billsToPay, 5 * 50000);
    expect(months[1].billsToPay, 50000 + 1200000);
  });

  test('schedule labels and round trip', () {
    String peso(int c) => 'P${c ~/ 100}';
    expect(billScheduleLabel(weekly6, peso), 'P500 a week · 6 times');
    expect(billScheduleLabel(legacy, peso), 'P1000 a month');
    expect(billScheduleLabel(once, peso), 'P12000 once');
    final back = Bill.fromMap(weekly6.toMap());
    expect(back.frequency, BillFrequency.weekly);
    expect(back.times, 6);
    expect(back.startDate, '2026-11-02');
    final old = Bill.fromMap(<String, Object?>{
      'id': 9,
      'name': 'X',
      'amount': 1,
      'active': 1,
    });
    expect(old.frequency, BillFrequency.monthly);
    expect(old.times, isNull);
    expect(old.startDate, isNull);
  });
}
