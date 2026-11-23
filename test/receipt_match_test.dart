import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/receipt_match.dart';
import 'package:finance_tracker/domain/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptGuess _g(List<String> lines, {int? amount, String? store}) =>
    ReceiptGuess(amount: amount, store: store, lines: lines);

void main() {
  const gloan = PaymentCandidate.loan(id: 1, name: 'GLoan', expected: 65040);
  const joint = PaymentCandidate.loan(id: 2, name: 'Joint loan', expected: 446200);
  const water = PaymentCandidate.bill(id: 7, name: 'Water bill', expected: 50000);
  const power = PaymentCandidate.bill(id: 8, name: 'Meralco', expected: 235000);
  final all = <PaymentCandidate>[gloan, joint, water, power];

  test('name words skip generic words', () {
    expect(nameWords('GLoan'), <String>['gloan']);
    expect(nameWords('Joint loan'), <String>['joint']);
    expect(nameWords('Meralco bill'), <String>['meralco']);
    expect(nameWords('Loan'), isEmpty);
  });

  test('GLoan Dues receipt → Loan payment · GLoan', () {
    final m = matchPayment(
      _g(<String>['GLoan Dues', 'Paid via GCash', 'Total Paid  ₱ 650.40'],
          amount: 65040, store: 'GLoan Dues'),
      all,
    );
    expect(m, isNotNull);
    expect(m!.type, EntryType.loanPayment);
    expect(m.loanId, 1);
    expect(m.byName, isTrue);
    expect(m.byAmount, isTrue);
    expect(m.label, 'Loan payment · GLoan');
  });

  test('a biller name → Bill', () {
    final m = matchPayment(
      _g(<String>['MERALCO', 'Paid via GCash', 'Total ₱ 2,410.00'],
          amount: 241000),
      all,
    );
    expect(m?.type, EntryType.bill);
    expect(m?.billId, 8);
    expect(m?.byAmount, isFalse); // name is enough; amount differs this month
  });

  test('a shop receipt matches nothing', () {
    expect(
      matchPayment(
          _g(<String>['Corner Bakery', 'TOTAL 50.00'], amount: 5000), all),
      isNull,
    );
  });

  test('"water" in a store name alone is not the water bill', () {
    // "Water bill" needs the word water; a refilling station has it too, so
    // name matching alone would pick it. That is accepted: the person sees
    // it on Check and save. But the word must be a whole word.
    expect(
      matchPayment(_g(<String>['Watermelon stand', 'TOTAL 80.00'], amount: 8000),
          all),
      isNull,
    );
  });

  test('by amount only when the receipt says loan', () {
    final saysLoan = matchPayment(
      _g(<String>['Loan payment', 'Amount 4,462.00'], amount: 446200),
      all,
    );
    expect(saysLoan?.loanId, 2);
    expect(saysLoan?.byName, isFalse);
    final silent = matchPayment(
      _g(<String>['Sent via GCash', 'Total Amount Sent ₱4,462.00'],
          amount: 446200),
      all,
    );
    expect(silent, isNull);
  });

  test('two loans named on the receipt: the amount decides, else none', () {
    const g2 = PaymentCandidate.loan(id: 3, name: 'GLoan 2', expected: 120000);
    final cands = <PaymentCandidate>[gloan, g2];
    final lines = <String>['GLoan Dues', 'GLoan 2', 'Total Paid ₱ 650.40'];
    expect(matchPayment(_g(lines, amount: 65040), cands)?.loanId, 1);
    expect(matchPayment(_g(lines, amount: 99900), cands), isNull);
  });
}
