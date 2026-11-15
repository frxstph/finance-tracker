import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

/// Thin CRUD layer over SQLite. Business rules live in domain/ and state/.
class Repository {
  Repository(this._db);

  final Database _db;

  // Bills

  Future<List<Bill>> bills() async {
    final rows = await _db.query('bills', orderBy: 'name COLLATE NOCASE, id');
    return rows.map(Bill.fromMap).toList();
  }

  Future<int> insertBill(Bill bill) => _db.insert('bills', bill.toMap());

  Future<void> updateBill(Bill bill) async {
    await _db.update('bills', bill.toMap(),
        where: 'id = ?', whereArgs: <Object?>[bill.id]);
  }

  Future<void> deleteBill(int id) async {
    await _db.delete('bills', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<bool> billHasEntries(int id) async {
    final rows = await _db.query('entries',
        columns: <String>['id'],
        where: 'bill_id = ?',
        whereArgs: <Object?>[id],
        limit: 1);
    return rows.isNotEmpty;
  }

  // Loans

  Future<List<Loan>> loans() async {
    final rows = await _db.query('loans', orderBy: 'created, id');
    return rows.map(Loan.fromMap).toList();
  }

  Future<int> insertLoan(Loan loan) => _db.insert('loans', loan.toMap());

  Future<void> updateLoan(Loan loan) async {
    await _db.update('loans', loan.toMap(),
        where: 'id = ?', whereArgs: <Object?>[loan.id]);
  }

  Future<void> deleteLoan(int id) async {
    await _db.delete('loans', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<bool> loanHasEntries(int id) async {
    final rows = await _db.query('entries',
        columns: <String>['id'],
        where: 'loan_id = ?',
        whereArgs: <Object?>[id],
        limit: 1);
    return rows.isNotEmpty;
  }

  // Entries

  /// All entries, newest first.
  Future<List<Entry>> entries() async {
    final rows = await _db.query('entries', orderBy: 'date DESC, id DESC');
    return rows.map(Entry.fromMap).toList();
  }

  Future<int> insertEntry(Entry entry) => _db.insert('entries', entry.toMap());

  Future<void> updateEntry(Entry entry) async {
    await _db.update('entries', entry.toMap(),
        where: 'id = ?', whereArgs: <Object?>[entry.id]);
  }

  Future<void> deleteEntry(int id) async {
    await _db.delete('entries', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  // Backup

  /// Replaces every row with the given ones, keeping their ids, inside one
  /// transaction. If anything throws, the transaction rolls back and the
  /// existing data is untouched.
  Future<void> replaceAll({
    required List<Bill> bills,
    required List<Loan> loans,
    required List<Entry> entries,
  }) async {
    await _db.transaction((Transaction txn) async {
      await txn.delete('entries');
      await txn.delete('bills');
      await txn.delete('loans');
      for (final b in bills) {
        await txn.insert('bills', b.toMap());
      }
      for (final l in loans) {
        await txn.insert('loans', l.toMap());
      }
      for (final e in entries) {
        await txn.insert('entries', e.toMap());
      }
    });
  }
}
