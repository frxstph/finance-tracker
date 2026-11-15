# Finance Tracker: architecture spec (v1)

Personal, offline Android finance tracker. One user, one phone, no accounts, no
network. This file is the contract the implementation must follow.

## 1. Constraints that shape everything

- **No local toolchain.** The code is written in an environment with no Flutter
  or Dart SDK and no access to pub.dev. GitHub Actions is the only compiler.
  So: prefer boring, long-stable APIs; keep dependencies few; no code
  generation (no build_runner, freezed, drift, json_serializable).
- **The `android/` folder is not committed.** CI generates it with
  `flutter create` in a temp folder and copies it in, so the Gradle files always
  match the Flutter version CI installs.
- **Stable signing key.** `ci/debug.keystore` is committed (private repo,
  personal app). CI copies it to `~/.android/debug.keystore` before building.
  The Flutter template signs release builds with the debug config, so every
  APK has the same signature and installs over the previous one without
  wiping data. Never regenerate this file.
- **Offline.** No INTERNET permission needed by app code. No analytics, no
  network calls, no Firebase.
- **No personal data in the repo.** No hardcoded bill names, loan names or
  amounts. The app starts empty and the user adds their own. Tests use
  made-up numbers.

## 2. Stack

- Flutter, stable channel, Dart 3, Material 3. Android only.
- Dependencies (keep to this list; use caret constraints on a recent stable
  major, CI resolves exact versions):
  - `sqflite` (storage), `path`, `path_provider`
  - `image_picker` (camera and gallery)
  - `intl` (peso and date formatting)
  - `archive` (zip for backup)
  - `share_plus` (hand the backup file to Drive, Files, etc.)
  - `file_picker` (choose a backup file to restore)
- Dev: `flutter_test`, `flutter_lints`, `sqflite_common_ffi` only if needed for
  repository tests (prefer not to: keep repository thin and test pure logic).
- State: plain `ChangeNotifier` (`AppState`) exposed through an
  `InheritedNotifier`. No provider/riverpod/bloc packages.

## 3. Money and dates

- All amounts are **integer centavos** (`int`). Never `double` in storage or
  math. Parse user input "1,250.50" → 125050. Format with `intl` as `₱1,250.50`
  (drop `.00` when whole: `₱1,250`).
- Dates stored as ISO `yyyy-MM-dd` text (local date, no time zone math).
  Month key is `yyyy-MM`.

## 4. Data model (SQLite, schema version 1)

```sql
CREATE TABLE bills (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  amount INTEGER NOT NULL,          -- expected monthly amount, centavos
  active INTEGER NOT NULL DEFAULT 1 -- 0 = archived, hidden from new months
);
CREATE TABLE loans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  principal INTEGER NOT NULL,       -- total owed when added, centavos
  created TEXT NOT NULL             -- yyyy-MM-dd
);
CREATE TABLE entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,               -- income | bill | one_time | daily | loan_payment
  amount INTEGER NOT NULL,          -- always positive, centavos
  note TEXT NOT NULL DEFAULT '',
  date TEXT NOT NULL,               -- yyyy-MM-dd
  bill_id INTEGER REFERENCES bills(id),   -- set only when type = bill
  loan_id INTEGER REFERENCES loans(id),   -- set only when type = loan_payment
  photo TEXT,                       -- file name inside receipts/ dir, or NULL
  created_at TEXT NOT NULL          -- ISO timestamp
);
CREATE INDEX idx_entries_date ON entries(date);
```

Rules:
- `type = bill` requires `bill_id`; `type = loan_payment` requires `loan_id`.
- Deleting a bill or loan that has entries is not allowed; archive the bill
  (`active = 0`) instead. A loan with entries can't be deleted; a loan with no
  entries can.
- Deleting an entry deletes its photo file.
- Photos are copied into `<app documents>/receipts/<timestamp>_<random>.jpg`
  (picked with `imageQuality: 70, maxWidth: 1600`). Only the file name is
  stored in the DB, never an absolute path.

## 5. The calculation rules (pure Dart, unit tested)

Put these in `lib/domain/` with no Flutter or sqflite imports.

For a selected month `M`:

- `income(M)` = sum of `income` entries dated in M.
- `spent(M)` = sum of `bill` + `one_time` + `daily` entries in M.
- `loanPaid(M)` = sum of `loan_payment` entries in M.
- **Cash on hand** `cash(M) = income(M) − spent(M) − loanPaid(M)`.
  Each month starts from ₱0: no carry-over from earlier months. (The user
  asked for this explicitly.) Can be negative; show it in the danger color.
- **Still owed** = for every loan, `max(0, principal − all payments ever)`,
  summed. This is across all time, not per month.
- **Bills left this month** = active bills with no `bill` entry (matching
  `bill_id`) dated in M. Show the count and the sum of their expected amounts.
  A bill is "paid" for M once at least one entry for it exists in M.
- **Net position** = `cash(M) − stillOwed`.
- **Breakdown** = totals per type for M.

Loan payments are not expenses: they must never be added into `spent`.

## 6. Screens

Bottom navigation with 4 tabs plus a floating "Add" button on every tab.

1. **Dashboard** (home). Month switcher (‹ November 2026 ›) at the top. Four
   stat cards: Cash on hand, Still owed, Bills left (count + amount), Net
   position. Under them a simple breakdown list (Income, Bills, One-time,
   Daily, Loan payments) with amounts. No chart library in v1.
2. **Entries.** List for the selected month, newest first, grouped by day.
   Each row: type icon, note (or type name), amount (income green with `+`,
   others plain), small camera icon when a photo exists. Tap → entry detail
   (shows photo full width, edit, delete with confirm).
3. **Bills.** Active bills with paid/unpaid state for the selected month.
   Unpaid row has a "Pay" button → opens Quick add prefilled (type bill, that
   bill, its amount, today). Add/edit/archive bills from here.
4. **Loans.** Each loan: name, principal, paid so far, balance, a progress
   bar. "Pay" button → Quick add prefilled (type loan_payment, that loan).
   Add/edit loans; delete only when it has no payments.

**Quick add** (full-screen dialog/route): amount field focused with number
keyboard, type selector (5 segmented chips), bill picker when type = bill,
loan picker when type = loan_payment, note, date (defaults today), "Add
photo" (camera or gallery), Save. Validation: amount > 0; bill/loan chosen
when needed. Saving returns to where the user was and refreshes totals. It
must be faster than writing in a notebook: 3 taps for a plain daily spend.

**Settings** (app bar icon on Dashboard): Export backup, Restore backup,
app version text.

Empty states are invitations with one action each ("Add your first bill").

## 7. Backup

- **Export:** build `finance-backup-YYYYMMDD-HHmm.zip` in the temp dir
  containing `data.json` (`{"version":1,"bills":[…],"loans":[…],"entries":[…]}`)
  and every file from `receipts/` under `receipts/`. Share it with
  `share_plus`.
- **Restore:** pick a zip with `file_picker`, validate `version == 1`, confirm
  with the user ("This replaces everything on this phone"), then inside one
  DB transaction delete all rows and insert the backup's rows keeping their
  ids; replace the `receipts/` folder contents. On any error, leave the
  existing data untouched and show the error.

## 8. Code layout

```
lib/
  main.dart                 app entry, theme, AppState wiring
  domain/
    models.dart             Entry, Bill, Loan, EntryType (plain classes, toMap/fromMap)
    money.dart              parseCentavos, formatPeso
    summary.dart            MonthSummary + computeSummary(...) — the rules in §5
    dates.dart              month key helpers, add month, labels
  data/
    db.dart                 open DB, schema, migrations
    repository.dart         CRUD + queries; thin, no business rules
    photos.dart             copy/delete/resolve receipt files
    backup.dart             export/restore zip
  state/
    app_state.dart          ChangeNotifier: selected month, loaded lists, summary; actions
  ui/
    home_shell.dart         bottom nav + FAB
    dashboard_page.dart, entries_page.dart, bills_page.dart, loans_page.dart
    quick_add_page.dart, entry_detail_page.dart, settings_page.dart
    widgets/                stat_card.dart, month_switcher.dart, etc.
test/
  money_test.dart, summary_test.dart, dates_test.dart
ci/debug.keystore           fixed signing key (do not regenerate)
.github/workflows/build.yml
pubspec.yaml, analysis_options.yaml, README.md, .gitignore
```

## 9. CI (`.github/workflows/build.yml`)

Triggers: push to `main`, and `workflow_dispatch`. `permissions: contents: write`.

Steps:
1. `actions/checkout@v4`
2. `actions/setup-java@v4` (temurin 21; Android lint on current Flutter needs Java 21)
3. `subosito/flutter-action@v2` (channel stable, cache on)
4. Generate the Android scaffold and copy it in:
   `flutter create --platforms=android --org ph.patrick --project-name finance_tracker /tmp/scaffold`
   then `cp -r /tmp/scaffold/android ./android`
5. Set the launcher label to "Finance Tracker" (sed on
   `android/app/src/main/AndroidManifest.xml`, `android:label`).
6. `mkdir -p ~/.android && cp ci/debug.keystore ~/.android/debug.keystore`
7. `flutter pub get`
8. `flutter analyze --no-fatal-infos --no-fatal-warnings`
9. `flutter test`
10. `flutter build apk --release --build-number=${{ github.run_number }}`
11. Rename to `finance-tracker-${{ github.run_number }}.apk`; upload with
    `actions/upload-artifact@v4`.
12. Publish a GitHub Release tagged `build-${{ github.run_number }}` with the
    APK attached (`gh release create` with `GH_TOKEN: ${{ github.token }}`),
    so the APK is one tap to download on the phone.

The keystore password, alias and key password are the Android debug defaults
(`android` / `androiddebugkey` / `android`).

## 10. Not in v1

Receipt text reading (ML Kit), charts, the month-ahead forecast, sub-labels
for daily spending, carry-over between months, multiple currencies, iOS.
Leave clean seams (the `domain/` layer) but write no code for these.

## 11. Quality bar

- `flutter analyze` clean of errors. No `dynamic` soup; null-safe; `const`
  where natural.
- Every `async` gap that touches `BuildContext` checks `mounted` /
  `context.mounted`.
- No deprecated APIs where a stable replacement has existed for a year or
  more, but when unsure between a new API and an old one that is certain to
  exist, choose the one certain to compile on current stable Flutter.
- UI copy: sentence case, short, plain words, peso amounts.
- Unit tests cover §3 and §5 including: empty month, negative cash, loan
  overpayment clamped at 0, bill paid twice in a month, entries on month
  boundaries, parse/format round trips.
