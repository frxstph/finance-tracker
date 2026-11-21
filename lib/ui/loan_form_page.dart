import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/amount_field.dart';
import 'widgets/dialogs.dart';
import 'widgets/photo_section.dart';

/// Opens the form to add a new loan.
Future<void> showNewLoanForm(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const LoanFormPage(),
    ),
  );
}

/// Opens the form to edit [loan].
Future<void> showEditLoanForm(BuildContext context, Loan loan) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => LoanFormPage(existing: loan),
    ),
  );
}

/// Add or edit a loan: name, total owed, how it's paid back, and (for a new
/// loan) whether the money goes into this month's cash.
class LoanFormPage extends StatefulWidget {
  const LoanFormPage({super.key, this.existing});

  final Loan? existing;

  @override
  State<LoanFormPage> createState() => _LoanFormPageState();
}

class _LoanFormPageState extends State<LoanFormPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _months = TextEditingController();
  final TextEditingController _dueDay = TextEditingController();
  String? _dueDayError;
  LoanPlan _plan = LoanPlan.monthly;
  String _startMonth = monthKey(addMonths(DateTime.now(), 1));
  bool _addToCash = true;
  PhotoChange _photoChange = PhotoChange.keep;
  String? _newPhotoPath;
  bool _saving = false;
  String? _nameError;
  String? _amountError;
  String? _monthsError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final l = widget.existing;
    if (l != null) {
      _name.text = l.name;
      _amount.text = centavosToInput(l.principal);
      _plan = l.plan;
      _months.text = l.plan == LoanPlan.monthly ? '${l.months}' : '';
      _startMonth = l.startMonth;
      _dueDay.text = l.dueDay == null ? '' : '${l.dueDay}';
      _addToCash = false;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _months.dispose();
    _dueDay.dispose();
    super.dispose();
  }

  int? get _parsedMonths {
    final n = int.tryParse(_months.text.trim());
    if (n == null || n < 1 || n > 600) return null;
    return n;
  }

  void _shiftMonth(int by) {
    setState(() {
      _startMonth = monthKey(addMonths(parseMonthKey(_startMonth), by));
    });
  }

  /// "₱1,250 a month for 6 months" preview, or null when not computable yet.
  String? _preview() {
    final amount = parseCentavos(_amount.text);
    if (amount == null || amount <= 0) return null;
    if (_plan == LoanPlan.full) {
      return 'Pay ${formatPeso(amount)} in ${shortMonthLabel(_startMonth)}';
    }
    final n = _parsedMonths;
    if (n == null) return null;
    final probe = Loan(
      name: '',
      principal: amount,
      created: todayKey(),
      plan: LoanPlan.monthly,
      months: n,
      startMonth: _startMonth,
    );
    final last = monthKey(addMonths(parseMonthKey(_startMonth), n - 1));
    final span = n == 1
        ? shortMonthLabel(_startMonth)
        : '${shortMonthLabel(_startMonth)} to ${shortMonthLabel(last)}';
    return '${formatPeso(probe.installment)} a month, $span';
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final amount = parseCentavos(_amount.text);
    final months = _plan == LoanPlan.full ? 1 : _parsedMonths;
    final dueText = _dueDay.text.trim();
    final dueDay = dueText.isEmpty ? null : int.tryParse(dueText);
    final dueOk =
        dueText.isEmpty || (dueDay != null && dueDay >= 1 && dueDay <= 31);
    setState(() {
      _dueDayError = dueOk ? null : 'Enter a day from 1 to 31, or leave empty';
      _nameError = name.isEmpty ? 'Enter a name' : null;
      _amountError =
          amount == null || amount <= 0 ? 'Enter an amount above ₱0' : null;
      _monthsError = months == null ? 'Enter how many months' : null;
    });
    if (name.isEmpty ||
        amount == null ||
        amount <= 0 ||
        months == null ||
        !dueOk) {
      return;
    }

    final state = AppScope.read(context);
    final existing = widget.existing;
    final loan = existing == null
        ? Loan(
            name: name,
            principal: amount,
            created: todayKey(),
            plan: _plan,
            months: months,
            startMonth: _startMonth,
            dueDay: dueDay,
          )
        : existing.copyWith(
            dueDay: dueDay,
            clearDueDay: dueDay == null,
            name: name,
            principal: amount,
            plan: _plan,
            months: months,
            startMonth: _startMonth,
          );

    setState(() => _saving = true);
    try {
      await state.saveLoan(
        loan,
        addToCash: !_isEditing && _addToCash,
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

  File? _previewFile(AppState state) {
    switch (_photoChange) {
      case PhotoChange.replace:
        final path = _newPhotoPath;
        return path == null ? null : File(path);
      case PhotoChange.remove:
        return null;
      case PhotoChange.keep:
        final l = widget.existing;
        return l == null ? null : state.loanPhotoFile(l);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final preview = _preview();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit loan' : 'New loan'),
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
          TextField(
            controller: _name,
            autofocus: !_isEditing,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'Who or what the loan is from',
              errorText: _nameError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          AmountField(
            controller: _amount,
            label: 'Total owed',
            errorText: _amountError,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          PhotoSection(
            file: _previewFile(state),
            addLabel: 'Add photo of agreement',
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
          const SizedBox(height: 24),
          Text('How you pay it back', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final p in LoanPlan.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: _plan == p,
                  onSelected: (_) => setState(() {
                    _plan = p;
                    _monthsError = null;
                  }),
                ),
            ],
          ),
          if (_plan == LoanPlan.monthly) ...<Widget>[
            const SizedBox(height: 16),
            TextField(
              controller: _months,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: 'Number of months',
                errorText: _monthsError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 16),
          _MonthPicker(
            label: _plan == LoanPlan.full ? 'Due month' : 'First payment',
            month: _startMonth,
            onPrevious: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _dueDay,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: InputDecoration(
              labelText: 'Due day of the month (optional)',
              hintText: '5',
              helperText: 'Used to place payments in the right week',
              errorText: _dueDayError,
              border: const OutlineInputBorder(),
            ),
          ),
          if (preview != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              preview,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFeatures: tabularFigures,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (!_isEditing) ...<Widget>[
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _addToCash,
              onChanged: (v) => setState(() => _addToCash = v),
              title: const Text('Add this money to cash'),
              subtitle: const Text(
                  'Counts as money received today. Turn off for a loan you '
                  'got before you started using the app.'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthPicker extends StatelessWidget {
  const _MonthPicker({
    required this.label,
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final String month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrevious,
          ),
          Expanded(
            child: Text(
              monthLabel(parseMonthKey(month)),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
