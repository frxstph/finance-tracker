import 'dates.dart';
import 'models.dart';

/// Totals for one month, following the rules in ARCHITECTURE.md §5.
class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.income,
    required this.loanReceived,
    required this.spent,
    required this.loanPaid,
    required this.stillOwed,
    required this.unpaidBills,
    required this.paidBillIds,
    required this.breakdown,
    required this.loanDues,
  });

  /// "yyyy-MM"
  final String month;
  final int income;

  /// Money received from new loans this month. Raises cash; not income.
  final int loanReceived;

  /// Bills + one-time + daily. Never includes loan payments.
  final int spent;
  final int loanPaid;

  /// Across all loans and all time, each clamped at 0.
  final int stillOwed;

  /// Active bills with no bill entry in [month].
  final List<Bill> unpaidBills;

  /// Ids of bills with at least one bill entry in [month].
  final Set<int> paidBillIds;

  /// Total per entry type for [month]. Every type is present.
  final Map<EntryType, int> breakdown;

  /// Loan id -> amount still due on it this month. Only loans with
  /// something due are present.
  final Map<int, int> loanDues;

  /// Each month starts at ₱0; no carry-over. May be negative.
  int get cash => income + loanReceived - spent - loanPaid;

  int get loanDueCount => loanDues.length;

  int get loanDueTotal =>
      loanDues.values.fold<int>(0, (sum, v) => sum + v);

  /// Unpaid bills plus loan payments due, for this month.
  int get leftToPayAmount => billsLeftAmount + loanDueTotal;

  int get billsLeftCount => unpaidBills.length;

  int get billsLeftAmount =>
      unpaidBills.fold<int>(0, (sum, b) => sum + b.amount);

  /// Cash minus everything owed on loans minus this month's unpaid bills.
  /// Loan payments due are not subtracted again: they are part of
  /// [stillOwed].
  int get netPosition => cash - stillOwed - billsLeftAmount;

  static MonthSummary empty(String month) => computeSummary(
        month: month,
        entries: const <Entry>[],
        bills: const <Bill>[],
        loans: const <Loan>[],
      );
}

/// Sum of all loan_payment entries per loan id, across all time.
Map<int, int> loanPaymentTotals(Iterable<Entry> entries) {
  final totals = <int, int>{};
  for (final e in entries) {
    if (e.type != EntryType.loanPayment) continue;
    final id = e.loanId;
    if (id == null) continue;
    totals[id] = (totals[id] ?? 0) + e.amount;
  }
  return totals;
}

/// Remaining balance of [loan], never below 0.
int loanBalance(Loan loan, Map<int, int> paymentTotals) {
  final paid = loan.id == null ? 0 : (paymentTotals[loan.id] ?? 0);
  final balance = loan.principal - paid;
  return balance < 0 ? 0 : balance;
}

/// Payments made on [loanId] dated in or before [month] ("yyyy-MM").
int _paidThrough(Iterable<Entry> entries, int loanId, String month) {
  var total = 0;
  for (final e in entries) {
    if (e.type != EntryType.loanPayment || e.loanId != loanId) continue;
    if (e.date.length < 7) continue;
    if (e.date.substring(0, 7).compareTo(month) <= 0) total += e.amount;
  }
  return total;
}

/// What is still due on [loan] in [month] ("yyyy-MM").
///
/// The plan expects one installment per month from the start month (a full
/// plan is one installment of everything). The amount due is what the plan
/// expects by the end of [month], minus every payment dated up to then, so
/// a missed month rolls into the next one. Never more than the loan's
/// remaining balance, never below 0. Nothing is due before the start month.
int loanDueInMonth(Loan loan, String month, Iterable<Entry> entries,
    Map<int, int> paymentTotals) {
  final id = loan.id;
  if (id == null) return 0;
  final elapsed = monthsBetween(loan.startMonth, month);
  if (elapsed < 0) return 0;
  final n = loan.paymentCount;
  final count = elapsed + 1 < n ? elapsed + 1 : n;
  final perMonth = loan.installment * count;
  final expected = perMonth < loan.principal ? perMonth : loan.principal;
  final due = expected - _paidThrough(entries, id, month);
  final balance = loanBalance(loan, paymentTotals);
  if (due <= 0 || balance <= 0) return 0;
  return due < balance ? due : balance;
}

/// What to pay on [loan] now: what is due this month, else the next
/// installment (paying ahead), never more than the balance.
int suggestedLoanPayment(Loan loan, int due, int balance) {
  if (balance <= 0) return 0;
  if (due > 0) return due < balance ? due : balance;
  final next = loan.installment;
  return next < balance ? next : balance;
}

/// How many of the plan's payments the money paid so far covers.
int paymentsCovered(Loan loan, int paid) {
  final per = loan.installment;
  if (per <= 0) return loan.paymentCount;
  final n = paid ~/ per;
  return n < loan.paymentCount ? n : loan.paymentCount;
}

/// Computes the summary for [month] ("yyyy-MM").
///
/// [entries] may contain entries from any month; month totals only use those
/// dated in [month], while "still owed" uses loan payments from all time.
MonthSummary computeSummary({
  required String month,
  required List<Entry> entries,
  required List<Bill> bills,
  required List<Loan> loans,
}) {
  final breakdown = <EntryType, int>{
    for (final t in EntryType.values) t: 0,
  };
  final paidBillIds = <int>{};

  for (final e in entries) {
    if (!isInMonth(e.date, month)) continue;
    breakdown[e.type] = breakdown[e.type]! + e.amount;
    if (e.type == EntryType.bill && e.billId != null) {
      paidBillIds.add(e.billId!);
    }
  }

  final income = breakdown[EntryType.income]!;
  final loanReceived = breakdown[EntryType.loanReceived]!;
  final spent = breakdown[EntryType.bill]! +
      breakdown[EntryType.oneTime]! +
      breakdown[EntryType.daily]!;
  final loanPaid = breakdown[EntryType.loanPayment]!;

  final totals = loanPaymentTotals(entries);
  var stillOwed = 0;
  for (final loan in loans) {
    stillOwed += loanBalance(loan, totals);
  }

  final loanDues = <int, int>{};
  for (final loan in loans) {
    final due = loanDueInMonth(loan, month, entries, totals);
    if (due > 0 && loan.id != null) loanDues[loan.id!] = due;
  }

  final unpaid = <Bill>[
    for (final b in bills)
      if (b.active && !(b.id != null && paidBillIds.contains(b.id))) b,
  ];

  return MonthSummary(
    month: month,
    income: income,
    loanReceived: loanReceived,
    spent: spent,
    loanPaid: loanPaid,
    stillOwed: stillOwed,
    unpaidBills: unpaid,
    paidBillIds: paidBillIds,
    breakdown: breakdown,
    loanDues: loanDues,
  );
}
