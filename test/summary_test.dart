import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/summary.dart';
import 'package:flutter_test/flutter_test.dart';

int _nextId = 1;

Entry e(EntryType type, int amount, String date, {int? billId, int? loanId}) {
  return Entry(
    id: _nextId++,
    type: type,
    amount: amount,
    date: date,
    billId: billId,
    loanId: loanId,
    createdAt: '${date}T08:00:00.000',
  );
}

const Bill water = Bill(id: 1, name: 'Bill A', amount: 50000);
const Bill power = Bill(id: 2, name: 'Bill B', amount: 120000);
const Bill oldBill =
    Bill(id: 3, name: 'Bill C', amount: 99900, active: false);
const Loan loanX =
    Loan(id: 10, name: 'Loan X', principal: 1000000, created: '2026-01-05',
        startMonth: '2026-01');
const Loan loanY =
    Loan(id: 11, name: 'Loan Y', principal: 200000, created: '2026-02-01',
        startMonth: '2026-02');

void main() {
  test('empty month is all zeros, bills all left', () {
    final s = computeSummary(
      month: '2026-11',
      entries: const <Entry>[],
      bills: const <Bill>[water, power, oldBill],
      loans: const <Loan>[],
    );
    expect(s.income, 0);
    expect(s.spent, 0);
    expect(s.loanPaid, 0);
    expect(s.cash, 0);
    expect(s.stillOwed, 0);
    expect(s.netPosition, -170000, reason: 'unpaid bills count against it');
    expect(s.billsLeftCount, 2, reason: 'archived bills are not counted');
    expect(s.billsLeftAmount, 170000);
    for (final t in EntryType.values) {
      expect(s.breakdown[t], 0);
    }
  });

  test('cash = income - spent - loan payments; loans never count as spent',
      () {
    final s = computeSummary(
      month: '2026-11',
      entries: <Entry>[
        e(EntryType.income, 2000000, '2026-11-01'),
        e(EntryType.bill, 50000, '2026-11-03', billId: 1),
        e(EntryType.oneTime, 30000, '2026-11-04'),
        e(EntryType.daily, 15050, '2026-11-05'),
        e(EntryType.loanPayment, 100000, '2026-11-06', loanId: 10),
      ],
      bills: const <Bill>[water, power],
      loans: const <Loan>[loanX],
    );
    expect(s.income, 2000000);
    expect(s.spent, 50000 + 30000 + 15050);
    expect(s.loanPaid, 100000);
    expect(s.cash, 2000000 - 95050 - 100000);
    expect(s.stillOwed, 900000);
    expect(s.netPosition, s.cash - 900000 - 120000);
    expect(s.breakdown[EntryType.loanPayment], 100000);
    expect(s.breakdown[EntryType.daily], 15050);
    expect(s.billsLeftCount, 1);
    expect(s.billsLeftAmount, 120000);
    expect(s.paidBillIds, <int>{1});
  });

  test('cash carries over from earlier months', () {
    final entries = <Entry>[
      e(EntryType.income, 500000, '2026-10-01'),
      e(EntryType.daily, 80000, '2026-11-02'),
    ];
    final nov = computeSummary(
      month: '2026-11',
      entries: entries,
      bills: const <Bill>[],
      loans: const <Loan>[],
    );
    expect(nov.openingCash, 500000, reason: 'October left 500000');
    expect(nov.monthChange, -80000);
    expect(nov.cash, 420000);
    expect(nov.netPosition, 420000);
    final oct = computeSummary(
      month: '2026-10',
      entries: entries,
      bills: const <Bill>[],
      loans: const <Loan>[],
    );
    expect(oct.openingCash, 0);
    expect(oct.cash, 500000);
    final dec = computeSummary(
      month: '2026-12',
      entries: entries,
      bills: const <Bill>[],
      loans: const <Loan>[],
    );
    expect(dec.cash, 420000, reason: 'an empty month keeps the cash');
  });

  test('cash can go negative and the shortfall carries over', () {
    final entries = <Entry>[
      e(EntryType.daily, 80000, '2026-11-02'),
      e(EntryType.income, 50000, '2026-12-02'),
    ];
    final dec = computeSummary(
      month: '2026-12',
      entries: entries,
      bills: const <Bill>[],
      loans: const <Loan>[],
    );
    expect(dec.openingCash, -80000);
    expect(dec.cash, -30000);
  });

  test('loan overpayment is clamped at 0 and still owed spans all time', () {
    final s = computeSummary(
      month: '2026-11',
      entries: <Entry>[
        e(EntryType.loanPayment, 150000, '2026-03-10', loanId: 11),
        e(EntryType.loanPayment, 100000, '2026-11-10', loanId: 11),
        e(EntryType.loanPayment, 250000, '2026-06-10', loanId: 10),
      ],
      bills: const <Bill>[],
      loans: const <Loan>[loanX, loanY],
    );
    // Loan Y: 200000 - 250000 -> 0 (not -50000). Loan X: 1000000 - 250000.
    expect(s.stillOwed, 750000);
    expect(s.loanPaid, 100000, reason: 'only November payments');
    expect(loanBalance(loanY, loanPaymentTotals(<Entry>[
      e(EntryType.loanPayment, 999999, '2026-01-01', loanId: 11),
    ])), 0);
  });

  test('a bill paid twice in a month counts once as paid, both amounts spent',
      () {
    final s = computeSummary(
      month: '2026-11',
      entries: <Entry>[
        e(EntryType.bill, 25000, '2026-11-02', billId: 1),
        e(EntryType.bill, 25000, '2026-11-20', billId: 1),
      ],
      bills: const <Bill>[water, power],
      loans: const <Loan>[],
    );
    expect(s.spent, 50000);
    expect(s.billsLeftCount, 1);
    expect(s.unpaidBills.single.id, 2);
    expect(s.paidBillIds, <int>{1});
  });

  test('entries on month boundaries land in the right month', () {
    final entries = <Entry>[
      e(EntryType.income, 100, '2026-10-31'),
      e(EntryType.income, 200, '2026-11-01'),
      e(EntryType.income, 400, '2026-11-30'),
      e(EntryType.income, 800, '2026-12-01'),
      e(EntryType.bill, 50000, '2026-10-31', billId: 1),
    ];
    final s = computeSummary(
      month: '2026-11',
      entries: entries,
      bills: const <Bill>[water],
      loans: const <Loan>[],
    );
    expect(s.income, 600);
    expect(s.billsLeftCount, 1,
        reason: 'paying on Oct 31 does not pay November');
  });

  test('December to January boundary', () {
    final entries = <Entry>[
      e(EntryType.daily, 1000, '2026-12-31'),
      e(EntryType.daily, 2000, '2027-01-01'),
    ];
    final jan = computeSummary(
      month: '2027-01',
      entries: entries,
      bills: const <Bill>[],
      loans: const <Loan>[],
    );
    expect(jan.spent, 2000);
  });
}
