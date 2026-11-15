import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../theme.dart';

/// Five choice chips, one per entry type.
class TypeSelector extends StatelessWidget {
  const TypeSelector({super.key, required this.value, required this.onChanged});

  final EntryType value;
  final ValueChanged<EntryType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final t in EntryType.values)
          ChoiceChip(
            avatar: Icon(iconForType(t), size: 18),
            label: Text(t.label),
            selected: t == value,
            onSelected: (_) => onChanged(t),
          ),
      ],
    );
  }
}
