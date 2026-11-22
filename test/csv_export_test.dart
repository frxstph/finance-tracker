import 'package:finance_tracker/domain/csv_export.dart';
import 'package:finance_tracker/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Entry _e(EntryType type, int amount, String date,
        {String note = '', String? photo}) =>
    Entry(
      type: type,
      amount: amount,
      note: note,
      date: date,
      photo: photo,
      createdAt: '${date}T08:00:00',
    );

void main() {
  test('plainAmount', () {
    expect(plainAmount(125050), '1250.50');
    expect(plainAmount(-300), '-3.00');
    expect(plainAmount(5), '0.05');
  });

  test('csvField quotes and guards formulas', () {
    expect(csvField('Rice'), 'Rice');
    expect(csvField('Rice, eggs'), '"Rice, eggs"');
    expect(csvField('He said "hi"'), '"He said ""hi"""');
    expect(csvField('=SUM(A1)'), "'=SUM(A1)");
  });

  test('rows are oldest first with signed amounts', () {
    final csv = entriesToCsv(<Entry>[
      _e(EntryType.daily, 4500, '2026-11-21', note: 'Bread', photo: 'a.jpg'),
      _e(EntryType.income, 400000, '2026-11-15', note: 'Salary'),
    ], (_) => '');
    final lines = csv.split('\r\n');
    expect(lines[0], 'Date,Type,Amount,In or out,For,Note,Has photo');
    expect(lines[1], startsWith('2026-11-15,'));
    expect(lines[1], contains(',4000.00,In,,Salary,No'));
    expect(lines[2], contains(',-45.00,Out,,Bread,Yes'));
  });
}
