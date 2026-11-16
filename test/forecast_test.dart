import 'package:finance_tracker/domain/dates.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/summary.dart';
import 'package:flutter_test/flutter_test.dart';

int _nextId = 500;

Entry e(EntryType type, int amount, String date,
    {int? billId, int? loanId, int? incomeId}) {
  return Entry(
    id: _nextId++,
    type: type,
    amount: amount,
    date: date,
    billId: billId,
    loanId: loanId,
    incomeId: incomeId,
    createdAt: '${date}T08:00:00.000',
  );
}

const Bill water = Bill(id: 1, name: 'Bill A', amount: 50000);
const IncomeSource salary =
    IncomeSource(id: 1, name: 'Pay A', amount: 3000000, day: 19);
const IncomeSource stopped = IncomeSource(
    id: 2, name: 'Pay B', amount: 999900, day: 1, active: false);

// ₱6,000 over 6 months from December: ₱1,000 a month.
const Loan loan = Loan(
  id: 1,
  name: 'Loan M',
  principal: 600000,
  created: '2026-11-10',
  plan: LoanPlan.monthly,
  months: 6,
  startMonth: '2026-12',
);

final List<Entry> novEntries = <Entry>[
  e(EntryType.income, 2000000, '2026-11-01'),
  e(EntryType.daily, 50000, '2026-11-05'),
];

List<ForecastMonth> run(String to, List<Entry> entries) => forecastMonths(
      fromMonth: '2026-11',
      toMonth: to,
      entries: entries,
      bills: const <Bill>[water],
      loans: const <Loan>[loan],
      incomes: const <IncomeSource>[salary, stopped],
    );

void main() {
  test('this month: recorded money plus what is still expected', () {
    final nov = run('2026-11', novEntries).single;
    expect(nov.startCash, 0);
    expect(nov.recorded, 1950000);
    expect(nov.incomeToCome, 3000000, reason: 'archived income is skipped');
    expect(nov.billsToPay, 50000);
    expect(nov.loanPayments, 0, reason: 'the loan starts in December');
    expect(nov.endCash, 4900000);
    expect(nov.owedAfter, 600000);
    expect(nov.netPosition, 4300000);
  });

  test('later months chain from the month before', () {
    final months = run('2027-01', novEntries);
    expect(months.map((m) => m.month).toList(),
        <String>['2026-11', '2026-12', '2027-01']);
    final dec = months[1];
    expect(dec.startCash, 4900000);
    expect(dec.incomeToCome, 3000000);
    expect(dec.loanPayments, 100000);
    expect(dec.endCash, 4900000 + 3000000 - 50000 - 100000);
    expect(dec.owedAfter, 500000);
    final jan = months[2];
    expect(jan.startCash, dec.endCash);
    expect(jan.loanPayments, 100000,
        reason: 'December is assumed paid, so no catch-up');
    expect(jan.owedAfter, 400000);
  });

  test('received income and paid bills are not counted twice', () {
    final entries = <Entry>[
      ...novEntries,
      e(EntryType.income, 3000000, '2026-11-19', incomeId: 1),
      e(EntryType.bill, 50000, '2026-11-20', billId: 1),
    ];
    final nov = run('2026-11', entries).single;
    expect(nov.incomeToCome, 0);
    expect(nov.billsToPay, 0);
    expect(nov.endCash, 4900000, reason: 'same end, now all recorded');
  });

  test('a payment already made ahead covers the forecast month', () {
    final entries = <Entry>[
      ...novEntries,
      e(EntryType.loanPayment, 100000, '2026-11-25', loanId: 1),
    ];
    final dec = run('2026-12', entries)[1];
    expect(dec.loanPayments, 0);
    expect(dec.owedAfter, 500000);
  });

  test('the loan is never paid past its balance', () {
    final months = run('2027-08', novEntries);
    expect(months.last.owedAfter, 0);
    final total = months.fold<int>(0, (s, m) => s + m.loanPayments);
    expect(total, 600000);
  });

  test('no forecast for months already over', () {
    expect(run('2026-10', novEntries), isEmpty);
  });

  test('summary lists monthly income still to come', () {
    final s = computeSummary(
      month: '2026-11',
      entries: <Entry>[
        e(EntryType.income, 1000, '2026-12-19', incomeId: 1),
      ],
      bills: const <Bill>[],
      loans: const <Loan>[],
      incomes: const <IncomeSource>[salary, stopped],
    );
    expect(s.incomesLeft.map((i) => i.id).toList(), <int?>[1],
        reason: 'December receipt does not count for November');
    expect(s.incomeLeftAmount, 3000000);
    final dec = computeSummary(
      month: '2026-12',
      entries: <Entry>[
        e(EntryType.income, 1000, '2026-12-19', incomeId: 1),
      ],
      bills: const <Bill>[],
      loans: const <Loan>[],
      incomes: const <IncomeSource>[salary],
    );
    expect(dec.incomesLeft, isEmpty);
    expect(dec.receivedIncomeIds, <int>{1});
  });

  test('income sources round trip and entries keep their source', () {
    expect(IncomeSource.fromMap(salary.toMap()).day, 19);
    expect(IncomeSource.fromMap(stopped.toMap()).active, isFalse);
    final x = e(EntryType.income, 100, '2026-11-19', incomeId: 1);
    expect(Entry.fromMap(x.toMap()).incomeId, 1);
    expect(Entry.fromMap(<String, Object?>{
      'id': 1,
      'type': 'income',
      'amount': 5,
      'date': '2026-11-01',
      'created_at': '2026-11-01T00:00:00.000',
    }).incomeId, isNull, reason: 'older rows have no income_id');
  });

  test('day of month helpers', () {
    expect(ordinalDay(1), '1st');
    expect(ordinalDay(2), '2nd');
    expect(ordinalDay(3), '3rd');
    expect(ordinalDay(11), '11th');
    expect(ordinalDay(15), '15th');
    expect(ordinalDay(19), '19th');
    expect(ordinalDay(21), '21st');
    expect(ordinalDay(22), '22nd');
    expect(ordinalDay(31), '31st');
    expect(dayInMonth(DateTime(2027, 2), 31), DateTime(2027, 2, 28));
    expect(dayInMonth(DateTime(2028, 2), 30), DateTime(2028, 2, 29));
    expect(dayInMonth(DateTime(2026, 11), 19), DateTime(2026, 11, 19));
  });
}
