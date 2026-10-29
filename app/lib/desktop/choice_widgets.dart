import 'package:flutter/material.dart';

import '../widgets/office_theme.dart';

/// A small tappable chip that shows the current value of a choice and
/// whether its options are open below it.
///
/// Bubbles on the desktop layer must not use popup menus, dropdowns or
/// tooltips: those open in the overlay, outside the bubble's hit rect, so
/// the runner's window region cuts them off, and they outlive the bubble
/// when the layer drops behind the icons. A [ValueChip] plus a
/// [ChoiceStrip] inside the bubble keeps everything in its rect.
class ValueChip extends StatelessWidget {
  const ValueChip({
    super.key,
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: PixelColors.paperLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: open ? PixelColors.ink : PixelColors.paperEdge,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: PixelText.faint,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 14,
              color: PixelColors.ink,
            ),
          ],
        ),
      ),
    );
  }
}

/// The options of an open [ValueChip], laid out inside the bubble: one
/// choice chip per value, the current one highlighted.
class ChoiceStrip extends StatelessWidget {
  const ChoiceStrip({
    super.key,
    required this.choices,
    required this.selected,
    required this.labelOf,
    required this.onChosen,
  });

  final List<String> choices;
  final String selected;
  final String Function(String) labelOf;
  final ValueChanged<String> onChosen;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final choice in choices)
          ChoiceChip(
            label: Text(labelOf(choice), style: PixelText.body),
            selected: choice == selected,
            onSelected: (_) => onChosen(choice),
            selectedColor: PixelColors.tab,
            backgroundColor: PixelColors.paperLight,
            side: const BorderSide(color: PixelColors.paperEdge),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            showCheckmark: false,
          ),
      ],
    );
  }
}
