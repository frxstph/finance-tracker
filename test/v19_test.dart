import 'package:finance_tracker/domain/bill_schedule.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/money.dart';
import 'package:finance_tracker/domain/summary.dart';
import 'package:finance_tracker/domain/weeks.dart';
import 'package:flutter_test/flutter_test.dart';

int _id = 900;

Entry e(EntryType type, int amount, String date,
    {int? billId, int? loanId, int? incomeId}) {
  return Entry(
    id: _id++,
    type: type,
    amount: amount,
    date: date,
    billId: billId,
    loanId: loanId,
    incomeId: incomeId,
    createdAt: '${date}T08:00:00.000',
  );
}

void main() {
  group('sums in amount boxes', () {
    test('adds, subtracts, multiplies and divides', () {
      expect(parseCentavos('450+120+35'), 60500);
      expect(parseCentavos('1,500*3'), 450000);
      expect(parseCentavos('1500×3'), 450000);
      expect(parseCentavos('2000/4'), 50000);
      expect(parseCentavos('2000÷4'), 50000);
      expect(parseCentavos('100+50×2'), 20000, reason: '× before +');
      expect(parseCentavos('1000-250.50'), 74950);
      expect(parseCentavos('₱ 450 + 120'), 57000);
      expect(parseCentavos('10/3'), 333, reason: 'rounded to the centavo');
      expect(parseCentavos('99.99*1.5'), 14999, reason: '149.985 rounds up');
    });

    test('rejects unfinished or impossible sums', () {
      for (final s in <String>[
        '450+',
        '+450',
        '450++120',
        '450+abc',
        '100/0',
        '100-200',
        '1.234+1',
        '999999999999*999999999999',
      ]) {
        expect(parseCentavos(s), isNull, reason: 'input "$s"');
      }
    });

    test('plain amounts still parse the old way', () {
      expect(isAmountExpression('1,250.50'), isFalse);
      expect(isAmountExpression('-5'), isFalse);
      expect(isAmountExpression('450+1'), isTrue);
      expect(parseCentavos('-5'), isNull);
      expect(parseCentavos('1 000'), isNull);
      expect(parseCentavos('₱1,250.50'), 125050);
    });
  });

  group('adjustments', () {
    test('change cash but are neither income nor spending', () {
      final s = computeSummary(
        month: '2026-11',
        entries: <Entry>[
          e(EntryType.income, 100000, '2026-11-01'),
          e(EntryType.adjustIn, 5000, '2026-11-03'),
          e(EntryType.adjustOut, 2000, '2026-11-04'),
        ],
        bills: const <Bill>[],
        loans: const <Loan>[],
      );
      expect(s.income, 100000);
      expect(s.spent, 0);
      expect(s.adjustments, 3000);
      expect(s.cash, 103000);
    });

    test('carry over into later months', () {
      final s = computeSummary(
        month: '2026-12',
        entries: <Entry>[e(EntryType.adjustIn, 5000, '2026-11-03')],
        bills: const <Bill>[],
        loans: const <Loan>[],
      );
      expect(s.openingCash, 5000);
    });

    test('one chip, two directions', () {
      expect(EntryType.adjustIn.isMoneyIn, isTrue);
      expect(EntryType.adjustOut.isMoneyIn, isFalse);
      expect(EntryType.adjustIn.userSelectable, isTrue);
      expect(EntryType.adjustOut.userSelectable, isFalse);
      expect(EntryType.fromDb('adjust_out'), EntryType.adjustOut);
    });
  });

  test('loan due day and accounts round trip', () {
    const loan = Loan(
      id: 1,
      name: 'L',
      principal: 100,
      created: '2026-11-01',
      startMonth: '2026-11',
      dueDay: 5,
    );
    expect(Loan.fromMap(loan.toMap()).dueDay, 5);
    expect(loan.copyWith(clearDueDay: true).dueDay, isNull);
    const acct = PayAccount(id: 2, name: 'Wallet A', details: 'Juan · 0917');
    final back = PayAccount.fromMap(acct.toMap());
    expect(back.name, 'Wallet A');
    expect(back.details, 'Juan · 0917');
    expect(back.photo, isNull);
  });

  test('bill due days follow the schedule', () {
    const weekly = Bill(
      id: 1,
      name: 'W',
      amount: 100,
      frequency: BillFrequency.weekly,
      startDate: '2026-11-02',
    );
    expect(billDueDays(weekly, '2026-11'), <int?>[2, 9, 16, 23, 30]);
    expect(billDueDays(weekly, '2026-12'), <int?>[7, 14, 21, 28]);
    const monthly31 = Bill(id: 2, name: 'M', amount: 100, startDate: '2026-10-31');
    expect(billDueDays(monthly31, '2026-11'), <int?>[30]);
    const old = Bill(id: 3, name: 'O', amount: 100);
    expect(billDueDays(old, '2026-11'), <int?>[null]);
  });

  group('week blocks', () {
    const pay = IncomeSource(id: 1, name: 'Pay', amount: 3000000, day: 19);
    const rent = Bill(id: 1, name: 'Rent', amount: 1000000, startDate: '2026-10-05');
    const old = Bill(id: 2, name: 'Old bill', amount: 50000);
    const loan = Loan(
      id: 1,
      name: 'Loan',
      principal: 600000,
      created: '2026-11-01',
      plan: LoanPlan.monthly,
      months: 6,
      startMonth: '2026-12',
      dueDay: 10,
    );

    List<WeekBlock> run(String month, List<Entry> entries, DateTime today) {
      final f = forecastMonths(
        fromMonth: '2026-11',
        toMonth: month,
        entries: entries,
        bills: const <Bill>[rent, old],
        loans: const <Loan>[loan],
        incomes: const <IncomeSource>[pay],
      ).last;
      final blocks = weekBlocks(
        forecast: f,
        entries: entries,
        bills: const <Bill>[rent, old],
        loans: const <Loan>[loan],
        incomes: const <IncomeSource>[pay],
        today: today,
      );
      expect(blocks.last.endCash, f.endCash, reason: 'blocks add up');
      return blocks;
    }

    test('fixed ranges, items on their days, and a short week', () {
      final blocks = run('2026-12', const <Entry>[], DateTime(2026, 11, 21));
      expect(blocks.map((b) => '${b.firstDay}-${b.lastDay}').toList(),
          <String>['1-7', '8-14', '15-21', '22-31']);
      // Dec: rent on the 5th and the old bill (no due day) on the 1st.
      expect(blocks[0].items.map((i) => i.label).toList(),
          <String>['Old bill', 'Rent']);
      expect(blocks[0].items.first.dayKnown, isFalse);
      expect(blocks[1].items.single.label, 'Loan');
      expect(blocks[1].items.single.amount, -100000);
      expect(blocks[2].items.single.label, 'Pay');
      expect(blocks.every((b) => !b.past), isTrue);
    });

    test('current month: overdue items land today, past blocks are done',
        () {
      final entries = <Entry>[e(EntryType.income, 500000, '2026-11-02')];
      final blocks = run('2026-11', entries, DateTime(2026, 11, 21));
      expect(blocks[0].past, isTrue);
      expect(blocks[0].recorded, 500000);
      // Rent (5th) and pay (19th) not recorded yet: counted on the 21st.
      final labels = blocks[2].items.map((i) => i.label).toSet();
      expect(labels, containsAll(<String>['Rent', 'Pay', 'Old bill']));
      expect(blocks[2].items.every((i) => i.day == 21), isTrue);
    });

    test('paid and received items drop out', () {
      final entries = <Entry>[
        e(EntryType.bill, 1000000, '2026-12-05', billId: 1),
        e(EntryType.income, 3000000, '2026-12-19', incomeId: 1),
      ];
      final blocks = run('2026-12', entries, DateTime(2026, 11, 21));
      expect(blocks[0].items.map((i) => i.label).toList(), <String>['Old bill']);
      expect(blocks[0].recorded, -1000000);
      expect(blocks[2].items, isEmpty);
      expect(blocks[2].recorded, 3000000);
    });
  });
}
