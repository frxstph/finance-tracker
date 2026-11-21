import 'package:finance_tracker/domain/calc.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

int _id = 2000;

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
  group('calculator line', () {
    test('works out the usual sums', () {
      expect(evaluateExpression('2+3×4'), 14);
      expect(evaluateExpression('1,250+300'), 1550);
      expect(evaluateExpression('10÷4'), 2.5);
      expect(evaluateExpression('-5+2'), -3);
      expect(evaluateExpression('8−3'), 5);
      expect(evaluateExpression('200×15%'), closeTo(30, 1e-9));
      expect(evaluateExpression('50%'), 0.5);
      expect(evaluateExpression('3×-2'), -6);
    });

    test('rejects unfinished lines', () {
      for (final s in <String>['', '5+', '×5', '5++', '5÷0', '1..2', 'abc']) {
        expect(evaluateExpression(s), isNull, reason: 'line "$s"');
      }
    });

    test('result to an amount', () {
      expect(resultToCentavos(12.5), 1250);
      expect(resultToCentavos(0.004), isNull, reason: 'rounds to ₱0');
      expect(resultToCentavos(0), isNull);
      expect(resultToCentavos(-3), isNull);
      expect(resultToCentavos(null), isNull);
    });
  });

  group('loan quote', () {
    test('monthly add-on interest', () {
      final q = quoteLoan(
        principal: 1000000,
        ratePercent: 3,
        months: 6,
        kind: InterestKind.monthlyAddOn,
      )!;
      expect(q.interest, 180000, reason: '₱10,000 × 3% × 6');
      expect(q.total, 1180000);
      expect(q.monthly, 196667, reason: 'rounded up');
    });

    test('yearly rate on the balance', () {
      final q = quoteLoan(
        principal: 10000000,
        ratePercent: 12,
        months: 12,
        kind: InterestKind.yearly,
      )!;
      // ₱100,000 at 12% a year for 12 months is about ₱8,884.88 a month.
      expect(q.monthly, inInclusiveRange(888488, 888489));
      expect(q.total, q.monthly * 12);
      expect(q.interest, q.total - 10000000);
    });

    test('zero interest and bad input', () {
      final q = quoteLoan(
        principal: 600000,
        ratePercent: 0,
        months: 6,
        kind: InterestKind.yearly,
      )!;
      expect(q.monthly, 100000);
      expect(q.interest, 0);
      expect(
          quoteLoan(
              principal: 0,
              ratePercent: 3,
              months: 6,
              kind: InterestKind.monthlyAddOn),
          isNull);
    });
  });

  test('split', () {
    final s = splitAmount(100000, 3)!;
    expect(s.each, 33333);
    expect(s.extra, 1);
    expect(splitAmount(100, 0), isNull);
  });

  group('afford and safe to spend', () {
    const pay = IncomeSource(id: 1, name: 'Pay', amount: 2000000, day: 19);
    const rent = Bill(id: 1, name: 'Rent', amount: 800000, startDate: '2026-10-05');
    final cash = <Entry>[e(EntryType.income, 1000000, '2026-11-01')];
    final today = DateTime(2026, 11, 10);

    test('a purchase that keeps every week above zero', () {
      final r = canAfford(
        amount: 500000,
        date: DateTime(2026, 11, 12),
        today: today,
        entries: cash,
        bills: const <Bill>[rent],
        loans: const <Loan>[],
        incomes: const <IncomeSource>[pay],
      );
      // Rent (5th, overdue) counts today: 10,000 − 8,000 = 2,000 left
      // through the 18th; buying for 5,000 on the 12th goes below zero.
      expect(r.affordable, isFalse);
      expect(r.lowest, 200000 - 500000);
      expect(r.lowestFirstDay, 8);
    });

    test('the same purchase after payday is fine', () {
      final r = canAfford(
        amount: 500000,
        date: DateTime(2026, 11, 20),
        today: today,
        entries: cash,
        bills: const <Bill>[rent],
        loans: const <Loan>[],
        incomes: const <IncomeSource>[pay],
      );
      expect(r.affordable, isTrue);
      expect(r.monthEnd, 1000000 - 800000 + 2000000 - 500000);
    });

    test('safe to spend until the next payday', () {
      final s = safeToSpend(
        today: today,
        entries: cash,
        bills: const <Bill>[rent],
        loans: const <Loan>[],
        incomes: const <IncomeSource>[pay],
      );
      expect(s.payday, DateTime(2026, 11, 19));
      expect(s.paydayName, 'Pay');
      expect(s.days, 9);
      expect(s.cashNow, 1000000);
      expect(s.dueBeforePayday, 800000);
      expect(s.free, 200000);
      expect(s.perDay, 200000 ~/ 9);
    });

    test('after payday it looks ahead to next month', () {
      final s = safeToSpend(
        today: DateTime(2026, 11, 25),
        entries: <Entry>[
          ...cash,
          e(EntryType.bill, 800000, '2026-11-05', billId: 1),
          e(EntryType.income, 2000000, '2026-11-19', incomeId: 1),
        ],
        bills: const <Bill>[rent],
        loans: const <Loan>[],
        incomes: const <IncomeSource>[pay],
      );
      expect(s.payday, DateTime(2026, 12, 19));
      expect(s.cashNow, 2200000);
      expect(s.dueBeforePayday, 800000, reason: 'December rent on the 5th');
      expect(s.days, 24);
    });

    test('no monthly income: until the end of the month', () {
      final s = safeToSpend(
        today: today,
        entries: cash,
        bills: const <Bill>[],
        loans: const <Loan>[],
      );
      expect(s.payday, DateTime(2026, 11, 30));
      expect(s.paydayName, isNull);
      expect(s.perDay, 1000000 ~/ 20);
    });
  });
}
