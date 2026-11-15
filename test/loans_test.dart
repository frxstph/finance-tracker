import 'package:finance_tracker/domain/dates.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/summary.dart';
import 'package:flutter_test/flutter_test.dart';

int _nextId = 100;

Entry e(EntryType type, int amount, String date, {int? loanId}) {
  return Entry(
    id: _nextId++,
    type: type,
    amount: amount,
    date: date,
    loanId: loanId,
    createdAt: '${date}T08:00:00.000',
  );
}

// ₱6,000 over 6 months from December: ₱1,000 a month.
const Loan monthly = Loan(
  id: 1,
  name: 'Loan M',
  principal: 600000,
  created: '2026-11-10',
  plan: LoanPlan.monthly,
  months: 6,
  startMonth: '2026-12',
);

// ₱1,000 paid in one go, due November.
const Loan full = Loan(
  id: 2,
  name: 'Loan F',
  principal: 100000,
  created: '2026-10-01',
  startMonth: '2026-11',
);

MonthSummary sum(String month, List<Entry> entries, List<Loan> loans) =>
    computeSummary(
      month: month,
      entries: entries,
      bills: const <Bill>[],
      loans: loans,
    );

int due(Loan loan, String month, List<Entry> entries) =>
    loanDueInMonth(loan, month, entries, loanPaymentTotals(entries));

void main() {
  test('money received from a loan raises cash but is not income', () {
    final entries = <Entry>[
      e(EntryType.loanReceived, 600000, '2026-11-10', loanId: 1),
      e(EntryType.daily, 50000, '2026-11-11'),
    ];
    final s = sum('2026-11', entries, const <Loan>[monthly]);
    expect(s.income, 0);
    expect(s.loanReceived, 600000);
    expect(s.cash, 550000);
    expect(s.stillOwed, 600000, reason: 'receiving does not pay it down');
    expect(s.netPosition, 550000 - 600000);
    expect(s.breakdown[EntryType.loanReceived], 600000);
  });

  test('nothing is due before the first payment month', () {
    expect(due(monthly, '2026-11', const <Entry>[]), 0);
    expect(sum('2026-11', const <Entry>[], const <Loan>[monthly]).loanDues,
        isEmpty);
  });

  test('monthly plan: one installment a month, paid months clear', () {
    expect(due(monthly, '2026-12', const <Entry>[]), 100000);
    final paidDec = <Entry>[
      e(EntryType.loanPayment, 100000, '2026-12-15', loanId: 1),
    ];
    expect(due(monthly, '2026-12', paidDec), 0);
    expect(due(monthly, '2027-01', paidDec), 100000);
  });

  test('a missed month rolls into the next one', () {
    final paidDec = <Entry>[
      e(EntryType.loanPayment, 100000, '2026-12-15', loanId: 1),
    ];
    // January missed: February owes two installments.
    expect(due(monthly, '2027-02', paidDec), 200000);
  });

  test('paying ahead covers later months', () {
    final paidAhead = <Entry>[
      e(EntryType.loanPayment, 300000, '2026-12-15', loanId: 1),
    ];
    expect(due(monthly, '2027-01', paidAhead), 0);
    expect(due(monthly, '2027-02', paidAhead), 0);
    expect(due(monthly, '2027-03', paidAhead), 100000);
  });

  test('after the last month, the remaining balance is due', () {
    final some = <Entry>[
      e(EntryType.loanPayment, 200000, '2027-01-15', loanId: 1),
    ];
    expect(due(monthly, '2027-09', some), 400000);
  });

  test('installments round up and never exceed the total', () {
    const odd = Loan(
      id: 3,
      name: 'Loan O',
      principal: 100000,
      created: '2026-11-01',
      plan: LoanPlan.monthly,
      months: 3,
      startMonth: '2026-11',
    );
    expect(odd.installment, 33334);
    expect(due(odd, '2027-01', const <Entry>[]), 100000);
  });

  test('pay in full: whole balance due from the due month', () {
    expect(due(full, '2026-10', const <Entry>[]), 0);
    expect(due(full, '2026-11', const <Entry>[]), 100000);
    final partial = <Entry>[
      e(EntryType.loanPayment, 40000, '2026-11-20', loanId: 2),
    ];
    expect(due(full, '2026-11', partial), 60000);
    expect(due(full, '2026-12', partial), 60000);
  });

  test('a later payment that clears the loan means nothing is due', () {
    final later = <Entry>[
      e(EntryType.loanPayment, 100000, '2026-12-05', loanId: 2),
    ];
    expect(due(full, '2026-11', later), 0);
  });

  test('left to pay adds loan dues to unpaid bills', () {
    const bill = Bill(id: 7, name: 'Bill', amount: 50000);
    final s = computeSummary(
      month: '2026-12',
      entries: const <Entry>[],
      bills: const <Bill>[bill],
      loans: const <Loan>[monthly, full],
    );
    expect(s.loanDues, <int, int>{1: 100000, 2: 100000});
    expect(s.loanDueCount, 2);
    expect(s.leftToPayAmount, 50000 + 200000);
  });

  test('payments covered counts whole installments', () {
    expect(paymentsCovered(monthly, 0), 0);
    expect(paymentsCovered(monthly, 250000), 2);
    expect(paymentsCovered(monthly, 900000), 6);
    expect(paymentsCovered(full, 100000), 1);
  });

  test('old loan rows read as pay in full, due the month they were added',
      () {
    final l = Loan.fromMap(<String, Object?>{
      'id': 5,
      'name': 'Old',
      'principal': 100000,
      'created': '2026-03-15',
    });
    expect(l.plan, LoanPlan.full);
    expect(l.months, 1);
    expect(l.startMonth, '2026-03');
    expect(Loan.fromMap(l.toMap()).startMonth, '2026-03');
  });

  test('loan photo survives a save round trip and can be cleared', () {
    final withPhoto = full.copyWith(photo: '123_000001.jpg');
    expect(withPhoto.hasPhoto, isTrue);
    expect(Loan.fromMap(withPhoto.toMap()).photo, '123_000001.jpg');
    expect(withPhoto.copyWith(name: 'Renamed').photo, '123_000001.jpg');
    expect(withPhoto.copyWith(clearPhoto: true).photo, isNull);
    expect(full.hasPhoto, isFalse);
  });

  test('loan received entries link to their loan', () {
    expect(EntryType.loanReceived.needsLoan, isTrue);
    expect(EntryType.loanReceived.isMoneyIn, isTrue);
    expect(EntryType.loanReceived.userSelectable, isFalse);
    expect(EntryType.fromDb('loan_received'), EntryType.loanReceived);
  });

  test('month keys', () {
    expect(monthsBetween('2026-11', '2027-02'), 3);
    expect(monthsBetween('2027-02', '2026-11'), -3);
    expect(isValidMonthKey('2026-12'), isTrue);
    expect(isValidMonthKey('2026-13'), isFalse);
    expect(isValidMonthKey('2026-1'), isFalse);
    expect(shortMonthLabel('2027-01'), 'Jan 2027');
  });
}
