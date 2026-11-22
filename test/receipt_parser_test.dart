import 'package:finance_tracker/domain/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 11, 22);

  group('amountsIn', () {
    test('reads pesos with centavos', () {
      expect(amountsIn('TOTAL 1,248.50'), <int>[124850]);
      expect(amountsIn('₱35.00 x2 70.00'), <int>[3500, 7000]);
      expect(amountsIn('PHP1248.50'), <int>[124850]);
      expect(amountsIn('P 1 248.50'), <int>[124850]);
    });

    test('ignores numbers without centavos', () {
      expect(amountsIn('TIN 123-456-789-000'), isEmpty);
      expect(amountsIn('Qty 3'), isEmpty);
      expect(amountsIn('1,248'), isEmpty);
    });
  });

  group('findTotal', () {
    test('uses the total line, not subtotal, cash or change', () {
      final lines = <String>[
        'SUBTOTAL 1,114.73',
        'VAT 12% 133.77',
        'TOTAL 1,248.50',
        'CASH 1,500.00',
        'CHANGE 251.50',
      ];
      expect(findTotal(lines), 124850);
    });

    test('prefers amount due over a plain total', () {
      final lines = <String>[
        'TOTAL 900.00',
        'DISCOUNT 100.00',
        'AMOUNT DUE 800.00',
      ];
      expect(findTotal(lines), 80000);
    });

    test('finds the amount on the line after the label', () {
      final lines = <String>['TOTAL', '459.25', 'CASH', '500.00'];
      expect(findTotal(lines), 45925);
    });

    test('falls back to the largest amount that is not cash or change', () {
      final lines = <String>['Rice 50.00', 'Eggs 120.00', 'CASH 500.00'];
      expect(findTotal(lines), 12000);
    });

    test('a dotted date is not money', () {
      expect(findTotal(<String>['11.21.26', 'Bread 45.00']), 4500);
    });

    test('nothing readable gives null', () {
      expect(findTotal(<String>['Thank you', 'Come again']), isNull);
    });
  });

  group('findDate', () {
    test('month-first slash dates', () {
      expect(findDate(<String>['Date: 11/21/2026'], today),
          DateTime(2026, 11, 21));
      expect(findDate(<String>['11/21/26 14:05'], today),
          DateTime(2026, 11, 21));
    });

    test('day-first when month-first is impossible', () {
      expect(findDate(<String>['21/11/2026'], today), DateTime(2026, 11, 21));
    });

    test('year first and written months', () {
      expect(findDate(<String>['2026-11-20'], today), DateTime(2026, 11, 20));
      expect(findDate(<String>['Nov 19, 2026'], today), DateTime(2026, 11, 19));
      expect(findDate(<String>['18 November 2026'], today),
          DateTime(2026, 11, 18));
    });

    test('skips future and very old dates', () {
      expect(findDate(<String>['12/25/2026'], today), isNull);
      expect(findDate(<String>['01/02/2020'], today), isNull);
    });
  });

  group('findStore', () {
    test('first name-like line, title-cased', () {
      final lines = <String>[
        'GREENLEAF MINI MART',
        'VAT REG TIN 123-456-789-000',
        'Official Receipt',
      ];
      expect(findStore(lines), 'Greenleaf Mini Mart');
    });

    test('skips receipt headings', () {
      expect(findStore(<String>['OFFICIAL RECEIPT', 'Corner Bakery']),
          'Corner Bakery');
    });
  });

  test('parseReceipt puts it together', () {
    final g = parseReceipt(<String>[
      'CORNER BAKERY',
      '11/21/2026 08:15',
      'Pandesal 10 pcs 50.00',
      'TOTAL 50.00',
      'CASH 100.00',
    ], today: today);
    expect(g.amount, 5000);
    expect(g.date, DateTime(2026, 11, 21));
    expect(g.store, 'Corner Bakery');
  });
}
