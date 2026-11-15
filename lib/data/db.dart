import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const int schemaVersion = 1;
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
    },
    // Future schema versions add an onUpgrade here.
  );
}
