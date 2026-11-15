import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Peso amount input: decimal keyboard, digits/commas/dot only.
class AmountField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      style: Theme.of(context)
          .textTheme
          .headlineSmall
          ?.copyWith(fontFeatures: tabularFigures),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '₱ ',
        errorText: errorText,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: onSubmitted,
      onChanged: onChanged,
    );
  }
}
