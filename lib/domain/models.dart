/// Plain data classes for the finance tracker. No Flutter or sqflite imports.
library;

enum EntryType {
  income('income', 'Income'),
  bill('bill', 'Bill'),
  oneTime('one_time', 'One-time'),
  daily('daily', 'Daily'),
  loanPayment('loan_payment', 'Loan payment'),

  /// Money received from a new loan. Raises cash but is not income.
  /// Created when a loan is added; never picked by hand.
  loanReceived('loan_received', 'Loan received'),

  /// A correction that adds to cash (a starting balance, found money, a
  /// cash count that came out higher). Not income.
  adjustIn('adjust_in', 'Adjustment'),

  /// A correction that takes from cash (a cash count that came out lower).
  /// Not spending.
  adjustOut('adjust_out', 'Adjustment');

  const EntryType(this.dbValue, this.label);

  /// Value stored in the `entries.type` column and in backups.
  final String dbValue;

  /// Sentence-case label for the UI.
  final String label;

  static EntryType fromDb(String value) {
    for (final t in EntryType.values) {
      if (t.dbValue == value) return t;
    }
    throw FormatException('Unknown entry type: $value');
  }

  /// Money coming in (shown green with a plus sign).
  bool get isMoneyIn =>
      this == income || this == loanReceived || this == adjustIn;

  bool get isAdjustment => this == adjustIn || this == adjustOut;

  /// Linked to a loan through `loan_id`.
  bool get needsLoan => this == loanPayment || this == loanReceived;

  /// Offered in the quick add type chips.
  /// "Adjustment" shows as one chip (adjustIn) with an add/take toggle.
  bool get userSelectable => this != loanReceived && this != adjustOut;
}

/// How a loan is paid back.
enum LoanPlan {
  /// One payment of the whole amount, due in the loan's start month.
  full('full', 'Pay in full'),

  /// Equal payments over a number of months, from the start month.
  monthly('monthly', 'Monthly');

  const LoanPlan(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static LoanPlan fromDb(String value) {
    for (final p in LoanPlan.values) {
      if (p.dbValue == value) return p;
    }
    throw FormatException('Unknown loan plan: $value');
  }
}

int _int(Object? v, String field) {
  if (v is int) return v;
  if (v is num && v == v.roundToDouble()) return v.toInt();
  throw FormatException('Field "$field" must be a whole number');
}

int? _intOrNull(Object? v, String field) => v == null ? null : _int(v, field);

String _str(Object? v, String field) {
  if (v is String) return v;
  throw FormatException('Field "$field" must be text');
}

/// How often a bill comes around.
enum BillFrequency {
  monthly('monthly', 'Monthly', 'a month'),
  weekly('weekly', 'Weekly', 'a week'),
  daily('daily', 'Daily', 'a day'),
  once('once', 'One time', 'once');

  const BillFrequency(this.dbValue, this.label, this.per);

  final String dbValue;
  final String label;

  /// "₱500 a week", "₱3,000 once".
  final String per;

  static BillFrequency fromDb(String value) {
    for (final f in BillFrequency.values) {
      if (f.dbValue == value) return f;
    }
    throw FormatException('Unknown bill frequency: $value');
  }
}

class Bill {
  const Bill({
    this.id,
    required this.name,
    required this.amount,
    this.active = true,
    this.frequency = BillFrequency.monthly,
    this.times,
    this.startDate,
  });

  final int? id;
  final String name;

  /// Amount each time it is due, in centavos.
  final int amount;

  /// False when archived.
  final bool active;

  final BillFrequency frequency;

  /// How many times it is paid in all, or null for no end. Not used for
  /// [BillFrequency.once].
  final int? times;

  /// "yyyy-MM-dd": the first time it is due (the due date for a one-time
  /// bill). Null only for monthly bills made before schedules existed: those
  /// are due every month.
  final String? startDate;

  Bill copyWith({
    int? id,
    String? name,
    int? amount,
    bool? active,
    BillFrequency? frequency,
    int? times,
    bool clearTimes = false,
    String? startDate,
    bool clearStartDate = false,
  }) {
    return Bill(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      active: active ?? this.active,
      frequency: frequency ?? this.frequency,
      times: clearTimes ? null : (times ?? this.times),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'name': name,
      'amount': amount,
      'active': active ? 1 : 0,
      'frequency': frequency.dbValue,
      'times': times,
      'start_date': startDate,
    };
  }

  /// Rows from before schedules existed read as monthly, no end, no start.
  factory Bill.fromMap(Map<String, Object?> map) {
    final freq = map['frequency'];
    final start = map['start_date'];
    return Bill(
      id: _intOrNull(map['id'], 'id'),
      name: _str(map['name'], 'name'),
      amount: _int(map['amount'], 'amount'),
      active: _int(map['active'] ?? 1, 'active') != 0,
      frequency: freq == null
          ? BillFrequency.monthly
          : BillFrequency.fromDb(_str(freq, 'frequency')),
      times: _intOrNull(map['times'], 'times'),
      startDate: start == null ? null : _str(start, 'start_date'),
    );
  }
}

class Loan {
  const Loan({
    this.id,
    required this.name,
    required this.principal,
    required this.created,
    this.plan = LoanPlan.full,
    this.months = 1,
    required this.startMonth,
    this.photo,
    this.dueDay,
  });

  final int? id;
  final String name;

  /// Total owed when added, in centavos.
  final int principal;

  /// yyyy-MM-dd
  final String created;

  final LoanPlan plan;

  /// Number of monthly payments. Always 1 for [LoanPlan.full].
  final int months;

  /// "yyyy-MM": the due month for a full payment, or the first month of a
  /// monthly plan.
  final String startMonth;

  /// File name of a photo of the loan (agreement, IOU) in the receipts
  /// folder, or null.
  final String? photo;

  bool get hasPhoto => photo != null && photo!.isNotEmpty;

  /// Day of the month payments are due (1–31; 29–31 fall on the last day of
  /// shorter months), or null for "any day".
  final int? dueDay;

  /// Number of payments the plan has.
  int get paymentCount => plan == LoanPlan.full || months < 1 ? 1 : months;

  /// Amount due each month, rounded up to the centavo so the payments cover
  /// the total. The last payment is whatever is left.
  int get installment {
    final n = paymentCount;
    return (principal + n - 1) ~/ n;
  }

  Loan copyWith({
    int? id,
    String? name,
    int? principal,
    String? created,
    LoanPlan? plan,
    int? months,
    String? startMonth,
    String? photo,
    bool clearPhoto = false,
    int? dueDay,
    bool clearDueDay = false,
  }) {
    return Loan(
      id: id ?? this.id,
      name: name ?? this.name,
      principal: principal ?? this.principal,
      created: created ?? this.created,
      plan: plan ?? this.plan,
      months: months ?? this.months,
      startMonth: startMonth ?? this.startMonth,
      photo: clearPhoto ? null : (photo ?? this.photo),
      dueDay: clearDueDay ? null : (dueDay ?? this.dueDay),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'name': name,
      'principal': principal,
      'created': created,
      'plan': plan.dbValue,
      'months': paymentCount,
      'start_month': startMonth,
      'photo': photo,
      'due_day': dueDay,
    };
  }

  /// Rows from before repayment plans existed have no plan columns: they
  /// read as "pay in full", due in the month the loan was added.
  factory Loan.fromMap(Map<String, Object?> map) {
    final created = _str(map['created'], 'created');
    final rawPlan = map['plan'];
    final rawStart = map['start_month'];
    final rawPhoto = map['photo'];
    return Loan(
      id: _intOrNull(map['id'], 'id'),
      name: _str(map['name'], 'name'),
      principal: _int(map['principal'], 'principal'),
      created: created,
      plan: rawPlan == null
          ? LoanPlan.full
          : LoanPlan.fromDb(_str(rawPlan, 'plan')),
      months: map['months'] == null ? 1 : _int(map['months'], 'months'),
      startMonth: rawStart == null
          ? (created.length >= 7 ? created.substring(0, 7) : created)
          : _str(rawStart, 'start_month'),
      photo: rawPhoto == null ? null : _str(rawPhoto, 'photo'),
      dueDay: _intOrNull(map['due_day'], 'due_day'),
    );
  }
}

/// Money that comes in every month on a set day (salary on the 19th, an
/// allowance on the 1st). Each month it is expected until an income entry
/// linked to it is recorded in that month.
class IncomeSource {
  const IncomeSource({
    this.id,
    required this.name,
    required this.amount,
    required this.day,
    this.active = true,
  });

  final int? id;
  final String name;

  /// Expected amount each month, in centavos.
  final int amount;

  /// Day of the month it usually arrives, 1–31. In a shorter month it
  /// arrives on the last day.
  final int day;

  /// False = archived: no longer expected.
  final bool active;

  IncomeSource copyWith({
    int? id,
    String? name,
    int? amount,
    int? day,
    bool? active,
  }) {
    return IncomeSource(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      day: day ?? this.day,
      active: active ?? this.active,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'name': name,
      'amount': amount,
      'day': day,
      'active': active ? 1 : 0,
    };
  }

  factory IncomeSource.fromMap(Map<String, Object?> map) {
    return IncomeSource(
      id: _intOrNull(map['id'], 'id'),
      name: _str(map['name'], 'name'),
      amount: _int(map['amount'], 'amount'),
      day: _int(map['day'], 'day'),
      active: _int(map['active'], 'active') != 0,
    );
  }
}

/// A place people send you money: a bank or e-wallet account with its QR
/// code (a screenshot or photo kept in the receipts folder).
class PayAccount {
  const PayAccount({
    this.id,
    required this.name,
    this.details = '',
    this.photo,
  });

  final int? id;

  /// "GCash", "BPI savings".
  final String name;

  /// Free text: account name, number, notes.
  final String details;

  /// File name of the QR image, or null.
  final String? photo;

  PayAccount copyWith({
    int? id,
    String? name,
    String? details,
    String? photo,
    bool clearPhoto = false,
  }) {
    return PayAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      details: details ?? this.details,
      photo: clearPhoto ? null : (photo ?? this.photo),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'name': name,
      'details': details,
      'photo': photo,
    };
  }

  factory PayAccount.fromMap(Map<String, Object?> map) {
    final rawPhoto = map['photo'];
    return PayAccount(
      id: _intOrNull(map['id'], 'id'),
      name: _str(map['name'], 'name'),
      details: map['details'] == null ? '' : _str(map['details'], 'details'),
      photo: rawPhoto == null ? null : _str(rawPhoto, 'photo'),
    );
  }
}

/// "1st", "2nd", "3rd", "19th", "21st".
String ordinalDay(int day) {
  final mod100 = day % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${day}th';
  switch (day % 10) {
    case 1:
      return '${day}st';
    case 2:
      return '${day}nd';
    case 3:
      return '${day}rd';
    default:
      return '${day}th';
  }
}

class Entry {
  const Entry({
    this.id,
    required this.type,
    required this.amount,
    this.note = '',
    required this.date,
    this.billId,
    this.loanId,
    this.incomeId,
    this.photo,
    required this.createdAt,
  });

  final int? id;
  final EntryType type;

  /// Always positive, in centavos.
  final int amount;
  final String note;

  /// yyyy-MM-dd
  final String date;

  /// Set only when [type] is [EntryType.bill].
  final int? billId;

  /// Set only when [type] needs a loan ([EntryType.needsLoan]).
  final int? loanId;

  /// The monthly income source this income came from, or null. Only for
  /// [EntryType.income].
  final int? incomeId;

  /// File name inside the receipts folder, or null.
  final String? photo;

  /// ISO timestamp.
  final String createdAt;

  bool get hasPhoto => photo != null && photo!.isNotEmpty;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'type': type.dbValue,
      'amount': amount,
      'note': note,
      'date': date,
      'bill_id': billId,
      'loan_id': loanId,
      'income_id': incomeId,
      'photo': photo,
      'created_at': createdAt,
    };
  }

  factory Entry.fromMap(Map<String, Object?> map) {
    final photo = map['photo'];
    return Entry(
      id: _intOrNull(map['id'], 'id'),
      type: EntryType.fromDb(_str(map['type'], 'type')),
      amount: _int(map['amount'], 'amount'),
      note: map['note'] == null ? '' : _str(map['note'], 'note'),
      date: _str(map['date'], 'date'),
      billId: _intOrNull(map['bill_id'], 'bill_id'),
      loanId: _intOrNull(map['loan_id'], 'loan_id'),
      incomeId: _intOrNull(map['income_id'], 'income_id'),
      photo: photo == null ? null : _str(photo, 'photo'),
      createdAt: _str(map['created_at'], 'created_at'),
    );
  }
}
