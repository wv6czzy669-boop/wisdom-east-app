import 'package:flutter/material.dart';

import '../../theme/east_design.dart';

/// Shared geometry for the Home navigation mark and Kept emphasis.
class TopNavRingGeometry {
  const TopNavRingGeometry._();

  /// The Kept mark's outer diameter.
  static const double outerDiameter = 22.0;

  /// The stroke width shared by the Kept rings and the hamburger's bars
  /// (see `HomeTopNavBar`) so both controls carry the same visual weight.
  static const double strokeWidth = 1.0;

  /// The even gap, on every side, between the outer ring and the inner
  /// ring of a double-ring control.
  static const double innerRingInset = 6.0;

  static const Color color = EastColors.ink;

  static double get innerDiameter => outerDiameter - (innerRingInset * 2);
}

/// Paints Kept's concentric, unfilled ring outlines, centered in the
/// available space.
class TopNavRingPainter extends CustomPainter {
  const TopNavRingPainter({this.color = TopNavRingGeometry.color});

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
    canvas.drawCircle(center, TopNavRingGeometry.innerDiameter / 2, paint);
  }

  @override
  bool shouldRepaint(covariant TopNavRingPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Kept: a concentric double ring, no fill.
class DoubleRingIcon extends StatelessWidget {
  const DoubleRingIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: TopNavRingGeometry.outerDiameter,
      // Only this base ring carries the key — the transient Kept-icon
      // emphasis pulse (`_KeptIconEmphasis` in `home_ritual_widgets.dart`)
      // paints a second, differently-colored `TopNavRingPainter` overlay
      // that intentionally does not share this key, so
      // `find.byKey('kept-top-nav-ring')` always finds exactly one widget
      // regardless of whether the pulse is active. `DoubleRingIcon` is
      // only ever used for Kept, so this key is unambiguous.
      //
      // The color is resolved explicitly from the current Appearance
      // (rather than relying on `TopNavRingPainter`'s own default, which
      // stays pinned to `TopNavRingGeometry.color` for any caller that
      // never supplies one) so Kept's ring stays visible in Dark Mode.
      child: CustomPaint(
        key: const ValueKey('kept-top-nav-ring'),
        painter: TopNavRingPainter(color: EastColors.of(context).ink),
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
    final color = EastColors.of(context).ink;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Bar(color: color),
        const SizedBox(height: _barGap),
        _Bar(color: color),
        const SizedBox(height: _barGap),
        _Bar(color: color),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: HomeTopNavBar._barLength,
      height: TopNavRingGeometry.strokeWidth,
      color: color,
    );
  }
}
