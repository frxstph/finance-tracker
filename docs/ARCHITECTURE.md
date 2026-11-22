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
- **Net position** = `cash(M) − stillOwed − billsLeftAmount(M)` (v1.5;
  loan dues are not subtracted again, they are inside `stillOwed`).
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

## 12. v1.1 changes (loan plans, money received, contextual add button)

These amend the sections above; where they disagree, this section wins.

**New entry type `loan_received`** ("Loan received"). Linked to a loan via
`loan_id`. Raises cash but is not income:
`cash(M) = income(M) + loanReceived(M) − spent(M) − loanPaid(M)`.
It is created only by the new-loan form (toggle "Add this money to cash",
on by default, off for loans taken before using the app), dated today, for
the loan's full amount. It is not offered in the quick add type chips, but
an existing one can still be edited. Deleting a loan with no payments also
deletes its `loan_received` entries (one transaction).

**Loan repayment plan.** Schema v2 adds to `loans`:
`plan TEXT NOT NULL DEFAULT 'full'` (`full` | `monthly`),
`months INTEGER NOT NULL DEFAULT 1`, `start_month TEXT` (`yyyy-MM`).
Upgrading from v1 sets `start_month` to the month the loan was created.
- `full`: one payment of everything, due in `start_month`.
- `monthly`: `months` payments from `start_month`. Installment =
  `ceil(principal / months)` centavos; the plan never expects more than the
  principal.
- **Due in month M** = (installments expected by the end of M, capped at
  the principal) − (payments dated up to the end of M), clamped to
  `[0, balance]`. Nothing is due before `start_month`; a missed month rolls
  into the next; paying ahead covers later months.

**Dashboard.** "Bills left" becomes **"Left to pay"**: unpaid bills plus loan
amounts due this month. The breakdown gains "Loans received".

**Loans tab.** Has the month switcher. Each card shows the plan
("₱X a month · N of M paid · Dec 2026 to May 2027" or "Pay in full by
Nov 2026"), paid of total, and what's due in the selected month. "Pay"
prefills the amount due (or the balance when nothing is due).

**Add button follows the tab.** Dashboard and Entries: "Add entry". Bills:
"Add bill". Loans: "Add loan" (opens the full-screen loan form).

**Backup.** Exports `version: 2` (loans carry plan fields). Restores version
1 or 2; version-1 loans read as pay in full.

## 13. v1.2 changes (payment amounts, photos)

- **Pay amounts fill themselves.** Choosing a loan in quick add (or opening
  it from a Pay button) fills the amount due this month, else the balance;
  choosing a bill fills its monthly amount. A filled amount is replaced when
  another bill or loan is picked, never an amount the user typed. With one
  open loan, it is picked automatically. Paid-off loans are hidden from the
  payment picker.
- **Photo button** sits under the amount and picker, labelled "Add photo of
  payment" for loan payments and "Add receipt photo" otherwise.
- **Loan photo.** Schema v3 adds `loans.photo TEXT` (file name in
  `receipts/`, same rules as entry photos). Set in the loan form ("Add photo
  of agreement"); shown as a thumbnail on the loan card that opens full
  screen with pinch to zoom. Deleted with the loan. Included in backups
  (same receipts folder); backup format stays version 2 with an optional
  `photo` on loans.

## 14. v1.3 changes (pay screen)

- **Suggested payment** = due this month if anything is; otherwise the next
  installment (paying ahead), capped at the balance. Never the whole
  balance of a monthly loan just because nothing is due yet. Used by the
  pay screen and by quick add.
- **Pay screen.** A loan's Pay button opens a short confirm screen, not the
  full entry form: what the payment is ("Due this month", "Payment 1 of 6 ·
  Dec 2026"), the amount in large type with a "Change" link, balance after
  it, "Add photo of payment", date paid (today), and a full-width "Confirm
  payment" button.

## 15. v1.4 changes (bill pay screen)

- One shared `ConfirmPaymentPage` (lib/ui/confirm_payment_page.dart) backs
  every Pay button; `lib/ui/pay_pages.dart` fills it for bills and loans.
- **Bills' Pay** now opens it: "Monthly bill · November 2026", the bill's
  usual amount in large type ("Change" to edit), "Add photo of receipt",
  date paid, "Confirm payment". The date defaults to today when the selected
  month is the current one, otherwise the 1st of the selected month, so the
  payment marks that month's bill as paid.

## 16. v1.6 changes (dashboard colors)

Stat card values: Cash on hand green above ₱0, red below. Left to pay
orange while anything is unpaid. Still owed red while any loan has a
balance. Net position green above ₱0, red below. Zero stays the plain text
color. Colors come from `incomeColor`, `billsColor` and `debtColor` in
lib/ui/theme.dart, with lighter shades in dark mode.

## 17. v1.7 changes (carry-over, monthly income, entry filters, forecast)

**Cash carries over.** Replaces "each month starts at ₱0" (§5).
`openingCash(M)` = all money in − all money out dated before M;
`cash(M) = openingCash(M) + monthChange(M)`. Money in = income and loan
received; everything else is money out. The dashboard shows "Started month
with ₱X" under cash on hand.

**Monthly income sources.** Schema v4: table `incomes(id, name, amount, day
1–31, active)`, and `entries.income_id` (only on income entries). A source
is expected each month until an income entry linked to it is dated in that
month. Day 29–31 falls on the last day of shorter months. Delete only when
never received; otherwise archive. Backup version 3 adds `incomes`
(versions 1–2 still restore, with no incomes).

**Monthly tab** (was "Bills"): "Monthly income" section (each with
"Receive" → the shared confirm screen, dated today in the current month or
the source's day in another month) above "Monthly bills". Its add button
asks which one to add. Quick add's Income type has an optional "Monthly
income" picker ("Other income (not monthly)" by default).

**Entries tab.** Filter chips: All, Income (incl. loans received),
Spending (bills, one-time, daily), One-time, Loan payments; an "All months"
chip that drops the month switcher. A total line: net for All, sum
otherwise.

**Forecast ("If all paid").** A dashboard toggle. `forecastMonths(from:
current month, to: selected month)` simulates each month: start cash
(actual for the current month, the previous month's projected end after
that) + recorded entries in the month + monthly income not yet received −
active bills not yet paid − the loan payments each plan expects (catch-up
included; payments the forecast already assumed in earlier months count as
made). End cash, loans owed after those payments, and net position = end
cash − owed after. Months before the current one have no forecast; the
dashboard says so and shows the actual numbers. A "How it adds up" card
lists the sum.

## 18. v1.8 changes (bill schedules)

Schema v5 adds to `bills`: `frequency TEXT NOT NULL DEFAULT 'monthly'`
(`monthly` | `weekly` | `daily` | `once`), `times INTEGER` (null = no end),
`start_date TEXT` (yyyy-MM-dd; null only for monthly bills made before
v1.8, which stay due every month). `amount` is the amount each time.

**Times due in month M** (`billDueCount`, lib/domain/bill_schedule.dart):
monthly = 1 from the start month, for `times` months; weekly/daily = every
7 days / every day from the start date that falls in M, up to `times`
payments in all; once = 1 in the due date's month. **Paid** = number of bill
entries for it in M. Left = due − paid (not below 0); left amount = left ×
amount. "Left to pay", net position and the forecast all use this.

Bill form (full screen): name, amount each time, How often chips, first
payment / due date, "Only a set number of times" + count, and a preview
line. List rows: "₱500 a week · 6 times · 2 of 5 paid"; when nothing is due:
"Starts Jan 2027", "Due Dec 2026", "Finished" or "Not this month". Backup
version 4 (1–3 still restore; their bills read as monthly).

Also: the empty-row hints on the Monthly tab are gone, and cash on hand's
detail line reads "Running balance".

## 19. v1.8.1 (loan card layout)

Loan cards read top to bottom in four bands: name with Pay and the menu;
the balance as one large number (dark text, green when paid off) with "left of
₱total"; the progress bar with "₱paid paid · n of m paid" and "₱x / month"
under it; then a colored status pill (orange "Due this month · ₱x", grey
"Starts …", green "Nothing due this month" / "Paid off") beside the date
range. Same information as before, grouped.

## 20. v1.9 changes (adjustments, sums, accounts, week blocks)

**Adjustments.** Entry types `adjust_in` / `adjust_out` (one "Adjustment"
chip with "Add to cash" / "Take from cash"). They move cash and carry over
but are neither income nor spending; the breakdown shows their net.
**Count my cash** (tap the Cash on hand card): enter the real amount; the
difference from `cashNow` (all entries dated up to today) is saved as an
adjustment dated today, note "Cash count".

**Sums in amount boxes.** `parseCentavos` also evaluates `a op b op c…`
with + − × ÷ (also * /), × and ÷ first; numbers after × or ÷ are plain
factors; results round to the centavo; negative, unfinished, ÷0 or too
large → null. Amount fields show + − × ÷ buttons while focused, "= ₱605"
under a sum, and replace the sum with its total when focus leaves.

**My accounts** (QR icon on the Dashboard). Schema v6 table
`accounts(id, name, details, photo)`. Each card shows the QR image (tap for
full screen on white), the details with a copy button, and share (image +
text). Photos live in the receipts folder and go into backups. Backup
version 5 (1–4 still restore).

**Week blocks in "If all paid".** Schema v6 adds `loans.due_day` (optional
1–31). `weekBlocks` splits a forecast month into 1–7, 8–14, 15–21, 22–end:
recorded entries on their day; monthly income not yet received on its day;
each bill payment still due on its due day (`billDueDays`); each loan
payment the forecast expects on the loan's due day. Overdue items or items
without a due day count on today (current month) or the 1st (later
months). Block end cash chains; the last equals the forecast's end cash.
The card warns about the first upcoming block that ends below ₱0.

## 21. v1.9.1 (one color rule)

Lists use one rule: money in green with "+", money out red with "−" (true
minus sign), zero muted grey (`flowColor`, `signedPeso`). Balances (cash
at a point in time) are dark bold text, red only below ₱0
(`balanceColor`). Week blocks show the date range as the heading and end
with a labelled "Cash after" line; "How it adds up" and the "This month"
breakdown follow the same rule, and the breakdown ends with "Net this
month". The four stat cards keep their own colors.

## 22. v1.10 changes (calculator, money tools, safe to spend)

All math is pure Dart in lib/domain/calc.dart, unit tested.

**Calculator** (calculator icon on the Dashboard). `evaluateExpression`:
+ − × ÷ (× ÷ first), leading or after-× minus, postfix % (÷100), commas
ignored; null for unfinished lines or ÷0. Keypad C ⌫ % ÷ / 7–9 × / 4–6 − /
1–3 + / 00 0 . =; the last 10 results stay for the session (tap to reuse).
"Use ₱x in a new entry" opens Add entry with the amount.

**Loan tab.** `quoteLoan`: add-on (% a month on the full amount every
month: interest = P × r × n, payment = ⌈total ÷ n⌉) or yearly reducing
balance (standard amortization, payment rounded up to the centavo).
Shows each month, total, interest; "Add as a loan" opens the loan form
filled in with the total and months.

**Split tab.** Even split; any leftover centavos go to one person.

**Afford tab.** `canAfford`: takes the amount out of every week block from
the purchase date to the end of the next month in "If all paid" and
reports the lowest block-end cash (and where), plus month-end cash.
Affordable when the lowest stays at or above ₱0.

**Safe to spend** (Dashboard, "Now", current month only). Payday = the
earliest monthly income still to come (this month if on or after today and
not yet received, else next month); none set → end of month. Set aside =
every bill and loan payment the week blocks place before payday (overdue
count today) plus anything recorded after today in that window. Per day =
(cash up to today − set aside) ÷ days from today to payday (today counts,
at least 1); shows "Short by ₱x" when negative. Tap for the breakdown.

## 23. v1.10.1 (safe to spend looks past payday; "Can I buy it?")

**Safe to spend** now also keeps back money for after payday: budget =
min(free before payday, lowest week-block end cash from today through the
end of the month after payday's month). Per day = budget ÷ days. The
breakdown shows "Kept for bills after payday" and the tightest week.

**"Can I buy it?"** (was "Afford"): "How much is it?", "When would you buy
it?" (Today / After payday / Pick a date), then a plain answer ("Yes, you
can buy it" or "Not on …", with how short and when). The purchase week is
checked day by day (income later in the week does not count yet), later
weeks by their end cash. When the answer is no, `earliestAffordable`
scans up to 62 days ahead and offers the earliest safe day.

## 24. v1.11 clarity pass (same math, plainer words)

- **Modes renamed:** "Now / If all paid" → "Today / Plan ahead", with a
  one-line note under Plan ahead. Plan cards: Month-end cash, Loans left,
  Pay to come, Net position (short details that fit).
- **Safe to spend** leads with one sentence: "₱650 a day · Until Pay on the
  19th (8 days), with all bills covered", or "Hold off spending · You'll be
  ₱X short around 1–7 Dec / before payday", or "Nothing spare". "See how"
  opens the breakdown: cash now, due before payday, left before payday,
  lowest later (when lower), then short by or you can spend / each day.
- **Can I buy it?** first checks the same date with ₱0: if that is already
  short, it says "You're already short" (how much without it, how much with
  it) instead of blaming the purchase and offering no safe day.
- **Due-day nudge:** bills with no start date (`billHasDueDay` false) and
  loans with a balance and no due day are counted on the 1st or today,
  which can make early weeks look short. A banner on the Dashboard and in
  "Can I buy it?" opens **Set due days**: one list, a day box each. A bill's
  start date becomes that day in the month of its first payment (or this
  month), so months it was already due stay due (`startDateForDueDay`).

## 25. v1.11.1 Dashboard polish and the Scan button

Design: the "Dashboard polish v1.11.1" and "Scan button concept" canvases.

- **One card format.** `widgets/info_card.dart` (`InfoCard`) is shared by
  Safe to spend and the due-day banner: icon + title on one row, an optional
  big headline, body text, then actions at the bottom left. Body and actions
  start at the same left edge, so the two cards line up.
- **Due-day banner** is shorter ("4 loans need a due day" / "Plans may look
  short until you set them.") with **Set due days** and **Later**. Later
  hides it until the set of items without a due day changes or the app
  restarts (`AppState.showDueDayNudge`, `hideDueDayNudge`; in memory only).
- **Safe to spend** shows whole pesos a day (rounded down), a shorter
  sentence, and a **"Payday in N days"** pill on the title row (tomorrow /
  today wording; hidden when there is no monthly income).
- **Today's date** ("22" over "Sun") sits at the right end of the Today /
  Plan ahead row. It is always today's date.
- **Amounts stay on one line.** `formatPeso` uses a true minus sign
  ("−₱1,250") and from ₱1,000,000 up rounds off the centavos
  ("₱1,145,578"). Stat card values already shrink to fit (`FittedBox`).
- **Scan button.** The tab bar is Dashboard, Entries, a raised Scan circle,
  Monthly, Loans. Scan opens "Add a spend": Scan a receipt and Choose a photo
  say "Coming soon" (receipt OCR is the next update); Add without a photo
  opens the normal add screen. The + button is gone from Dashboard and
  Entries; Monthly and Loans keep their own Add.
- Smaller fixes: "Tap to count" caption, tighter month row.
