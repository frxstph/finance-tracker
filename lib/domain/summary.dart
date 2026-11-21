import 'bill_schedule.dart';
import 'dates.dart';
import 'models.dart';

/// One bill's status in a month: how many times it is due and paid.
class BillStatus {
  const BillStatus({required this.bill, required this.due, required this.paid});

  final Bill bill;

  /// Times due this month by its schedule.
  final int due;

  /// Payments recorded for it this month.
  final int paid;

  /// Payments still to make this month.
  int get left => due - paid > 0 ? due - paid : 0;

  int get leftAmount => left * bill.amount;
}

/// Totals for one month, following the rules in ARCHITECTURE.md §5.
class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.income,
    required this.loanReceived,
    required this.spent,
    required this.loanPaid,
    required this.stillOwed,
    required this.billStatus,
    required this.paidBillIds,
    required this.breakdown,
    required this.loanDues,
    required this.openingCash,
    required this.incomesLeft,
    required this.receivedIncomeIds,
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

  /// Bill id -> due and paid counts this month, for every active bill.
  final Map<int, BillStatus> billStatus;

  /// Active bills with payments still to make this month.
  List<BillStatus> get billsLeft => <BillStatus>[
        for (final st in billStatus.values)
          if (st.left > 0) st,
      ];

  /// The bills in [billsLeft].
  List<Bill> get unpaidBills =>
      <Bill>[for (final st in billsLeft) st.bill];

  /// Ids of bills with at least one bill entry in [month].
  final Set<int> paidBillIds;

  /// Total per entry type for [month]. Every type is present.
  final Map<EntryType, int> breakdown;

  /// Loan id -> amount still due on it this month. Only loans with
  /// something due are present.
  final Map<int, int> loanDues;

  /// Cash carried in from every earlier month: all money in minus all money
  /// out dated before this month.
  final int openingCash;

  /// Active monthly income sources not yet received this month.
  final List<IncomeSource> incomesLeft;

  /// Ids of income sources with an income entry this month.
  final Set<int> receivedIncomeIds;

  /// Money in minus money out during this month only.
  int get monthChange =>
      income + loanReceived + adjustments - spent - loanPaid;

  /// Adjustments this month: added to cash minus taken from cash. Neither
  /// income nor spending.
  int get adjustments =>
      (breakdown[EntryType.adjustIn] ?? 0) -
      (breakdown[EntryType.adjustOut] ?? 0);

  /// Cash on hand at the end of this month (or now, for the current month):
  /// what was carried in plus this month's change. May be negative.
  int get cash => openingCash + monthChange;

  int get incomeLeftAmount =>
      incomesLeft.fold<int>(0, (sum, i) => sum + i.amount);

  int get loanDueCount => loanDues.length;

  int get loanDueTotal =>
      loanDues.values.fold<int>(0, (sum, v) => sum + v);

  /// Unpaid bills plus loan payments due, for this month.
  int get leftToPayAmount => billsLeftAmount + loanDueTotal;

  int get billsLeftCount => billsLeft.length;

  int get billsLeftAmount =>
      billsLeft.fold<int>(0, (sum, st) => sum + st.leftAmount);

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

/// +amount for money in, −amount for money out.
int signedAmount(Entry e) => e.type.isMoneyIn ? e.amount : -e.amount;

/// All money in minus all money out dated before [month] ("yyyy-MM").
int cashBefore(Iterable<Entry> entries, String month) {
  var total = 0;
  for (final e in entries) {
    if (e.date.length < 7) continue;
    if (e.date.substring(0, 7).compareTo(month) < 0) total += signedAmount(e);
  }
  return total;
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
  List<IncomeSource> incomes = const <IncomeSource>[],
}) {
  final receivedIncomeIds = <int>{};
  final breakdown = <EntryType, int>{
    for (final t in EntryType.values) t: 0,
  };
  final paidBillIds = <int>{};
  final billPayments = <int, int>{};

  for (final e in entries) {
    if (!isInMonth(e.date, month)) continue;
    breakdown[e.type] = breakdown[e.type]! + e.amount;
    if (e.type == EntryType.bill && e.billId != null) {
      paidBillIds.add(e.billId!);
      billPayments[e.billId!] = (billPayments[e.billId!] ?? 0) + 1;
    }
    if (e.type == EntryType.income && e.incomeId != null) {
      receivedIncomeIds.add(e.incomeId!);
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

  final billStatus = <int, BillStatus>{
    for (final b in bills)
      if (b.active && b.id != null)
        b.id!: BillStatus(
          bill: b,
          due: billDueCount(b, month),
          paid: billPayments[b.id] ?? 0,
        ),
  };

  return MonthSummary(
    month: month,
    income: income,
    loanReceived: loanReceived,
    spent: spent,
    loanPaid: loanPaid,
    stillOwed: stillOwed,
    billStatus: billStatus,
    paidBillIds: paidBillIds,
    breakdown: breakdown,
    loanDues: loanDues,
    openingCash: cashBefore(entries, month),
    incomesLeft: <IncomeSource>[
      for (final i in incomes)
        if (i.active && !(i.id != null && receivedIncomeIds.contains(i.id)))
          i,
    ],
    receivedIncomeIds: receivedIncomeIds,
  );
}

/// One month of the "if everything is paid" forecast.
class ForecastMonth {
  const ForecastMonth({
    required this.month,
    required this.startCash,
    required this.recorded,
    required this.incomeToCome,
    required this.billsToPay,
    required this.loanPayments,
    required this.owedAfter,
    this.loanDues = const <int, int>{},
  });

  /// "yyyy-MM"
  final String month;

  /// Cash at the start of the month (actual for the first forecast month,
  /// projected after that).
  final int startCash;

  /// Money in minus money out already recorded in this month.
  final int recorded;

  /// Monthly income expected but not yet received this month.
  final int incomeToCome;

  /// Active bills not yet paid this month.
  final int billsToPay;

  /// Loan payments the plans expect this month, catch-up included.
  final int loanPayments;

  /// Loans still owed after this month's planned payments.
  final int owedAfter;

  /// Loan id -> payment the forecast expects this month (only loans with
  /// something due).
  final Map<int, int> loanDues;

  /// Projected cash at the end of the month.
  int get endCash =>
      startCash + recorded + incomeToCome - billsToPay - loanPayments;

  int get netPosition => endCash - owedAfter;
}

/// Forecast from [fromMonth] through [toMonth] ("yyyy-MM"), assuming every
/// expected monthly income arrives, every active bill is paid and every loan
/// payment its plan expects is made. Entries already recorded (in any month)
/// count as they are. Returns one item per month, oldest first; empty when
/// [toMonth] is before [fromMonth].
List<ForecastMonth> forecastMonths({
  required String fromMonth,
  required String toMonth,
  required List<Entry> entries,
  required List<Bill> bills,
  required List<Loan> loans,
  List<IncomeSource> incomes = const <IncomeSource>[],
}) {
  final result = <ForecastMonth>[];
  final count = monthsBetween(fromMonth, toMonth);
  if (count < 0) return result;

  final totals = loanPaymentTotals(entries);
  final planned = <int, int>{};
  var cash = cashBefore(entries, fromMonth);
  final start = parseMonthKey(fromMonth);

  for (var i = 0; i <= count; i++) {
    final month = monthKey(addMonths(start, i));
    var recorded = 0;
    final billPayments = <int, int>{};
    final receivedIncomes = <int>{};
    for (final e in entries) {
      if (!isInMonth(e.date, month)) continue;
      recorded += signedAmount(e);
      if (e.type == EntryType.bill && e.billId != null) {
        billPayments[e.billId!] = (billPayments[e.billId!] ?? 0) + 1;
      }
      if (e.type == EntryType.income && e.incomeId != null) {
        receivedIncomes.add(e.incomeId!);
      }
    }

    var incomeToCome = 0;
    for (final s in incomes) {
      if (s.active && !(s.id != null && receivedIncomes.contains(s.id))) {
        incomeToCome += s.amount;
      }
    }
    var billsToPay = 0;
    for (final b in bills) {
      if (!b.active) continue;
      final left = billDueCount(b, month) - (billPayments[b.id] ?? 0);
      if (left > 0) billsToPay += left * b.amount;
    }

    var loanPayments = 0;
    var owedAfter = 0;
    final loanDues = <int, int>{};
    for (final loan in loans) {
      final id = loan.id;
      if (id == null) continue;
      final extra = planned[id] ?? 0;
      var balance = loan.principal - (totals[id] ?? 0) - extra;
      if (balance < 0) balance = 0;
      final elapsed = monthsBetween(loan.startMonth, month);
      var due = 0;
      if (elapsed >= 0 && balance > 0) {
        final n = loan.paymentCount;
        final k = elapsed + 1 < n ? elapsed + 1 : n;
        final perMonth = loan.installment * k;
        final expected = perMonth < loan.principal ? perMonth : loan.principal;
        due = expected - _paidThrough(entries, id, month) - extra;
        if (due < 0) due = 0;
        if (due > balance) due = balance;
      }
      planned[id] = extra + due;
      loanPayments += due;
      if (due > 0) loanDues[id] = due;
      owedAfter += balance - due;
    }

    final item = ForecastMonth(
      month: month,
      startCash: cash,
      recorded: recorded,
      incomeToCome: incomeToCome,
      billsToPay: billsToPay,
      loanPayments: loanPayments,
      owedAfter: owedAfter,
      loanDues: loanDues,
    );
    result.add(item);
    cash = item.endCash;
  }
  return result;
}
