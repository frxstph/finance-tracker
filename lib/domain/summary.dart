import 'dates.dart';
import 'models.dart';

/// Totals for one month, following the rules in ARCHITECTURE.md §5.
class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.income,
    required this.spent,
    required this.loanPaid,
    required this.stillOwed,
    required this.unpaidBills,
    required this.paidBillIds,
    required this.breakdown,
  });

  /// "yyyy-MM"
  final String month;
  final int income;

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

  /// Each month starts at ₱0; no carry-over. May be negative.
  int get cash => income - spent - loanPaid;

  int get billsLeftCount => unpaidBills.length;

  int get billsLeftAmount =>
      unpaidBills.fold<int>(0, (sum, b) => sum + b.amount);

  int get netPosition => cash - stillOwed;

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
  final spent = breakdown[EntryType.bill]! +
      breakdown[EntryType.oneTime]! +
      breakdown[EntryType.daily]!;
  final loanPaid = breakdown[EntryType.loanPayment]!;

  final totals = loanPaymentTotals(entries);
  var stillOwed = 0;
  for (final loan in loans) {
    stillOwed += loanBalance(loan, totals);
  }

  final unpaid = <Bill>[
    for (final b in bills)
      if (b.active && !(b.id != null && paidBillIds.contains(b.id))) b,
  ];

  return MonthSummary(
    month: month,
    income: income,
    spent: spent,
    loanPaid: loanPaid,
    stillOwed: stillOwed,
    unpaidBills: unpaid,
    paidBillIds: paidBillIds,
    breakdown: breakdown,
  );
}
