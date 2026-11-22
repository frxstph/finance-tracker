import 'package:finance_tracker/domain/bulk_import.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:finance_tracker/domain/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

ImportDraft _d({
  int? amount,
  DateTime? date,
  String? ref,
  bool dateGuessed = false,
  bool amountGuessed = false,
}) =>
    ImportDraft(
      photoPath: 'p.jpg',
      guess: ReceiptGuess(
        amount: amount,
        date: date,
        reference: ref,
        dateGuessed: dateGuessed,
        amountGuessed: amountGuessed,
      ),
    );

void main() {
  final now = DateTime(2026, 11, 22, 15);

  test('ready when amount and full date are found', () {
    final r = reviewDrafts(
        <ImportDraft>[_d(amount: 5000, date: DateTime(2026, 11, 21))],
        const <Entry>[],
        now);
    expect(r.single.status, ImportStatus.ready);
    expect(r.single.addByDefault, isTrue);
  });

  test('needs a fix without amount or date, or with a future date', () {
    final r = reviewDrafts(<ImportDraft>[
      _d(date: DateTime(2026, 11, 21)),
      _d(amount: 100),
      _d(amount: 100, date: DateTime(2026, 11, 30)),
    ], const <Entry>[], now);
    expect(r.map((x) => x.status), everyElement(ImportStatus.needsFix));
    expect(r[0].reason, 'Needs an amount');
    expect(r[1].reason, 'Needs a date');
    expect(r.every((x) => !x.addByDefault), isTrue);
  });

  test('same reference twice: the second is a duplicate', () {
    final r = reviewDrafts(<ImportDraft>[
      _d(amount: 15000, date: DateTime(2026, 10, 30), ref: '111'),
      _d(amount: 15000, date: DateTime(2026, 10, 30), ref: '111'),
    ], const <Entry>[], now);
    expect(r[0].status, ImportStatus.ready);
    expect(r[1].status, ImportStatus.duplicate);
    expect(r[1].reason, 'Same receipt as photo 1');
  });

  test('same amount and date as an existing money-out entry', () {
    final existing = <Entry>[
      const Entry(
        id: 1,
        type: EntryType.daily,
        amount: 50000,
        note: '',
        date: '2026-11-18',
        createdAt: '2026-11-18T10:00:00',
      ),
    ];
    final r = reviewDrafts(
        <ImportDraft>[_d(amount: 50000, date: DateTime(2026, 11, 18))],
        existing,
        now);
    expect(r.single.status, ImportStatus.duplicate);
    expect(r.single.reason, 'Same as an entry on Wed 18 Nov');
  });

  test('guessed date or amount, or an old date: check', () {
    final r = reviewDrafts(<ImportDraft>[
      _d(amount: 100, date: DateTime(2026, 11, 19), dateGuessed: true),
      _d(amount: 200, date: DateTime(2026, 11, 19), amountGuessed: true),
      _d(amount: 300, date: DateTime(2026, 8, 1)),
    ], const <Entry>[], now);
    expect(r.map((x) => x.status), everyElement(ImportStatus.check));
    expect(r.every((x) => x.addByDefault), isTrue);
  });

  test('a fixed draft is ready even if the reader guessed', () {
    final d = _d(amount: 100, date: DateTime(2026, 11, 19), dateGuessed: true)
      ..fixed = true;
    expect(reviewDrafts(<ImportDraft>[d], const <Entry>[], now).single.status,
        ImportStatus.ready);
  });

  test('reader flags: no total label, no year', () {
    final today = DateTime(2026, 11, 22);
    final a = parseReceipt(<String>['Rice 50.00', 'Eggs 120.00', 'NOV 19'],
        today: today);
    expect(a.amountGuessed, isTrue);
    expect(a.dateGuessed, isTrue);
    final b = parseReceipt(<String>['TOTAL 50.00', 'Nov 19, 2026'],
        today: today);
    expect(b.amountGuessed, isFalse);
    expect(b.dateGuessed, isFalse);
  });
}
