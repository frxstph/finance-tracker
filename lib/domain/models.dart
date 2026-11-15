/// Plain data classes for the finance tracker. No Flutter or sqflite imports.
library;

enum EntryType {
  income('income', 'Income'),
  bill('bill', 'Bill'),
  oneTime('one_time', 'One-time'),
  daily('daily', 'Daily'),
  loanPayment('loan_payment', 'Loan payment');

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

class Bill {
  const Bill({
    this.id,
    required this.name,
    required this.amount,
    this.active = true,
  });

  final int? id;
  final String name;

  /// Expected monthly amount in centavos.
  final int amount;

  /// False when archived.
  final bool active;

  Bill copyWith({int? id, String? name, int? amount, bool? active}) {
    return Bill(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      active: active ?? this.active,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'name': name,
      'amount': amount,
      'active': active ? 1 : 0,
    };
  }

  factory Bill.fromMap(Map<String, Object?> map) {
    return Bill(
      id: _intOrNull(map['id'], 'id'),
      name: _str(map['name'], 'name'),
      amount: _int(map['amount'], 'amount'),
      active: _int(map['active'] ?? 1, 'active') != 0,
    );
  }
}

class Loan {
  const Loan({
    this.id,
    required this.name,
    required this.principal,
    required this.created,
  });

  final int? id;
  final String name;

  /// Total owed when added, in centavos.
  final int principal;

  /// yyyy-MM-dd
  final String created;

  Loan copyWith({int? id, String? name, int? principal, String? created}) {
    return Loan(
      id: id ?? this.id,
      name: name ?? this.name,
      principal: principal ?? this.principal,
      created: created ?? this.created,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'name': name,
      'principal': principal,
      'created': created,
    };
  }

  factory Loan.fromMap(Map<String, Object?> map) {
    return Loan(
      id: _intOrNull(map['id'], 'id'),
      name: _str(map['name'], 'name'),
      principal: _int(map['principal'], 'principal'),
      created: _str(map['created'], 'created'),
    );
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

  /// Set only when [type] is [EntryType.loanPayment].
  final int? loanId;

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
      photo: photo == null ? null : _str(photo, 'photo'),
      createdAt: _str(map['created_at'], 'created_at'),
    );
  }
}
