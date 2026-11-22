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

  group('e-wallet and bank screens', () {
    test('GCash payment receipt', () {
      final g = parseReceipt(<String>[
        'CORNER STATION',
        'Paid via GCash',
        'Amount  500.00',
        'Total  ₱ 500.00',
        'Your payment was successfully processed. You may present',
        'reference number below as your proof of payment.',
        'Date  Nov 10, 2026 10:21 PM',
        'Reference No.  123456789',
        'QRPH Invoice No.  654321',
      ], today: today);
      expect(g.amount, 50000);
      expect(g.date, DateTime(2026, 11, 10));
      expect(g.store, 'Corner Station');
    });

    test('bank app: the transfer, not the balance', () {
      final g = parseReceipt(<String>[
        '2:59 M BPI in',
        'Deposit accounts',
        'SAVINGS ACCOUNT',
        'Available balance',
        'PHP 12,345.67',
        'Total balance',
        'PHP 12,345.67',
        'Show details',
        'Transaction history',
        'Recent transactions',
        'InstaPay Transfer',
        'YOUR RECENT TRANSACTION',
        'Amount  - PHP 2,000.00',
        'NOV 19',
      ], today: today);
      expect(g.amount, 200000);
      expect(g.date, DateTime(2026, 11, 19));
      expect(g.store, isNull);
    });

    test('label and amount on separate rows', () {
      expect(
        findTotal(<String>['Available balance', 'PHP 12,345.67', 'Amount',
            '- PHP 2,000.00']),
        200000,
      );
    });

    test('month and day with no year', () {
      expect(findDate(<String>['NOV 19'], today), DateTime(2026, 11, 19));
      expect(findDate(<String>['DEC 30'], today), DateTime(2025, 12, 30));
    });

    test('keeps the lines it read', () {
      final g = parseReceipt(<String>['  A  ', '', 'B'], today: today);
      expect(g.lines, <String>['A', 'B']);
    });
  });

  // Formats from real GCash / bank screenshots. Names, numbers and amounts
  // are made up; the layout and wording are as the phone reads them.
  group('GCash screenshot formats', () {
    test('Send money: total amount sent, date on the Ref No. row', () {
      final g = parseReceipt(<String>[
        'MA•••••••A S.',
        '+63 9•••••1234',
        'Sent via GCash',
        'Amount  75.00',
        'Total Amount Sent  ₱75.00',
        'Ref No. 1234 567 890123  Nov 20, 2026 11:07 AM',
        '279g (gCO2e)',
        'By going digital, you reduce your carbon footprint from',
        'transportation, paper, and plastic.',
      ], today: today);
      expect(g.amount, 7500);
      expect(g.date, DateTime(2026, 11, 20));
      expect(g.store, 'Sent to MA…A S.');
      expect(g.reference, '1234567890123');
    });

    test('Loan payment: total paid, not the remaining balance', () {
      final g = parseReceipt(<String>[
        'GLoan Dues',
        'Loan Account No.  ABCD1234',
        'Paid via GCash',
        'Amount  650.40',
        'Total Paid  ₱ 650.40',
        'Remaining GLoan Balance  ₱ 3,250.10',
        'Posting of your payment will be reflected within 24',
        'hours.',
        'Date  Nov 15 2026, 10:38 PM',
        'Reference No.  1234567890123',
      ], today: today);
      expect(g.amount, 65040);
      expect(g.date, DateTime(2026, 11, 15));
      expect(g.store, 'GLoan Dues');
      expect(g.reference, '1234567890123');
    });

    test('QR payment to a shop', () {
      final g = parseReceipt(<String>[
        'Burger Place BP0212 MAIN 1',
        'Paid via GCash',
        'Amount  195.00',
        'Total  ₱ 195.00',
        'Your payment was successfully processed. You may present',
        'reference number below as your proof of payment.',
        'Date  Oct 31, 2026 2:11 PM',
        'Reference No.  123456789',
        'QRPH Invoice No.  654321',
      ], today: today);
      expect(g.amount, 19500);
      expect(g.date, DateTime(2026, 10, 31));
      expect(g.store, 'Burger Place BP0212 MAIN 1');
      expect(g.reference, '123456789');
    });

    test('Bank transfer: total with fee, date with no space after comma', () {
      final g = parseReceipt(<String>[
        'Bank Transfer Complete',
        'Sent via GCash',
        'Successful transactions are credited instantly. You will receive an update',
        'about this transaction in your GCash Inbox.',
        'Bank  Some Bank',
        'Account No.  •••••••••••1234',
        'Account Name  me',
        'Transfer Method  Instapay',
        'Transfer Amount  2,500.00',
        '+Fee  10.00',
        'Total  ₱ 2,510.00',
        'Date  Oct 31,2026 07:27 AM',
        'InstaPay Invoice No.  1234567',
        'Ref No.  1234567890123',
      ], today: today);
      expect(g.amount, 251000);
      expect(g.date, DateTime(2026, 10, 31));
      expect(g.store, 'Bank Transfer Complete');
      expect(g.reference, '1234567890123');
    });

    test('Load: total includes the convenience fee', () {
      final g = parseReceipt(<String>[
        'Go59 For Students With',
        'FREE 5G',
        'Some Name',
        '+63 900 000 0000',
        'Paid via GCash',
        'Amount  59.00',
        'Convenience Fee  1.00',
        'Load Plus Health Insurance  FREE',
        'Total  ₱ 60.00',
        'Schedule for Autoload',
        'Date  Oct 30, 2026 11:35 PM',
        'Reference No.  1234567890123',
      ], today: today);
      expect(g.amount, 6000);
      expect(g.date, DateTime(2026, 10, 30));
    });

    test('reader slips: 0ct for Oct, ₱ read as P, dots as thousands', () {
      final g = parseReceipt(<String>[
        'Total Amount Sent  P4.000.00',
        'Ref No. 1234 567 890123  0ct 31, 2026 11:51 AM',
      ], today: today);
      expect(g.amount, 400000);
      expect(g.date, DateTime(2026, 10, 31));
    });

    test('the same transfer twice has the same reference', () {
      List<String> shot(String time) => <String>[
            'JO•••N S.',
            'Sent via GCash',
            'Total Amount Sent  ₱150.00',
            'Ref No. 1111 222 333444  Oct 30, 2026 $time',
          ];
      final a = parseReceipt(shot('10:21 AM'), today: today);
      final b = parseReceipt(shot('9:44 AM'), today: today);
      expect(a.reference, b.reference);
      expect(a.amount, b.amount);
    });
  });
}
