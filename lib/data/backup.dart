import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart'
    show Archive, ArchiveFile, ZipDecoder, ZipEncoder;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;

import '../domain/dates.dart';
import '../domain/models.dart';
import 'photos.dart';
import 'repository.dart';

const int backupVersion = 2;

/// Backup versions this app can restore. Version 1 has no loan plans; its
/// loans read as "pay in full".
const Set<int> _readableVersions = <int>{1, 2};
const String _dataFileName = 'data.json';
const String _receiptsPrefix = 'receipts/';

/// A fully parsed and validated backup, ready to restore. Nothing on the
/// phone has been touched yet when one of these exists.
class BackupContents {
  const BackupContents({
    required this.bills,
    required this.loans,
    required this.entries,
    required this.receipts,
  });

  final List<Bill> bills;
  final List<Loan> loans;
  final List<Entry> entries;

  /// Receipt file name -> bytes.
  final Map<String, List<int>> receipts;
}

/// Thrown when the data was restored but the receipt photos could not be
/// swapped in. The entries, bills and loans are already the backup's.
class RestorePhotosException implements Exception {
  const RestorePhotosException();

  @override
  String toString() => 'Receipt photos could not be replaced';
}

class BackupService {
  BackupService(this._repo, this._photos);

  final Repository _repo;
  final PhotoStore _photos;

  // Export

  /// Writes `finance-backup-YYYYMMDD-HHmm.zip` to the temp folder.
  Future<File> exportZip() async {
    final bills = await _repo.bills();
    final loans = await _repo.loans();
    final entries = await _repo.entries();

    final data = <String, Object?>{
      'version': backupVersion,
      'bills': bills.map((b) => b.toMap()).toList(),
      'loans': loans.map((l) => l.toMap()).toList(),
      'entries': entries.map((e) => e.toMap()).toList(),
    };

    final archive = Archive();
    final jsonBytes = utf8.encode(jsonEncode(data));
    archive.addFile(ArchiveFile(_dataFileName, jsonBytes.length, jsonBytes));

    for (final file in await _photos.allFiles()) {
      final bytes = await file.readAsBytes();
      final name = '$_receiptsPrefix${p.basename(file.path)}';
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    final List<int>? zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError('Could not build the backup file');
    }

    final tmp = await getTemporaryDirectory();
    final out = File(p.join(
        tmp.path, 'finance-backup-${fileStamp(DateTime.now())}.zip'));
    await out.writeAsBytes(zipBytes, flush: true);
    return out;
  }

  /// Opens the Android share sheet with the backup file.
  Future<void> share(File zip) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(zip.path, mimeType: 'application/zip')],
        subject: p.basename(zip.path),
        text: 'Finance tracker backup',
      ),
    );
  }

  // Restore

  /// Reads and validates the whole backup without touching the phone's data.
  /// Throws [FormatException] with a user-readable message when invalid.
  Future<BackupContents> readBackup(String zipPath) async {
    final bytes = await _readBytes(zipPath);
    final archive = _decodeZip(bytes);

    List<int>? jsonBytes;
    final receipts = <String, List<int>>{};
    for (final ArchiveFile file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name;
      if (name == _dataFileName) {
        jsonBytes = _contentOf(file);
      } else if (name.startsWith(_receiptsPrefix)) {
        final photoName = name.substring(_receiptsPrefix.length);
        if (!isSafePhotoName(photoName)) continue;
        receipts[photoName] = _contentOf(file);
      }
    }
    if (jsonBytes == null) {
      throw const FormatException('The backup has no data.json.');
    }
    final Map<String, dynamic> data = _decodeJson(jsonBytes);
    return _parseData(data, receipts);
  }

  Future<List<int>> _readBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException {
      throw const FormatException('Could not read that file.');
    }
  }

  Archive _decodeZip(List<int> bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('That file is not a backup zip.');
    }
  }

  Map<String, dynamic> _decodeJson(List<int> bytes) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      decoded = null;
    }
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('The backup data is damaged.');
  }

  List<int> _contentOf(ArchiveFile file) {
    Object? content;
    try {
      content = file.content;
    } catch (_) {
      content = null;
    }
    if (content is List<int>) return content;
    throw FormatException('Could not unpack ${file.name}.');
  }

  List<Map<String, Object?>> _rows(Map<String, dynamic> data, String key) {
    final list = data[key];
    if (list is! List) {
      throw FormatException('The backup is missing "$key".');
    }
    final out = <Map<String, Object?>>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) {
        throw FormatException('A row in "$key" is damaged.');
      }
      out.add(Map<String, Object?>.from(item));
    }
    return out;
  }

  List<T> _parseRows<T>(
    Map<String, dynamic> data,
    String key,
    T Function(Map<String, Object?> row) parse,
  ) {
    final rows = _rows(data, key);
    final out = <T>[];
    for (final row in rows) {
      try {
        out.add(parse(row));
      } on FormatException {
        rethrow;
      } catch (_) {
        throw FormatException('A row in "$key" is damaged.');
      }
    }
    return out;
  }

  BackupContents _parseData(
      Map<String, dynamic> data, Map<String, List<int>> receipts) {
    final version = data['version'];
    if (version is! int || !_readableVersions.contains(version)) {
      throw FormatException('Unsupported backup version: ${data['version']}.');
    }
    final bills = _parseRows<Bill>(data, 'bills', Bill.fromMap);
    final loans = _parseRows<Loan>(data, 'loans', Loan.fromMap);
    final entries = _parseRows<Entry>(data, 'entries', Entry.fromMap);

    _validate(bills, loans, entries);

    return BackupContents(
      bills: bills,
      loans: loans,
      entries: entries,
      receipts: receipts,
    );
  }

  void _validate(List<Bill> bills, List<Loan> loans, List<Entry> entries) {
    Set<int> uniqueIds(Iterable<int?> ids, String what) {
      final seen = <int>{};
      for (final id in ids) {
        if (id == null || !seen.add(id)) {
          throw FormatException('The backup has a bad $what id.');
        }
      }
      return seen;
    }

    final billIds = uniqueIds(bills.map((b) => b.id), 'bill');
    final loanIds = uniqueIds(loans.map((l) => l.id), 'loan');
    uniqueIds(entries.map((e) => e.id), 'entry');

    for (final b in bills) {
      if (b.amount < 0) throw const FormatException('A bill has a bad amount.');
    }
    for (final l in loans) {
      if (l.principal < 0 ||
          !isValidDateKey(l.created) ||
          l.months < 1 ||
          !isValidMonthKey(l.startMonth) ||
          (l.photo != null && !isSafePhotoName(l.photo!))) {
        throw const FormatException('A loan has bad data.');
      }
    }
    for (final e in entries) {
      if (e.amount < 0 || !isValidDateKey(e.date)) {
        throw const FormatException('An entry has a bad amount or date.');
      }
      if (e.type == EntryType.bill && !billIds.contains(e.billId)) {
        throw const FormatException('A bill payment points to a missing bill.');
      }
      if (e.type.needsLoan && !loanIds.contains(e.loanId)) {
        throw const FormatException('A loan entry points to a missing loan.');
      }
      if (e.billId != null && !billIds.contains(e.billId)) {
        throw const FormatException('An entry points to a missing bill.');
      }
      if (e.loanId != null && !loanIds.contains(e.loanId)) {
        throw const FormatException('An entry points to a missing loan.');
      }
      final photo = e.photo;
      if (photo != null && !isSafePhotoName(photo)) {
        throw const FormatException('An entry has a bad photo name.');
      }
    }
  }

  /// Replaces everything on this phone with [contents].
  ///
  /// Receipt files are staged in a new folder first. The database swap is a
  /// single transaction. Only after it commits is the staged folder moved
  /// into place. On any failure before the commit, existing data and
  /// receipts are untouched.
  Future<void> restore(BackupContents contents) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final docs = _photos.documentsPath;
    final live = _photos.receiptsDir;
    final staging = Directory(p.join(docs, 'receipts_restore_$stamp'));
    final old = Directory(p.join(docs, 'receipts_old_$stamp'));

    try {
      await staging.create(recursive: true);
      for (final item in contents.receipts.entries) {
        await File(p.join(staging.path, item.key))
            .writeAsBytes(item.value, flush: true);
      }
    } catch (_) {
      await _deleteQuietly(staging);
      rethrow;
    }

    try {
      await _repo.replaceAll(
        bills: contents.bills,
        loans: contents.loans,
        entries: contents.entries,
      );
    } catch (_) {
      await _deleteQuietly(staging);
      rethrow;
    }

    // The database now holds the backup. Swap the receipts folder.
    try {
      if (await live.exists()) {
        await live.rename(old.path);
      }
      await staging.rename(live.path);
    } on FileSystemException {
      throw const RestorePhotosException();
    }
    await _deleteQuietly(old);
  }

  Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } on FileSystemException {
      // Leftover temp folders are harmless.
    }
  }
}
