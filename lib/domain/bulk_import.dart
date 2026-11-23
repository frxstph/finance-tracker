import 'dates.dart';
import 'models.dart';
import 'receipt_match.dart';
import 'receipt_parser.dart';

/// One photo in "Choose photos" (several at once), before it becomes an
/// entry. Starts from what was read and holds the person's fixes.
class ImportDraft {
  ImportDraft({required this.photoPath, required this.guess, this.match})
      : amount = guess.amount,
        date = guess.date,
        note = guess.store ?? '',
        type = match?.type ?? EntryType.daily;

  final String photoPath;
  final ReceiptGuess guess;

  int? amount;
  DateTime? date;
  String note;
  EntryType type;

  /// The loan or bill this receipt pays, when recognised.
  final PaymentMatch? match;

  /// The loan or bill to link, when the type is that payment.
  int? get loanId => type == EntryType.loanPayment ? match?.loanId : null;
  int? get billId => type == EntryType.bill ? match?.billId : null;

  /// "Loan payment · GLoan", "Daily", "One-time".
  String get typeLabel {
    final m = match;
    if (m != null && type == m.type) return m.label;
    return type == EntryType.oneTime ? 'One-time' : 'Daily';
  }

  /// Ticked to be added.
  bool include = false;

  /// The person changed the amount or date by hand: their word beats any
  /// "check this" hint.
  bool fixed = false;

  String? get reference => guess.reference;
}

enum ImportStatus { ready, check, needsFix, duplicate }

/// Where a draft stands and why, in words for the screen.
class ImportReview {
  const ImportReview(this.status, this.reason);

  final ImportStatus status;
  final String reason;

  /// Ready and Check go in unless unticked; the others wait for a fix.
  bool get addByDefault =>
      status == ImportStatus.ready || status == ImportStatus.check;
}

/// Days after which a date is worth a second look.
const int oldAfterDays = 60;

/// Reviews each of [drafts] (in order) against the others and against
/// [existing] entries:
/// - Needs a fix: no amount, no date, or a date in the future
/// - Possible duplicate: same reference as an earlier photo, or same amount
///   and date as an earlier photo or as an existing money-out entry
/// - Check: amount or date was guessed, or the date is over 60 days old
/// - Ready: everything else
List<ImportReview> reviewDrafts(
  List<ImportDraft> drafts,
  List<Entry> existing,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <ImportReview>[];
  for (var i = 0; i < drafts.length; i++) {
    final d = drafts[i];
    final amount = d.amount;
    final date = d.date;
    if (amount == null || amount <= 0) {
      out.add(const ImportReview(ImportStatus.needsFix, 'Needs an amount'));
      continue;
    }
    if (date == null) {
      out.add(const ImportReview(ImportStatus.needsFix, 'Needs a date'));
      continue;
    }
    final day = DateTime(date.year, date.month, date.day);
    if (day.isAfter(today)) {
      out.add(const ImportReview(
          ImportStatus.needsFix, 'The date is in the future'));
      continue;
    }

    String? dup;
    for (var j = 0; j < i && dup == null; j++) {
      final o = drafts[j];
      if (d.reference != null && d.reference == o.reference) {
        dup = 'Same receipt as photo ${j + 1}';
      } else if (o.amount == amount &&
          o.date != null &&
          sameDay(o.date!, day)) {
        dup = 'Same amount and date as photo ${j + 1}';
      }
    }
    if (dup == null) {
      final key = dateKey(day);
      for (final e in existing) {
        if (!e.type.isMoneyIn && e.amount == amount && e.date == key) {
          dup = 'Same as an entry on ${shortDayLabel(day)}';
          break;
        }
      }
    }
    if (dup != null) {
      out.add(ImportReview(ImportStatus.duplicate, dup));
      continue;
    }

    if (!d.fixed) {
      if (d.guess.dateGuessed) {
        out.add(const ImportReview(
            ImportStatus.check, 'Check the date: it had no year'));
        continue;
      }
      if (d.guess.amountGuessed) {
        out.add(const ImportReview(
            ImportStatus.check, 'Check the amount: no total on the photo'));
        continue;
      }
      if (today.difference(day).inDays > oldAfterDays) {
        out.add(const ImportReview(
            ImportStatus.check, 'Check the date: over 2 months ago'));
        continue;
      }
    }
    out.add(const ImportReview(ImportStatus.ready, 'Ready'));
  }
  return out;
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const List<String> _weekdays = <String>[
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];
const List<String> _monthNames = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Wed 18 Nov".
String shortDayLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1]}';
