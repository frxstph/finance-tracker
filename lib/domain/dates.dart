/// Date helpers. Dates are local calendar dates stored as "yyyy-MM-dd";
/// months are keyed "yyyy-MM". No time zone math.
library;

const List<String> _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _weekdayShort = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _four(int n) => n.toString().padLeft(4, '0');

/// "yyyy-MM-dd" for the calendar date of [d].
String dateKey(DateTime d) => '${_four(d.year)}-${_two(d.month)}-${_two(d.day)}';

/// "yyyy-MM" for the month containing [d].
String monthKey(DateTime d) => '${_four(d.year)}-${_two(d.month)}';

/// Today's date key.
String todayKey() => dateKey(DateTime.now());

final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// True when [s] is a real calendar date in "yyyy-MM-dd" form.
bool isValidDateKey(String s) {
  final m = _datePattern.firstMatch(s);
  if (m == null) return false;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1) return false;
  return d <= daysInMonth(y, mo);
}

/// Parses "yyyy-MM-dd" into a local midnight DateTime.
/// Throws [FormatException] when invalid.
DateTime parseDateKey(String s) {
  if (!isValidDateKey(s)) {
    throw FormatException('Invalid date: $s');
  }
  return DateTime(
    int.parse(s.substring(0, 4)),
    int.parse(s.substring(5, 7)),
    int.parse(s.substring(8, 10)),
  );
}

/// The "yyyy-MM" month key of a "yyyy-MM-dd" date key.
String monthKeyOfDate(String date) => date.substring(0, 7);

/// True when the date key [date] falls in month [month] ("yyyy-MM").
bool isInMonth(String date, String month) =>
    date.length == 10 && date.startsWith('$month-');

final RegExp _monthPattern = RegExp(r'^(\d{4})-(\d{2})$');

/// True when [s] is a real month in "yyyy-MM" form.
bool isValidMonthKey(String s) {
  final m = _monthPattern.firstMatch(s);
  if (m == null) return false;
  final mo = int.parse(m.group(2)!);
  return mo >= 1 && mo <= 12;
}

/// Months since year 0 for a "yyyy-MM" key, so two keys can be subtracted.
int monthIndex(String month) =>
    int.parse(month.substring(0, 4)) * 12 + int.parse(month.substring(5, 7)) - 1;

/// Number of months from [from] to [to] ("yyyy-MM"); negative when [to] is
/// earlier.
int monthsBetween(String from, String to) => monthIndex(to) - monthIndex(from);

/// First day of the month for a "yyyy-MM" key.
DateTime parseMonthKey(String month) =>
    DateTime(int.parse(month.substring(0, 4)), int.parse(month.substring(5, 7)), 1);

/// "Nov 2026" for a "yyyy-MM" key.
String shortMonthLabel(String month) {
  final d = parseMonthKey(month);
  return '${_monthNames[d.month - 1].substring(0, 3)} ${d.year}';
}

/// [day] of [month]'s month, moved to the last day when the month is
/// shorter (the 31st of February is the 28th or 29th).
DateTime dayInMonth(DateTime month, int day) {
  final last = DateTime(month.year, month.month + 1, 0).day;
  final d = day < 1 ? 1 : (day > last ? last : day);
  return DateTime(month.year, month.month, d);
}

/// First day of the month containing [d].
DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

/// First day of the month [months] away from the month containing [d].
DateTime addMonths(DateTime d, int months) =>
    DateTime(d.year, d.month + months, 1);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// "November 2026"
String monthLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

/// "Sat, 14 Nov 2026"
String dayLabel(DateTime d) =>
    '${_weekdayShort[d.weekday - 1]}, ${d.day} '
    '${_monthNames[d.month - 1].substring(0, 3)} ${d.year}';

/// "yyyyMMdd-HHmm" for file names.
String fileStamp(DateTime d) =>
    '${_four(d.year)}${_two(d.month)}${_two(d.day)}-${_two(d.hour)}${_two(d.minute)}';
