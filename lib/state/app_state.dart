import 'dart:io';

import 'package:flutter/widgets.dart';

import '../data/backup.dart';
import '../data/photos.dart';
import '../data/repository.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/calc.dart';
import '../domain/summary.dart';
import '../domain/weeks.dart';

/// Thrown for actions the rules forbid (e.g. deleting a bill with entries).
class ActionNotAllowed implements Exception {
  const ActionNotAllowed(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What to do with an entry's photo when saving it.
enum PhotoChange { keep, replace, remove }

/// The single app-wide state object. Holds the selected month, every loaded
/// row and the computed summary. All writes go through here so totals stay
/// fresh.
class AppState extends ChangeNotifier {
  AppState({
    required Repository repository,
    required PhotoStore photos,
    required BackupService backup,
  })  : _repo = repository,
        _photos = photos,
        _backup = backup;

  final Repository _repo;
  final PhotoStore _photos;
  final BackupService _backup;

  PhotoStore get photos => _photos;

  DateTime _month = startOfMonth(DateTime.now());
  List<Bill> _bills = const <Bill>[];
  List<Loan> _loans = const <Loan>[];
  List<IncomeSource> _incomes = const <IncomeSource>[];
  List<PayAccount> _accounts = const <PayAccount>[];
  List<Entry> _entries = const <Entry>[];
  MonthSummary _summary = MonthSummary.empty(monthKey(DateTime.now()));
  Map<int, int> _loanTotals = const <int, int>{};
  bool _loaded = false;

  bool get loaded => _loaded;
  DateTime get month => _month;
  String get monthKeyValue => monthKey(_month);
  List<Bill> get bills => _bills;
  List<Bill> get activeBills => _bills.where((b) => b.active).toList();
  List<Bill> get archivedBills => _bills.where((b) => !b.active).toList();
  List<Loan> get loans => _loans;
  List<IncomeSource> get incomes => _incomes;
  List<PayAccount> get accounts => _accounts;
  List<IncomeSource> get activeIncomes =>
      _incomes.where((i) => i.active).toList();
  List<IncomeSource> get archivedIncomes =>
      _incomes.where((i) => !i.active).toList();

  /// [f] split into the fixed blocks 1–7, 8–14, 15–21 and 22–end.
  List<WeekBlock> weeksFor(ForecastMonth f) => weekBlocks(
        forecast: f,
        entries: _entries,
        bills: _bills,
        loans: _loans,
        incomes: _incomes,
        today: DateTime.now(),
      );

  /// "Can I afford this?" for [amount] centavos on [date].
  AffordResult affordCheck(int amount, DateTime date) => canAfford(
        amount: amount,
        date: date,
        today: DateTime.now(),
        entries: _entries,
        bills: _bills,
        loans: _loans,
        incomes: _incomes,
      );

  /// What can be spent each day until the next payday.
  SafeToSpend get safeToSpendNow => safeToSpend(
        today: DateTime.now(),
        entries: _entries,
        bills: _bills,
        loans: _loans,
        incomes: _incomes,
      );

  /// Cash right now: everything recorded up to and including today.
  int get cashNow {
    final today = todayKey();
    var total = 0;
    for (final e in _entries) {
      if (e.date.compareTo(today) <= 0) total += signedAmount(e);
    }
    return total;
  }

  /// Records the difference between [actual] cash and [cashNow] as an
  /// adjustment dated today, so the app matches the wallet. Returns the
  /// signed difference; 0 means it already matched and nothing was added.
  Future<int> countCash(int actual) async {
    final diff = actual - cashNow;
    if (diff == 0) return 0;
    await saveEntry(Entry(
      type: diff > 0 ? EntryType.adjustIn : EntryType.adjustOut,
      amount: diff.abs(),
      note: 'Cash count',
      date: todayKey(),
      createdAt: DateTime.now().toIso8601String(),
    ));
    return diff;
  }

  /// The month that holds today.
  String get currentMonthKey => monthKey(DateTime.now());

  /// "If everything is paid" forecast for the selected month, chained from
  /// the current month. Null for months before the current one.
  ForecastMonth? get forecast {
    final months = forecastMonths(
      fromMonth: currentMonthKey,
      toMonth: monthKeyValue,
      entries: _entries,
      bills: _bills,
      loans: _loans,
      incomes: _incomes,
    );
    return months.isEmpty ? null : months.last;
  }
  List<Entry> get allEntries => _entries;
  MonthSummary get summary => _summary;

  /// Entries in the selected month, newest first.
  List<Entry> get monthEntries {
    final key = monthKeyValue;
    return _entries.where((e) => isInMonth(e.date, key)).toList();
  }

  int loanPaid(Loan loan) => loan.id == null ? 0 : (_loanTotals[loan.id] ?? 0);
  int loanBalanceOf(Loan loan) => loanBalance(loan, _loanTotals);

  /// Still due on [loan] in the selected month.
  int loanDueOf(Loan loan) =>
      loan.id == null ? 0 : (_summary.loanDues[loan.id] ?? 0);

  /// Amount to put in a payment for [loan]: due this month, else the next
  /// installment.
  int loanPaymentSuggestion(Loan loan) =>
      suggestedLoanPayment(loan, loanDueOf(loan), loanBalanceOf(loan));

  /// Due and paid counts for [bill] in the selected month, or null when it
  /// is archived.
  BillStatus? billStatusOf(Bill bill) =>
      bill.id == null ? null : _summary.billStatus[bill.id];

  Bill? billById(int? id) {
    if (id == null) return null;
    for (final b in _bills) {
      if (b.id == id) return b;
    }
    return null;
  }

  IncomeSource? incomeById(int? id) {
    if (id == null) return null;
    for (final i in _incomes) {
      if (i.id == id) return i;
    }
    return null;
  }

  Loan? loanById(int? id) {
    if (id == null) return null;
    for (final l in _loans) {
      if (l.id == id) return l;
    }
    return null;
  }

  Entry? entryById(int id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Display title for an entry: its note, else the bill/loan name, else the
  /// type label.
  String titleFor(Entry e) {
    if (e.note.trim().isNotEmpty) return e.note.trim();
    if (e.type == EntryType.bill) {
      final b = billById(e.billId);
      if (b != null) return b.name;
    }
    if (e.type.needsLoan) {
      final l = loanById(e.loanId);
      if (l != null) return l.name;
    }
    if (e.type == EntryType.income) {
      final i = incomeById(e.incomeId);
      if (i != null) return i.name;
    }
    return e.type.label;
  }

  File? photoFile(Entry e) {
    final name = e.photo;
    if (name == null || !isSafePhotoName(name)) return null;
    return _photos.fileFor(name);
  }

  // Loading

  Future<void> load() async {
    _bills = await _repo.bills();
    _loans = await _repo.loans();
    _incomes = await _repo.incomes();
    _accounts = await _repo.accounts();
    _entries = await _repo.entries();
    _loaded = true;
    _recompute();
  }

  void _recompute() {
    _loanTotals = loanPaymentTotals(_entries);
    _summary = computeSummary(
      month: monthKeyValue,
      entries: _entries,
      bills: _bills,
      loans: _loans,
      incomes: _incomes,
    );
    notifyListeners();
  }

  // Month

  void showPreviousMonth() => _setMonth(addMonths(_month, -1));
  void showNextMonth() => _setMonth(addMonths(_month, 1));
  void showThisMonth() => _setMonth(startOfMonth(DateTime.now()));

  void _setMonth(DateTime m) {
    _month = startOfMonth(m);
    _recompute();
  }

  // Entries

  /// Inserts or updates [entry]. When [photoChange] is replace, the image at
  /// [newPhotoPath] is copied into receipts first.
  Future<void> saveEntry(
    Entry entry, {
    PhotoChange photoChange = PhotoChange.keep,
    String? newPhotoPath,
  }) async {
    final previous = entry.id == null ? null : entryById(entry.id!);
    String? photo = previous?.photo;
    String? imported;
    if (photoChange == PhotoChange.replace && newPhotoPath != null) {
      imported = await _photos.importFile(newPhotoPath);
      photo = imported;
    } else if (photoChange == PhotoChange.remove) {
      photo = null;
    }

    final toSave = Entry(
      id: entry.id,
      type: entry.type,
      amount: entry.amount,
      note: entry.note.trim(),
      date: entry.date,
      billId: entry.type == EntryType.bill ? entry.billId : null,
      loanId: entry.type.needsLoan ? entry.loanId : null,
      incomeId: entry.type == EntryType.income ? entry.incomeId : null,
      photo: photo,
      createdAt: entry.createdAt,
    );

    try {
      if (toSave.id == null) {
        await _repo.insertEntry(toSave);
      } else {
        await _repo.updateEntry(toSave);
      }
    } catch (_) {
      await _photos.delete(imported);
      rethrow;
    }

    final oldPhoto = previous?.photo;
    if (oldPhoto != null && oldPhoto != photo) {
      await _photos.delete(oldPhoto);
    }
    await _reloadEntries();
  }

  Future<void> deleteEntry(Entry entry) async {
    final id = entry.id;
    if (id == null) return;
    await _repo.deleteEntry(id);
    await _photos.delete(entry.photo);
    await _reloadEntries();
  }

  Future<void> _reloadEntries() async {
    _entries = await _repo.entries();
    _recompute();
  }

  // Bills

  Future<void> saveBill(Bill bill) async {
    if (bill.id == null) {
      await _repo.insertBill(bill);
    } else {
      await _repo.updateBill(bill);
    }
    await _reloadBills();
  }

  Future<void> setBillActive(Bill bill, bool active) async {
    await _repo.updateBill(bill.copyWith(active: active));
    await _reloadBills();
  }

  /// Deletes a bill that has no entries. Throws [ActionNotAllowed] otherwise.
  Future<void> deleteBill(Bill bill) async {
    final id = bill.id;
    if (id == null) return;
    if (await _repo.billHasEntries(id)) {
      throw const ActionNotAllowed(
          'This bill has payments, so it can only be archived.');
    }
    await _repo.deleteBill(id);
    await _reloadBills();
  }

  Future<void> _reloadBills() async {
    _bills = await _repo.bills();
    _recompute();
  }

  // Payment accounts (QR codes)

  /// Inserts or updates [account]. [photoChange] works as in [saveEntry].
  Future<void> saveAccount(
    PayAccount account, {
    PhotoChange photoChange = PhotoChange.keep,
    String? newPhotoPath,
  }) async {
    PayAccount? previous;
    for (final a in _accounts) {
      if (a.id != null && a.id == account.id) previous = a;
    }
    String? photo = previous?.photo;
    String? imported;
    if (photoChange == PhotoChange.replace && newPhotoPath != null) {
      imported = await _photos.importFile(newPhotoPath);
      photo = imported;
    } else if (photoChange == PhotoChange.remove) {
      photo = null;
    }
    final toSave = account.copyWith(photo: photo, clearPhoto: photo == null);
    try {
      if (toSave.id == null) {
        await _repo.insertAccount(toSave);
      } else {
        await _repo.updateAccount(toSave);
      }
    } catch (_) {
      await _photos.delete(imported);
      rethrow;
    }
    final oldPhoto = previous?.photo;
    if (oldPhoto != null && oldPhoto != photo) {
      await _photos.delete(oldPhoto);
    }
    _accounts = await _repo.accounts();
    notifyListeners();
  }

  Future<void> deleteAccount(PayAccount account) async {
    final id = account.id;
    if (id == null) return;
    await _repo.deleteAccount(id);
    await _photos.delete(account.photo);
    _accounts = await _repo.accounts();
    notifyListeners();
  }

  File? accountPhotoFile(PayAccount account) {
    final name = account.photo;
    if (name == null || !isSafePhotoName(name)) return null;
    return _photos.fileFor(name);
  }

  // Monthly income sources

  Future<void> saveIncome(IncomeSource source) async {
    if (source.id == null) {
      await _repo.insertIncome(source);
    } else {
      await _repo.updateIncome(source);
    }
    await _reloadIncomes();
  }

  Future<void> setIncomeActive(IncomeSource source, bool active) async {
    await _repo.updateIncome(source.copyWith(active: active));
    await _reloadIncomes();
  }

  /// Deletes an income source that has never been received. Throws
  /// [ActionNotAllowed] otherwise.
  Future<void> deleteIncome(IncomeSource source) async {
    final id = source.id;
    if (id == null) return;
    if (await _repo.incomeHasEntries(id)) {
      throw const ActionNotAllowed(
          'This income has been received before, so it can only be archived.');
    }
    await _repo.deleteIncome(id);
    await _reloadIncomes();
  }

  Future<void> _reloadIncomes() async {
    _incomes = await _repo.incomes();
    _recompute();
  }

  // Loans

  /// Inserts or updates [loan]. For a new loan with [addToCash], a "loan
  /// received" entry for the full amount is added today, so the money shows
  /// in cash on hand. [photoChange] works as in [saveEntry].
  Future<void> saveLoan(
    Loan loan, {
    bool addToCash = false,
    PhotoChange photoChange = PhotoChange.keep,
    String? newPhotoPath,
  }) async {
    final previous = loan.id == null ? null : loanById(loan.id);
    String? photo = previous?.photo;
    String? imported;
    if (photoChange == PhotoChange.replace && newPhotoPath != null) {
      imported = await _photos.importFile(newPhotoPath);
      photo = imported;
    } else if (photoChange == PhotoChange.remove) {
      photo = null;
    }
    final toSave = loan.copyWith(photo: photo, clearPhoto: photo == null);

    Entry? received;
    try {
      if (toSave.id == null) {
        received = addToCash
            ? Entry(
                type: EntryType.loanReceived,
                amount: toSave.principal,
                date: todayKey(),
                createdAt: DateTime.now().toIso8601String(),
              )
            : null;
        await _repo.insertLoanWithReceipt(toSave, received: received);
      } else {
        await _repo.updateLoan(toSave);
      }
    } catch (_) {
      await _photos.delete(imported);
      rethrow;
    }

    final oldPhoto = previous?.photo;
    if (oldPhoto != null && oldPhoto != photo) {
      await _photos.delete(oldPhoto);
    }
    if (received != null) _entries = await _repo.entries();
    await _reloadLoans();
  }

  File? loanPhotoFile(Loan loan) {
    final name = loan.photo;
    if (name == null || !isSafePhotoName(name)) return null;
    return _photos.fileFor(name);
  }

  /// Deletes a loan that has no payments, along with the money-received
  /// entry made when it was added. Throws [ActionNotAllowed] otherwise.
  Future<void> deleteLoan(Loan loan) async {
    final id = loan.id;
    if (id == null) return;
    if (await _repo.loanHasPayments(id)) {
      throw const ActionNotAllowed(
          'This loan has payments, so it can’t be deleted.');
    }
    final photos = <String>[
      for (final e in _entries)
        if (e.loanId == id && e.photo != null) e.photo!,
      if (loan.photo != null) loan.photo!,
    ];
    await _repo.deleteLoanAndReceipts(id);
    for (final name in photos) {
      await _photos.delete(name);
    }
    _entries = await _repo.entries();
    await _reloadLoans();
  }

  Future<void> _reloadLoans() async {
    _loans = await _repo.loans();
    _recompute();
  }

  // Backup

  /// Builds the backup zip and opens the share sheet.
  Future<void> exportBackup() async {
    final file = await _backup.exportZip();
    await _backup.share(file);
  }

  /// Reads and validates a backup without changing anything.
  Future<BackupContents> readBackup(String path) => _backup.readBackup(path);

  /// Replaces all data with [contents], then reloads.
  Future<void> restoreBackup(BackupContents contents) async {
    try {
      await _backup.restore(contents);
    } finally {
      await load();
    }
  }
}

/// Exposes [AppState] to the widget tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  /// Reads the state and rebuilds [context] when it changes.
  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!.notifier!;
  }

  /// Reads the state without subscribing (for callbacks).
  static AppState read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AppScope>();
    final scope = element?.widget as AppScope?;
    assert(scope != null, 'No AppScope above this widget');
    return scope!.notifier!;
  }
}
