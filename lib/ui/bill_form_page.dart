import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/bill_schedule.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/amount_field.dart';
import 'widgets/dialogs.dart';

/// Opens the form to add a new bill.
Future<void> showNewBillForm(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const BillFormPage(),
    ),
  );
}

/// Opens the form to edit [bill].
Future<void> showEditBillForm(BuildContext context, Bill bill) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => BillFormPage(existing: bill),
    ),
  );
}

/// Add or edit a bill: name, amount each time, how often (monthly, weekly,
/// daily, one time), when it starts, and whether it stops after a number of
/// payments.
class BillFormPage extends StatefulWidget {
  const BillFormPage({super.key, this.existing});

  final Bill? existing;

  @override
  State<BillFormPage> createState() => _BillFormPageState();
}

class _BillFormPageState extends State<BillFormPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _times = TextEditingController();
  BillFrequency _frequency = BillFrequency.monthly;

  /// Null only for an old monthly bill with no start date.
  DateTime? _start = DateTime.now();
  bool _limited = false;
  bool _saving = false;
  String? _nameError;
  String? _amountError;
  String? _timesError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _name.text = b.name;
      _amount.text = centavosToInput(b.amount);
      _frequency = b.frequency;
      final start = b.startDate;
      _start = start != null && isValidDateKey(start)
          ? parseDateKey(start)
          : null;
      _limited = b.times != null;
      _times.text = b.times == null ? '' : '${b.times}';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _times.dispose();
    super.dispose();
  }

  int? get _parsedTimes {
    final n = int.tryParse(_times.text.trim());
    if (n == null || n < 1 || n > 9999) return null;
    return n;
  }

  bool get _isOnce => _frequency == BillFrequency.once;

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _start = picked);
  }

  /// Date of the last payment when the bill stops after [times] payments.
  DateTime _lastPayment(DateTime start, int times) {
    switch (_frequency) {
      case BillFrequency.monthly:
        return DateTime(start.year, start.month + times - 1, 1);
      case BillFrequency.weekly:
        return DateTime(start.year, start.month, start.day + 7 * (times - 1));
      case BillFrequency.daily:
        return DateTime(start.year, start.month, start.day + times - 1);
      case BillFrequency.once:
        return start;
    }
  }

  /// "₱500 a week, 4 times · last on Mon, 7 Dec 2026", or null.
  String? _preview() {
    final amount = parseCentavos(_amount.text);
    if (amount == null || amount <= 0) return null;
    final start = _start;
    if (_isOnce) {
      return start == null
          ? null
          : '${formatPeso(amount)} once, due ${dayLabel(start)}';
    }
    final base = '${formatPeso(amount)} ${_frequency.per}';
    if (!_limited) {
      return start == null ? '$base, every month' : '$base from ${dayLabel(start)}';
    }
    final n = _parsedTimes;
    if (n == null || start == null) return null;
    final last = _lastPayment(start, n);
    final lastText = _frequency == BillFrequency.monthly
        ? monthLabel(last)
        : dayLabel(last);
    return '$base, $n ${n == 1 ? 'time' : 'times'} · last in $lastText';
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final amount = parseCentavos(_amount.text);
    final times = _isOnce || !_limited ? null : _parsedTimes;
    final timesOk = _isOnce || !_limited || times != null;
    setState(() {
      _nameError = name.isEmpty ? 'Enter a name' : null;
      _amountError =
          amount == null || amount <= 0 ? 'Enter an amount above ₱0' : null;
      _timesError = timesOk ? null : 'Enter how many times';
    });
    if (name.isEmpty || amount == null || amount <= 0 || !timesOk) return;

    // Anything but an open-ended monthly bill needs a start date.
    var start = _start;
    if (start == null && (_frequency != BillFrequency.monthly || times != null)) {
      start = DateTime.now();
    }

    final existing = widget.existing;
    final bill = (existing ?? Bill(name: name, amount: amount)).copyWith(
      name: name,
      amount: amount,
      frequency: _frequency,
      times: times,
      clearTimes: times == null,
      startDate: start == null ? null : dateKey(start),
      clearStartDate: start == null,
    );

    setState(() => _saving = true);
    try {
      await AppScope.read(context).saveBill(bill);
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
    final theme = Theme.of(context);
    final preview = _preview();
    final start = _start;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit bill' : 'New bill'),
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
              errorText: _nameError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          AmountField(
            controller: _amount,
            label: _isOnce ? 'Amount' : 'Amount each time',
            errorText: _amountError,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          Text('How often', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final f in BillFrequency.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: _frequency == f,
                  onSelected: (_) => setState(() {
                    _frequency = f;
                    _timesError = null;
                    if (f != BillFrequency.monthly && _start == null) {
                      _start = DateTime.now();
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(start == null ? 'Every month' : dayLabel(start)),
            subtitle: Text(_isOnce
                ? 'Due date'
                : start == null
                    ? 'No start date · tap to set one'
                    : 'First payment'),
            onTap: _pickStart,
          ),
          if (!_isOnce) ...<Widget>[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _limited,
              onChanged: (v) => setState(() {
                _limited = v;
                _timesError = null;
                if (v && _start == null) _start = DateTime.now();
              }),
              title: const Text('Only a set number of times'),
              subtitle: Text(_limited
                  ? 'Stops after the last payment'
                  : 'Keeps going until you archive it'),
            ),
            if (_limited)
              TextField(
                controller: _times,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'How many times',
                  errorText: _timesError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
          ],
          if (preview != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              preview,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFeatures: tabularFigures,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Short schedule text for lists: "₱500 a week · 4 times".
String billSubtitle(Bill bill) => billScheduleLabel(bill, formatPeso);
