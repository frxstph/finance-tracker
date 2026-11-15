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
      if (a != null && a > 0) _amount.text = centavosToInput(a);
    }
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
      if (bill != null && _amount.text.trim().isEmpty) {
        _amount.text = centavosToInput(bill.amount);
      }
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
    } else if (_type == EntryType.loanPayment && _loanId == null) {
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
        title: Text(_isEditing ? 'Edit entry' : 'Add entry'),
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
            autofocus: true,
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
            }),
          ),
          ..._linkedPicker(state),
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
          const SizedBox(height: 8),
          PhotoSection(
            file: _previewFile(state),
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
        final loanChoices = <int, String>{
          for (final l in state.loans)
            if (l.id != null) l.id!: l.name,
        };
        return <Widget>[
          const SizedBox(height: 16),
          if (loanChoices.isEmpty)
            const Text('No loans yet. Add one on the Loans tab.')
          else
            PickerField(
              label: 'Loan',
              hint: 'Choose a loan',
              value: _loanId,
              choices: loanChoices,
              errorText: _pickError,
              onChanged: (id) => setState(() {
                _loanId = id;
                _pickError = null;
              }),
            ),
        ];
      case EntryType.income:
      case EntryType.oneTime:
      case EntryType.daily:
        return const <Widget>[];
    }
  }
}
