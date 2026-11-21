import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/money.dart';
import '../theme.dart';

/// Peso amount input. Takes plain amounts ("1,250.50") and simple sums
/// ("450+120+35", "1500×3"). While focused it shows + − × ÷ buttons, since
/// the number keyboard may not have them, and "= ₱605" under a sum. When
/// the field loses focus, a valid sum is replaced by its total.
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.autofocus = false,
    this.errorText,
    this.onSubmitted,
    this.onChanged,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(AmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _collapseSum();
    if (mounted) setState(() {});
  }

  /// Replaces a valid sum with its total ("450+120" -> "570").
  void _collapseSum() {
    final text = widget.controller.text;
    if (!isAmountExpression(text)) return;
    final total = parseCentavos(text);
    if (total == null) return;
    final result = centavosToInput(total);
    widget.controller.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
    widget.onChanged?.call(result);
  }

  void _insert(String op) {
    final c = widget.controller;
    final text = c.text;
    final sel = c.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(start, end, op);
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + op.length),
    );
    widget.onChanged?.call(next);
  }

  /// "= ₱605" under a sum, or a hint when the sum is not finished.
  String? _helper() {
    final text = widget.controller.text;
    if (!isAmountExpression(text)) return null;
    final total = parseCentavos(text);
    return total == null ? 'Finish the sum' : '= ${formatPeso(total)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = _focus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          autofocus: widget.autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: widget.textInputAction,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+\-*/×÷ ]')),
          ],
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontFeatures: tabularFigures),
          decoration: InputDecoration(
            labelText: widget.label,
            prefixText: '₱ ',
            errorText: widget.errorText,
            helperText: widget.errorText == null ? _helper() : null,
            helperStyle: theme.textTheme.titleSmall?.copyWith(
              fontFeatures: tabularFigures,
              color: theme.colorScheme.primary,
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            _collapseSum();
            widget.onSubmitted?.call(widget.controller.text);
          },
          onChanged: widget.onChanged,
        ),
        if (focused)
          // Counted as part of the text field, so tapping a sign keeps the
          // keyboard open.
          TextFieldTapRegion(
            child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: <Widget>[
                for (final op in const <String>['+', '−', '×', '÷'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 40),
                        padding: EdgeInsets.zero,
                        textStyle: theme.textTheme.titleLarge,
                      ),
                      // The minus sign shown is "−"; the field stores "-".
                      onPressed: () => _insert(op == '−' ? '-' : op),
                      child: Text(op),
                    ),
                  ),
              ],
            ),
          ),
          ),
      ],
    );
  }
}
