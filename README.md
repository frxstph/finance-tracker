# Finance Tracker

A personal, offline finance tracker for Android. One phone, one user, no
accounts, no internet. You record money in and money out, and it shows where
you stand this month.

## Features

- **Dashboard** with a month switcher and four numbers: cash on hand, still
  owed, left to pay this month (unpaid bills plus loan amounts due) and net
  position, plus a breakdown by type.
- **Quick add** for income, bills, one-time spends, daily spends and loan
  payments. A plain daily spend takes three taps: Add, type the amount, Save.
- **Receipt photos** from the camera or gallery, stored on the phone.
- **Bills** with a paid/unpaid state per month and a one-tap "Pay".
- **Loans** with a repayment plan (pay in full by a month, or monthly over a
  number of months), what's due this month, paid so far and a progress bar.
  Adding a new loan can put the money into this month's cash, and a loan
  can keep a photo of its agreement or IOU.
- **Pay amounts fill themselves**: pick a loan and the amount due this month
  is filled in; pick a bill and its monthly amount is.
- **Bills on any schedule**: monthly, weekly, daily or one time, optionally
  for a set number of payments (e.g. weekly, 6 times).
- **Monthly income** on a set day (salary every 19th, pay on the 15th) with a
  Receive button, next to monthly bills on the Monthly tab.
- **Entries list filters**: income, spending, one-time, loan payments, for
  one month or all months, with totals.
- **Forecast ("If all paid")**: where cash and net position land at the end
  of any month if expected income arrives and every bill and loan payment
  is made.
- **An add button that follows the tab**: add an entry, a bill or a loan.
- **Backup and restore** as a single zip you can keep in Drive or Files.
- Light and dark themes that follow the phone.

How the numbers work:

- Cash on hand carries over: what you had at the end of last month plus this
  month's income and loans received, minus spending and loan payments.
  Every month starts from ₱0 (no carry-over).
- Still owed = what is left on every loan, across all time.
- Net position = cash on hand − still owed − this month's unpaid bills.
  (Loan payments due are already inside still owed.)
- Loan payments are never counted as spending, and money received from a
  loan is never counted as income.
- A monthly loan expects one installment a month; a missed month rolls into
  the next, and paying ahead covers later months.

## Screenshots

_Coming soon._

## How the APK is built

There is no local build. Every push to `main` runs
[`.github/workflows/build.yml`](.github/workflows/build.yml) on GitHub Actions:

1. Installs Java 21 and Flutter (stable).
2. Generates the `android/` folder with `flutter create` (it is not kept in
   the repo) and sets the app name to "Finance Tracker".
3. Installs the fixed signing key from `ci/debug.keystore`, so every build has
   the same signature and installs over the previous one without losing data.
4. Runs `flutter analyze` and the unit tests.
5. Builds a release APK and publishes it as a GitHub Release named
   `build-<number>`.

You can also start a build by hand from the Actions tab ("Run workflow").

## Installing on your phone

1. On the phone, open the repository's **Releases** page and pick the newest
   `build-…` release.
2. Download `finance-tracker-<number>.apk`.
3. Open the file. If Android asks, allow your browser or Files app to
   **install unknown apps** (Settings → Apps → Special access → Install
   unknown apps).
4. Tap Install. Later builds install over the old one and keep your data.

## Backup and restore

- **Export:** Dashboard → Settings → Export backup. The app builds
  `finance-backup-YYYYMMDD-HHmm.zip` (your data as `data.json` plus all
  receipt photos) and opens the share sheet so you can save it to Drive,
  Files or anywhere else.
- **Restore:** Settings → Restore backup, pick the zip. The app checks the
  whole file first, then asks before replacing everything on the phone. If
  anything goes wrong, your current data is left as it was.

## Project layout

```
lib/
  main.dart        app entry, theme, state wiring
  domain/          pure Dart: models, money, dates, monthly summary rules
  data/            SQLite, receipt photos, backup zip
  state/           AppState (ChangeNotifier) and AppScope
  ui/              pages and small widgets
test/              unit tests for money, dates and the summary rules
ci/debug.keystore  fixed signing key (do not regenerate)
docs/              architecture spec
```

## Roadmap

- **v2:** read receipt text from photos, simple charts, a month-ahead
  forecast.
