import 'money.dart';

/// A bill or loan payment expected on [date].
class DueItem {
  const DueItem({required this.date, required this.label, required this.amount});

  final DateTime date;
  final String label;

  /// Positive centavos.
  final int amount;
}

/// One phone notification to show at [at].
class Reminder {
  const Reminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  /// Stable per day and kind: yyyymmdd × 10 + 1 (the evening before) or
  /// + 2 (the morning of).
  final int id;
  final DateTime at;
  final String title;
  final String body;
}

/// "Meralco ₱2,350, Joint loan ₱4,462 and 2 more (₱9,100 in all)".
String describeDues(List<DueItem> items) {
  final shown = items.take(3).map((i) => '${i.label} ${formatPeso(i.amount)}');
  var text = shown.join(', ');
  if (items.length > 3) text += ' and ${items.length - 3} more';
  if (items.length > 1) {
    final total = items.fold<int>(0, (sum, i) => sum + i.amount);
    text += ' (${formatPeso(total)} in all)';
  }
  return text;
}

/// Reminders for [dues]: one the evening before ([eveningHour]) and one
/// the morning of ([morningHour]) each day something is due, items on the
/// same day grouped into one notification. Only times after [now] and
/// within [days] days are kept.
List<Reminder> buildReminders(
  List<DueItem> dues,
  DateTime now, {
  int eveningHour = 18,
  int morningHour = 8,
  int days = 35,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final last = today.add(Duration(days: days));
  final byDay = <DateTime, List<DueItem>>{};
  for (final d in dues) {
    final day = DateTime(d.date.year, d.date.month, d.date.day);
    if (day.isBefore(today) || day.isAfter(last) || d.amount <= 0) continue;
    byDay.putIfAbsent(day, () => <DueItem>[]).add(d);
  }
  final out = <Reminder>[];
  final keys = byDay.keys.toList()..sort();
  for (final day in keys) {
    final items = byDay[day]!..sort((a, b) => b.amount.compareTo(a.amount));
    final base = (day.year * 10000 + day.month * 100 + day.day) * 10;
    final body = describeDues(items);
    final evening = DateTime(day.year, day.month, day.day - 1, eveningHour);
    if (evening.isAfter(now)) {
      out.add(Reminder(
        id: base + 1,
        at: evening,
        title: 'Due tomorrow',
        body: body,
      ));
    }
    final morning = DateTime(day.year, day.month, day.day, morningHour);
    if (morning.isAfter(now)) {
      out.add(Reminder(
        id: base + 2,
        at: morning,
        title: 'Due today',
        body: body,
      ));
    }
  }
  return out;
}
