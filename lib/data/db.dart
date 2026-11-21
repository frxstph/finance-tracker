import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const int schemaVersion = 6;
const String databaseFileName = 'finance.db';

const List<String> _schemaV1 = <String>[
  '''
CREATE TABLE bills (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  amount INTEGER NOT NULL,
  active INTEGER NOT NULL DEFAULT 1
)''',
  '''
CREATE TABLE loans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  principal INTEGER NOT NULL,
  created TEXT NOT NULL
)''',
  '''
CREATE TABLE entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  amount INTEGER NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  date TEXT NOT NULL,
  bill_id INTEGER REFERENCES bills(id),
  loan_id INTEGER REFERENCES loans(id),
  photo TEXT,
  created_at TEXT NOT NULL
)''',
  'CREATE INDEX idx_entries_date ON entries(date)',
];

/// Version 2: loans get a repayment plan. Old loans become "pay in full",
/// due in the month they were added.
const List<String> _upgradeToV2 = <String>[
  "ALTER TABLE loans ADD COLUMN plan TEXT NOT NULL DEFAULT 'full'",
  'ALTER TABLE loans ADD COLUMN months INTEGER NOT NULL DEFAULT 1',
  'ALTER TABLE loans ADD COLUMN start_month TEXT',
  'UPDATE loans SET start_month = substr(created, 1, 7) '
      'WHERE start_month IS NULL',
];

/// Version 3: a loan can have a photo (agreement, IOU).
const List<String> _upgradeToV3 = <String>[
  'ALTER TABLE loans ADD COLUMN photo TEXT',
];

/// Version 4: monthly income sources, and income entries can point to one.
const List<String> _upgradeToV4 = <String>[
  '''
CREATE TABLE incomes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  amount INTEGER NOT NULL,
  day INTEGER NOT NULL,
  active INTEGER NOT NULL DEFAULT 1
)''',
  'ALTER TABLE entries ADD COLUMN income_id INTEGER REFERENCES incomes(id)',
];

/// Version 5: bills get a schedule. Old bills stay monthly with no end and
/// no start date.
const List<String> _upgradeToV5 = <String>[
  "ALTER TABLE bills ADD COLUMN frequency TEXT NOT NULL DEFAULT 'monthly'",
  'ALTER TABLE bills ADD COLUMN times INTEGER',
  'ALTER TABLE bills ADD COLUMN start_date TEXT',
];

/// Version 6: payment accounts with QR codes, and a due day on loans.
const List<String> _upgradeToV6 = <String>[
  '''
CREATE TABLE accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  details TEXT NOT NULL DEFAULT '',
  photo TEXT
)''',
  'ALTER TABLE loans ADD COLUMN due_day INTEGER',
];

/// Opens (and creates on first run) the app database.
Future<Database> openAppDatabase() async {
  final dir = await getDatabasesPath();
  return openDatabase(
    p.join(dir, databaseFileName),
    version: schemaVersion,
    onConfigure: (Database db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (Database db, int version) async {
      for (final sql in _schemaV1) {
        await db.execute(sql);
      }
      for (final sql in _upgradeToV2) {
        await db.execute(sql);
      }
      for (final sql in _upgradeToV3) {
        await db.execute(sql);
      }
      for (final sql in _upgradeToV4) {
        await db.execute(sql);
      }
      for (final sql in _upgradeToV5) {
        await db.execute(sql);
      }
      for (final sql in _upgradeToV6) {
        await db.execute(sql);
      }
    },
    onUpgrade: (Database db, int oldVersion, int newVersion) async {
      if (oldVersion < 2) {
        for (final sql in _upgradeToV2) {
          await db.execute(sql);
        }
      }
      if (oldVersion < 3) {
        for (final sql in _upgradeToV3) {
          await db.execute(sql);
        }
      }
      if (oldVersion < 4) {
        for (final sql in _upgradeToV4) {
          await db.execute(sql);
        }
      }
      if (oldVersion < 5) {
        for (final sql in _upgradeToV5) {
          await db.execute(sql);
        }
      }
      if (oldVersion < 6) {
        for (final sql in _upgradeToV6) {
          await db.execute(sql);
        }
      }
    },
  );
}
