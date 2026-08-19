import 'package:flutter/material.dart';

import '../../theme/east_design.dart';

/// Shared geometry for the Home top-navigation ring controls (Objects,
/// Kept).
///
/// Both controls are built from these same constants so their outer visible
/// diameter, stroke width, and color are guaranteed identical by
/// construction, rather than approximated through font glyph metrics (the
/// previous `○`/`◎` Unicode-glyph approach, which needed an estimated
/// `Transform.scale` correction to even get close to matching).
class TopNavRingGeometry {
  const TopNavRingGeometry._();

  /// The single outer diameter shared by every top-nav ring control.
  static const double outerDiameter = 22.0;

  /// The stroke width shared by every ring, and by the hamburger's bars
  /// (see `HomeTopNavBar`), so all three controls carry the same visual
  /// weight.
  static const double strokeWidth = 1.0;

  /// The even gap, on every side, between the outer ring and the inner
  /// ring of a double-ring control.
  static const double innerRingInset = 6.0;

  static const Color color = EastColors.ink;

  static double get innerDiameter => outerDiameter - (innerRingInset * 2);
}

/// Paints one or two concentric, unfilled ring outlines, centered in the
/// available space. Never draws a fill.
class TopNavRingPainter extends CustomPainter {
  const TopNavRingPainter({
    required this.ringCount,
    this.color = TopNavRingGeometry.color,
  }) : assert(
          ringCount == 1 || ringCount == 2,
          'Only single- or double-ring controls are defined.',
        );

  /// 1 for Objects (single outer ring), 2 for Kept (outer ring plus one
  /// centered inner ring).
  final int ringCount;

  /// Stroke color. Defaults to [TopNavRingGeometry.color] so every existing
  /// call site is unaffected; only the transient Kept-icon emphasis overlay
  /// (see `_KeptIconEmphasis` in `home_ritual_widgets.dart`) supplies a
  /// different value.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = TopNavRingGeometry.strokeWidth;

    final center = size.center(Offset.zero);
    canvas.drawCircle(center, TopNavRingGeometry.outerDiameter / 2, paint);
    if (ringCount == 2) {
      canvas.drawCircle(center, TopNavRingGeometry.innerDiameter / 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant TopNavRingPainter oldDelegate) {
    return oldDelegate.ringCount != ringCount || oldDelegate.color != color;
  }
}

/// Objects: a single circular ring, no fill.
class SingleRingIcon extends StatelessWidget {
  const SingleRingIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: TopNavRingGeometry.outerDiameter,
      // A stable key directly on this control's own ring `CustomPaint`, so
      // tests can locate and inspect its `painter` by key rather than by
      // walking up from a tooltip/ancestor (which broke once the tooltip
      // wrapper was removed) or calling `.single` on an unverified finder.
      // `SingleRingIcon` is only ever used for Objects, so this key is
      // unambiguous.
      child: CustomPaint(
        key: ValueKey('objects-top-nav-ring'),
        painter: TopNavRingPainter(ringCount: 1),
      ),
    );
  }
}

/// Kept: a concentric double ring (outer ring identical to Objects', plus
/// one centered inner ring), no fill.
class DoubleRingIcon extends StatelessWidget {
  const DoubleRingIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: TopNavRingGeometry.outerDiameter,
      // Only this base ring carries the key — the transient Kept-icon
      // emphasis pulse (`_KeptIconEmphasis` in `home_ritual_widgets.dart`)
      // paints a second, differently-colored `TopNavRingPainter` overlay
      // that intentionally does not share this key, so
      // `find.byKey('kept-top-nav-ring')` always finds exactly one widget
      // regardless of whether the pulse is active. `DoubleRingIcon` is
      // only ever used for Kept, so this key is unambiguous.
      child: CustomPaint(
        key: ValueKey('kept-top-nav-ring'),
        painter: TopNavRingPainter(ringCount: 2),
      ),
    );
  }
}

/// The three-horizontal-line hamburger, geometrically centered in its tap
/// target, with a stroke weight that matches `TopNavRingGeometry.strokeWidth`
/// so it carries the same visual weight as the two ring controls beside it.
class HomeTopNavBar extends StatelessWidget {
  const HomeTopNavBar({super.key});

  static const double _barLength = 18.0;
  static const double _barGap = 5.0;

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Bar(),
        SizedBox(height: _barGap),
        _Bar(),
        SizedBox(height: _barGap),
        _Bar(),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: HomeTopNavBar._barLength,
      height: TopNavRingGeometry.strokeWidth,
      color: TopNavRingGeometry.color,
    );
  }
}
