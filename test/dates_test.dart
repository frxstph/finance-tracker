import 'package:finance_tracker/domain/dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dateKey and monthKey pad correctly', () {
    expect(dateKey(DateTime(2026, 3, 7)), '2026-03-07');
    expect(monthKey(DateTime(2026, 3, 7)), '2026-03');
    expect(monthKeyOfDate('2026-11-30'), '2026-11');
  });

  test('parseDateKey round trips', () {
    final d = parseDateKey('2024-02-29');
    expect(d, DateTime(2024, 2, 29));
    expect(dateKey(d), '2024-02-29');
  });

  test('isValidDateKey rejects bad dates', () {
    expect(isValidDateKey('2026-11-15'), isTrue);
    expect(isValidDateKey('2024-02-29'), isTrue);
    expect(isValidDateKey('2025-02-29'), isFalse);
    expect(isValidDateKey('2026-13-01'), isFalse);
    expect(isValidDateKey('2026-00-10'), isFalse);
    expect(isValidDateKey('2026-04-31'), isFalse);
    expect(isValidDateKey('2026-4-1'), isFalse);
    expect(isValidDateKey('nonsense'), isFalse);
    expect(() => parseDateKey('2026-02-30'), throwsFormatException);
  });

  test('addMonths crosses year boundaries both ways', () {
    expect(addMonths(DateTime(2026, 12, 1), 1), DateTime(2027, 1, 1));
    expect(addMonths(DateTime(2026, 1, 1), -1), DateTime(2025, 12, 1));
    expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
    expect(addMonths(DateTime(2026, 5, 1), 12), DateTime(2027, 5, 1));
  });

  test('isInMonth uses exact month boundaries', () {
    expect(isInMonth('2026-11-01', '2026-11'), isTrue);
    expect(isInMonth('2026-11-30', '2026-11'), isTrue);
    expect(isInMonth('2026-10-31', '2026-11'), isFalse);
    expect(isInMonth('2026-12-01', '2026-11'), isFalse);
    expect(isInMonth('2025-11-15', '2026-11'), isFalse);
  });

  test('labels', () {
    expect(monthLabel(DateTime(2026, 11, 1)), 'November 2026');
    expect(dayLabel(DateTime(2026, 11, 14)), 'Sat, 14 Nov 2026');
    expect(fileStamp(DateTime(2026, 1, 2, 3, 4)), '20260102-0304');
    expect(daysInMonth(2024, 2), 29);
    expect(daysInMonth(2026, 12), 31);
  });
}
