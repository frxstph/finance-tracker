import 'package:finance_tracker/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCentavos', () {
    test('accepts plain, grouped, decimal and peso-signed input', () {
      expect(parseCentavos('1250'), 125000);
      expect(parseCentavos('1,250'), 125000);
      expect(parseCentavos('1250.5'), 125050);
      expect(parseCentavos('1250.50'), 125050);
      expect(parseCentavos('1,250.50'), 125050);
      expect(parseCentavos('₱1,250.50'), 125050);
      expect(parseCentavos('₱ 1,250.50'), 125050);
      expect(parseCentavos('  42  '), 4200);
      expect(parseCentavos('0.05'), 5);
      expect(parseCentavos('1,234,567.89'), 123456789);
    });

    test('zero parses to 0 (callers reject it)', () {
      expect(parseCentavos('0'), 0);
      expect(parseCentavos('0.00'), 0);
    });

    test('rejects negatives, garbage and too many decimals', () {
      const bad = <String>[
        '',
        '   ',
        '₱',
        '-1',
        '-1,250.50',
        '₱-5',
        'abc',
        '12a',
        '1.234',
        '1250.505',
        '1,25',
        '12,50.00',
        ',100',
        '100,',
        '1..5',
        '.5',
        '5.',
        '1 000',
      ];
      for (final s in bad) {
        expect(parseCentavos(s), isNull, reason: 'input "$s"');
      }
    });

    test('rejects absurdly large amounts', () {
      expect(parseCentavos('1234567890123'), isNull);
    });
  });

  group('formatPeso', () {
    test('drops .00 for whole amounts', () {
      expect(formatPeso(125000), '₱1,250');
      expect(formatPeso(0), '₱0');
      expect(formatPeso(100), '₱1');
    });

    test('keeps two decimals otherwise', () {
      expect(formatPeso(125050), '₱1,250.50');
      expect(formatPeso(5), '₱0.05');
      expect(formatPeso(123456789), '₱1,234,567.89');
    });

    test('negative amounts', () {
      expect(formatPeso(-125050), '-₱1,250.50');
      expect(formatPeso(-300), '-₱3');
    });
  });

  group('round trips', () {
    test('format then parse returns the same centavos', () {
      const values = <int>[0, 1, 5, 99, 100, 125000, 125050, 99999999, 100001];
      for (final v in values) {
        expect(parseCentavos(formatPeso(v)), v, reason: 'value $v');
        expect(parseCentavos(centavosToInput(v)), v, reason: 'value $v');
      }
    });

    test('centavosToInput gives plain editable text', () {
      expect(centavosToInput(125050), '1250.50');
      expect(centavosToInput(125000), '1250');
      expect(centavosToInput(7), '0.07');
    });
  });
}
