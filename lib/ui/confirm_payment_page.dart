import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/amount_field.dart';
import 'widgets/dialogs.dart';
import 'widgets/photo_section.dart';

/// The short "confirm payment" screen behind the Pay buttons on bills and
/// loans: the amount is already filled in, you add a photo and confirm.
class ConfirmPaymentPage extends StatefulWidget {
  const ConfirmPaymentPage({
    super.key,
    required this.title,
    required this.what,
    required this.initialAmount,
    required this.buildEntry,
    this.afterLine,
    this.initialDate,
    this.photoLabel = 'Add photo of payment',
    this.confirmLabel = 'Confirm payment',
    this.doneVerb = 'Paid',
    this.dateLabel = 'Date paid',
  });

  /// App bar title, e.g. "Pay Water".
  final String title;

  /// What this payment is, e.g. "Payment 1 of 6 · Dec 2026".
  final String what;

  /// Amount shown when the screen opens, in centavos.
  final int initialAmount;

  /// Builds the entry to save from the confirmed amount and date key.
  final Entry Function(int amount, String date) buildEntry;

  /// Optional line under the amount, e.g. the balance after paying.
  final String Function(int amount)? afterLine;

  /// Date paid; defaults to today.
  final DateTime? initialDate;

  final String photoLabel;

  /// Text on the big button.
  final String confirmLabel;

  /// Start of the message shown after saving, e.g. "Paid" or "Received".
  final String doneVerb;

  /// Label under the date.
  final String dateLabel;

  @override
  State<ConfirmPaymentPage> createState() => _ConfirmPaymentPageState();
}

class _ConfirmPaymentPageState extends State<ConfirmPaymentPage> {
  final TextEditingController _amount = TextEditingController();
  bool _editingAmount = false;
  String? _amountError;
  String? _photoPath;
  late DateTime _date = widget.initialDate ?? DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAmount > 0) {
      _amount.text = centavosToInput(widget.initialAmount);
    } else {
      _editingAmount = true;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
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

  Future<void> _confirm() async {
    if (_saving) return;
    final amount = parseCentavos(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() {
        _editingAmount = true;
        _amountError = 'Enter an amount above ₱0';
      });
      return;
    }
    final state = AppScope.read(context);
    final entry = widget.buildEntry(amount, dateKey(_date));
    setState(() => _saving = true);
    try {
      await state.saveEntry(
        entry,
        photoChange:
            _photoPath == null ? PhotoChange.keep : PhotoChange.replace,
        newPhotoPath: _photoPath,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Could not save: $e');
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text('${widget.doneVerb} ${formatPeso(amount)}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = parseCentavos(_amount.text) ?? 0;
    final after = widget.afterLine;
    final photo = _photoPath == null ? null : File(_photoPath!);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          Text(
            widget.what,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (_editingAmount)
            AmountField(
              controller: _amount,
              autofocus: true,
              errorText: _amountError,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _amountError = null),
              onSubmitted: (_) {
                if (parseCentavos(_amount.text) != null) {
                  setState(() => _editingAmount = false);
                }
              },
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    formatPeso(amount),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _editingAmount = true),
                  child: const Text('Change'),
                ),
              ],
            ),
          if (after != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              after(amount),
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontFeatures: tabularFigures),
            ),
          ],
          const SizedBox(height: 24),
          PhotoSection(
            file: photo,
            addLabel: widget.photoLabel,
            onPicked: (path) {
              if (!mounted) return;
              setState(() => _photoPath = path);
            },
            onRemove: () => setState(() => _photoPath = null),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(dayLabel(_date)),
            subtitle: Text(widget.dateLabel),
            onTap: _pickDate,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _saving ? null : _confirm,
            icon: const Icon(Icons.check),
            label: Text(widget.confirmLabel),
          ),
        ),
      ),
    );
  }
}
