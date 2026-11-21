import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../theme.dart';

/// One choice chip per type you can pick by hand. "Loan received" only
/// shows when editing an entry of that type. Both adjustment directions
/// share one "Adjustment" chip; picking it starts as "add to cash".
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
          if (t.userSelectable || (t == value && !t.isAdjustment))
            ChoiceChip(
              avatar: Icon(iconForType(t), size: 18),
              label: Text(t.label),
              selected: t == value ||
                  (t == EntryType.adjustIn && value.isAdjustment),
              onSelected: (_) {
                if (t.isAdjustment && value.isAdjustment) return;
                onChanged(t);
              },
            ),
      ],
    );
  }
}
