import 'package:flutter/material.dart';

/// A labelled dropdown of (id, name) choices, built on DropdownButton so it
/// does not depend on DropdownButtonFormField's changing parameters.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final String hint;
  final int? value;

  /// id -> display name, in display order.
  final Map<int, String> choices;
  final ValueChanged<int?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final current = value != null && choices.containsKey(value) ? value : null;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: current,
          hint: Text(hint),
          items: <DropdownMenuItem<int>>[
            for (final c in choices.entries)
              DropdownMenuItem<int>(value: c.key, child: Text(c.value)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
