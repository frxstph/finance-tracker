import 'package:finance_tracker/domain/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 22, 12, 0);

  test('evening before and morning of, future only', () {
    final r = buildReminders(<DueItem>[
      DueItem(date: DateTime(2026, 11, 25), label: 'Meralco', amount: 235000),
    ], now);
    expect(r.length, 2);
    expect(r[0].title, 'Due tomorrow');
    expect(r[0].at, DateTime(2026, 11, 24, 18));
    expect(r[0].id, 202611251);
    expect(r[0].body, 'Meralco ₱2,350');
    expect(r[1].title, 'Due today');
    expect(r[1].at, DateTime(2026, 11, 25, 8));
    expect(r[1].id, 202611252);
  });

  test('today after 8 am: nothing left for today', () {
    final r = buildReminders(<DueItem>[
      DueItem(date: DateTime(2026, 11, 22), label: 'Water', amount: 50000),
    ], now);
    expect(r, isEmpty);
  });

  test('tomorrow: evening reminder today still comes', () {
    final r = buildReminders(<DueItem>[
      DueItem(date: DateTime(2026, 11, 23), label: 'Water', amount: 50000),
    ], now);
    expect(r.map((x) => x.at), <DateTime>[
      DateTime(2026, 11, 22, 18),
      DateTime(2026, 11, 23, 8),
    ]);
  });

  test('same day items are grouped, biggest first, with a total', () {
    final r = buildReminders(<DueItem>[
      DueItem(date: DateTime(2026, 11, 30), label: 'Water', amount: 50000),
      DueItem(date: DateTime(2026, 11, 30), label: 'Joint loan', amount: 446200),
    ], now);
    expect(r.length, 2);
    expect(r.first.body, 'Joint loan ₱4,462, Water ₱500 (₱4,962 in all)');
  });

  test('more than three items are summarised', () {
    final items = <DueItem>[
      for (var i = 1; i <= 5; i++)
        DueItem(date: DateTime(2026, 12, 1), label: 'Bill $i', amount: i * 100),
    ];
    expect(describeDues(items), endsWith('and 2 more (₱15 in all)'));
  });

  test('skips past days and days beyond the window', () {
    final r = buildReminders(<DueItem>[
      DueItem(date: DateTime(2026, 11, 20), label: 'Old', amount: 100),
      DueItem(date: DateTime(2027, 2, 1), label: 'Far', amount: 100),
    ], now);
    expect(r, isEmpty);
  });
}
