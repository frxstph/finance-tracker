import 'models.dart';
import 'receipt_parser.dart';

/// A loan or bill a receipt might be paying.
class PaymentCandidate {
  const PaymentCandidate.loan({
    required this.id,
    required this.name,
    required this.expected,
  }) : isLoan = true;

  const PaymentCandidate.bill({
    required this.id,
    required this.name,
    required this.expected,
  }) : isLoan = false;

  final bool isLoan;
  final int id;
  final String name;

  /// What's usually paid, in centavos (the loan's due this month, or the
  /// bill's amount). 0 when unknown.
  final int expected;

  EntryType get type => isLoan ? EntryType.loanPayment : EntryType.bill;
}

/// What a receipt was matched to, and why (for the note on Check and save).
class PaymentMatch {
  const PaymentMatch(this.candidate, {required this.byName, required this.byAmount});

  final PaymentCandidate candidate;
  final bool byName;
  final bool byAmount;

  EntryType get type => candidate.type;
  int? get loanId => candidate.isLoan ? candidate.id : null;
  int? get billId => candidate.isLoan ? null : candidate.id;

  /// "Loan payment · GLoan".
  String get label =>
      '${candidate.isLoan ? 'Loan payment' : 'Bill'} · ${candidate.name}';
}

/// Words that say nothing about which loan or bill it is.
const Set<String> _generic = <String>{
  'loan', 'loans', 'bill', 'bills', 'payment', 'payments', 'monthly', 'the',
  'and', 'for', 'account', 'dues', 'due', 'fee', 'fees', 'plan', 'my', 'our',
  'pay', 'paid', 'sent', 'via', 'total', 'amount',
};

/// The words of [name] that identify it ("GLoan" → gloan; "Joint loan" →
/// joint; "Meralco bill" → meralco).
List<String> nameWords(String name) => <String>[
      for (final w in name.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
        if (w.length >= 3 && !_generic.contains(w)) w,
    ];

bool _hasWord(String text, String word) =>
    RegExp('(^|[^a-z0-9])${RegExp.escape(word)}([^a-z0-9]|\$)').hasMatch(text);

bool _amountClose(int? amount, int expected) {
  if (amount == null || expected <= 0) return false;
  final slack = expected ~/ 100 > 500 ? expected ~/ 100 : 500; // 1% or ₱5
  return (amount - expected).abs() <= slack;
}

/// Picks the loan or bill [guess] pays, or null when it isn't clear.
/// - By name: every identifying word of the loan or bill appears on the
///   receipt ("GLoan Dues" → GLoan). When several match by name, the one
///   whose usual amount matches wins; still a tie → null.
/// - By amount alone: only when the receipt says loan (or bill / biller)
///   and exactly one candidate of that kind expects this amount.
PaymentMatch? matchPayment(ReceiptGuess guess, List<PaymentCandidate> candidates) {
  if (candidates.isEmpty || guess.lines.isEmpty && guess.store == null) {
    return null;
  }
  final text = <String>[
    if (guess.store != null) guess.store!,
    ...guess.lines,
  ].join('\n').toLowerCase();

  final byName = <PaymentCandidate>[];
  for (final c in candidates) {
    final words = nameWords(c.name);
    if (words.isEmpty) continue;
    if (words.every((w) => _hasWord(text, w))) byName.add(c);
  }
  if (byName.length == 1) {
    final c = byName.single;
    return PaymentMatch(c,
        byName: true, byAmount: _amountClose(guess.amount, c.expected));
  }
  if (byName.length > 1) {
    final both =
        byName.where((c) => _amountClose(guess.amount, c.expected)).toList();
    return both.length == 1
        ? PaymentMatch(both.single, byName: true, byAmount: true)
        : null;
  }

  final saysLoan = _hasWord(text, 'loan') || _hasWord(text, 'loans');
  final saysBill = _hasWord(text, 'bill') ||
      _hasWord(text, 'biller') ||
      _hasWord(text, 'bills');
  final byAmount = <PaymentCandidate>[
    for (final c in candidates)
      if (_amountClose(guess.amount, c.expected) &&
          ((c.isLoan && saysLoan) || (!c.isLoan && saysBill)))
        c,
  ];
  if (byAmount.length == 1) {
    return PaymentMatch(byAmount.single, byName: false, byAmount: true);
  }
  return null;
}
