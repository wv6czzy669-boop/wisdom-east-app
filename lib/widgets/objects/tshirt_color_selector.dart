import 'package:flutter/material.dart';

import '../../data/objects_catalog.dart';

/// Two small, restrained circular controls for choosing the EAST. T-Shirt
/// color. No visible color-name text is ever shown; the uploaded swatch
/// artwork and accessibility semantics carry that meaning instead.
class TshirtColorSelector extends StatelessWidget {
  const TshirtColorSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final TshirtColor selected;
  final ValueChanged<TshirtColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ColorCircle(
          asset: ObjectsCatalog.espressoButtonAsset,
          semanticLabel: 'Espresso color',
          isSelected: selected == TshirtColor.espresso,
          onTap: () => onChanged(TshirtColor.espresso),
        ),
        const SizedBox(width: 26),
        _ColorCircle(
          asset: ObjectsCatalog.khakiButtonAsset,
          semanticLabel: 'Khaki color',
          isSelected: selected == TshirtColor.khaki,
          onTap: () => onChanged(TshirtColor.khaki),
        ),
      ],
    );
  }
}

class _ColorCircle extends StatelessWidget {
  const _ColorCircle({
    required this.asset,
    required this.semanticLabel,
    required this.isSelected,
    required this.onTap,
  });

  final String asset;
  final String semanticLabel;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38,
                height: 38,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFF4F0E8).withValues(alpha: 0.65)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(asset, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
