import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../state/app_state.dart';
import 'widgets/amount_field.dart';
import 'widgets/dialogs.dart';
import 'widgets/photo_section.dart';
import 'widgets/picker_field.dart';
import 'widgets/type_selector.dart';

/// Full-screen add/edit form. Defaults to a daily spend dated today, so a
/// plain daily spend is: tap Add, type the amount, tap Save.
class QuickAddPage extends StatefulWidget {
  const QuickAddPage({
    super.key,
    this.existing,
    this.initialType,
    this.initialBillId,
    this.initialLoanId,
    this.initialAmount,
  });

  /// When set, the form edits this entry.
  final Entry? existing;
  final EntryType? initialType;
  final int? initialBillId;
  final int? initialLoanId;
  final int? initialAmount;

  @override
  State<QuickAddPage> createState() => _QuickAddPageState();
}

class _QuickAddPageState extends State<QuickAddPage> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  EntryType _type = EntryType.daily;
  int? _billId;
  int? _loanId;
  DateTime _date = DateTime.now();
  PhotoChange _photoChange = PhotoChange.keep;
  String? _newPhotoPath;
  String? _amountError;
  String? _pickError;
  bool _saving = false;

  /// The amount text the form filled in by itself (from a bill or loan).
  /// While the field still shows it, picking another bill or loan replaces
  /// it; once you type your own amount, it's left alone.
  String? _autoAmountText;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type = e.type;
      _amount.text = centavosToInput(e.amount);
      _note.text = e.note;
      _billId = e.billId;
      _loanId = e.loanId;
      if (isValidDateKey(e.date)) _date = parseDateKey(e.date);
    } else {
      _type = widget.initialType ?? EntryType.daily;
      _billId = widget.initialBillId;
      _loanId = widget.initialLoanId;
      final a = widget.initialAmount;
      if (a != null && a > 0) {
        _amount.text = centavosToInput(a);
        _autoAmountText = _amount.text;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A loan payment with no loan chosen yet: pick the loan when there is
    // only one left to pay, and fill in what's due.
    if (widget.existing == null &&
        _type == EntryType.loanPayment &&
        _loanId == null) {
      _autoPickLoan(AppScope.read(context));
    }
  }

  /// Opened with the amount already known (a Pay button) or editing: keep
  /// the keyboard closed so the photo button is in view.
  bool get _focusAmount =>
      widget.existing == null && widget.initialAmount == null;

  bool get _amountIsAuto =>
      _amount.text.trim().isEmpty || _amount.text == _autoAmountText;

  void _fillAmount(int centavos) {
    if (centavos <= 0 || !_amountIsAuto) return;
    _amount.text = centavosToInput(centavos);
    _autoAmountText = _amount.text;
    _amountError = null;
  }

  /// What to pay on [loan] now: the amount due this month, else the whole
  /// balance.
  int _suggestedLoanAmount(AppState state, Loan loan) {
    final due = state.loanDueOf(loan);
    return due > 0 ? due : state.loanBalanceOf(loan);
  }

  List<Loan> _openLoans(AppState state) => <Loan>[
        for (final l in state.loans)
          if (l.id != null &&
              (state.loanBalanceOf(l) > 0 || l.id == _loanId))
            l,
      ];

  void _autoPickLoan(AppState state) {
    final open = _openLoans(state);
    if (open.length != 1) return;
    _loanId = open.single.id;
    _fillAmount(_suggestedLoanAmount(state, open.single));
  }

  void _onLoanChosen(AppState state, int? id) {
    setState(() {
      _loanId = id;
      _pickError = null;
      final loan = state.loanById(id);
      if (loan != null && _type == EntryType.loanPayment) {
        _fillAmount(_suggestedLoanAmount(state, loan));
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existing != null;

  File? _previewFile(AppState state) {
    switch (_photoChange) {
      case PhotoChange.replace:
        final path = _newPhotoPath;
        return path == null ? null : File(path);
      case PhotoChange.remove:
        return null;
      case PhotoChange.keep:
        final e = widget.existing;
        return e == null ? null : state.photoFile(e);
    }
  }

  void _onBillChosen(AppState state, int? id) {
    setState(() {
      _billId = id;
      _pickError = null;
      final bill = state.billById(id);
      if (bill != null) _fillAmount(bill.amount);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = parseCentavos(_amount.text);
    final amountError =
        amount == null || amount <= 0 ? 'Enter an amount above ₱0' : null;
    String? pickError;
    if (_type == EntryType.bill && _billId == null) {
      pickError = 'Choose a bill';
    } else if (_type.needsLoan && _loanId == null) {
      pickError = 'Choose a loan';
    }
    setState(() {
      _amountError = amountError;
      _pickError = pickError;
    });
    if (amount == null || amountError != null || pickError != null) return;

    final state = AppScope.read(context);
    final existing = widget.existing;
    final entry = Entry(
      id: existing?.id,
      type: _type,
      amount: amount,
      note: _note.text,
      date: dateKey(_date),
      billId: _billId,
      loanId: _loanId,
      photo: existing?.photo,
      createdAt: existing?.createdAt ?? DateTime.now().toIso8601String(),
    );

    setState(() => _saving = true);
    try {
      await state.saveEntry(
        entry,
        photoChange: _photoChange,
        newPhotoPath: _newPhotoPath,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Could not save: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing
            ? 'Edit entry'
            : _type == EntryType.loanPayment
                ? 'Pay a loan'
                : 'Add entry'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          AmountField(
            controller: _amount,
            autofocus: _focusAmount,
            errorText: _amountError,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          TypeSelector(
            value: _type,
            onChanged: (t) => setState(() {
              _type = t;
              _pickError = null;
              if (t == EntryType.loanPayment && _loanId == null) {
                _autoPickLoan(state);
              } else if (t == EntryType.loanPayment) {
                final loan = state.loanById(_loanId);
                if (loan != null) {
                  _fillAmount(_suggestedLoanAmount(state, loan));
                }
              } else if (t == EntryType.bill) {
                final bill = state.billById(_billId);
                if (bill != null) _fillAmount(bill.amount);
              }
            }),
          ),
          ..._linkedPicker(state),
          const SizedBox(height: 16),
          PhotoSection(
            file: _previewFile(state),
            addLabel: _type == EntryType.loanPayment
                ? 'Add photo of payment'
                : 'Add receipt photo',
            onPicked: (path) {
              if (!mounted) return;
              setState(() {
                _photoChange = PhotoChange.replace;
                _newPhotoPath = path;
              });
            },
            onRemove: () => setState(() {
              _photoChange = PhotoChange.remove;
              _newPhotoPath = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(dayLabel(_date)),
            subtitle: const Text('Date'),
            onTap: _pickDate,
          ),
        ],
      ),
    );
  }

  List<Widget> _linkedPicker(AppState state) {
    switch (_type) {
      case EntryType.bill:
        final billChoices = <int, String>{
          for (final b in state.bills)
            if (b.id != null && (b.active || b.id == _billId)) b.id!: b.name,
        };
        return <Widget>[
          const SizedBox(height: 16),
          if (billChoices.isEmpty)
            const Text('No bills yet. Add one on the Bills tab.')
          else
            PickerField(
              label: 'Bill',
              hint: 'Choose a bill',
              value: _billId,
              choices: billChoices,
              errorText: _pickError,
              onChanged: (id) => _onBillChosen(state, id),
            ),
        ];
      case EntryType.loanPayment:
      case EntryType.loanReceived:
        final paying = _type == EntryType.loanPayment;
        final loanChoices = <int, String>{
          for (final l in paying ? _openLoans(state) : state.loans)
            if (l.id != null) l.id!: l.name,
        };
        final chosen = state.loanById(_loanId);
        return <Widget>[
          const SizedBox(height: 16),
          if (loanChoices.isEmpty)
            Text(paying && state.loans.isNotEmpty
                ? 'All loans are paid off.'
                : 'No loans yet. Add one on the Loans tab.')
          else
            PickerField(
              label: 'Loan',
              hint: 'Choose a loan',
              value: _loanId,
              choices: loanChoices,
              errorText: _pickError,
              onChanged: (id) => _onLoanChosen(state, id),
            ),
          if (paying && chosen != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _loanHint(state, chosen),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ];
      case EntryType.income:
      case EntryType.oneTime:
      case EntryType.daily:
        return const <Widget>[];
    }
  }

  /// "Due this month ₱5,000 · Balance ₱20,000"
  String _loanHint(AppState state, Loan loan) {
    final due = state.loanDueOf(loan);
    final balance = state.loanBalanceOf(loan);
    if (balance <= 0) return 'Paid off';
    final dueText = due > 0
        ? 'Due this month ${formatPeso(due)}'
        : 'Nothing due this month';
    return '$dueText · Balance ${formatPeso(balance)}';
  }
}
