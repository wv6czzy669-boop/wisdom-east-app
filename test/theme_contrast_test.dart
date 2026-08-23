import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/theme/east_design.dart';

/// EAST. 1.1 accessibility polish (Build 33): deterministic WCAG 2.1
/// contrast checks for every user-readable [EastColorScheme] text token
/// against its own main background, in both Light and Dark. Standard
/// relative-luminance contrast formula -- see
/// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance and
/// https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio.
///
/// `divider` is a decorative hairline stroke, never text -- intentionally
/// excluded from the "meaningful text" thresholds below, per this task's
/// explicit instruction not to force decorative strokes to text contrast
/// ratios.
void main() {
  double channelLuminance(int channel8Bit) {
    final c = channel8Bit / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  double relativeLuminance(Color color) {
    final argb = color.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return 0.2126 * channelLuminance(r) +
        0.7152 * channelLuminance(g) +
        0.0722 * channelLuminance(b);
  }

  double contrastRatio(Color a, Color b) {
    final l1 = relativeLuminance(a);
    final l2 = relativeLuminance(b);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  group('Light palette -- meaningful text against EastColors.background', () {
    test('ink (primary text) holds >= 4.5:1', () {
      final ratio = contrastRatio(EastColors.ink, EastColors.background);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('secondary text holds >= 4.5:1', () {
      final ratio = contrastRatio(EastColors.secondary, EastColors.background);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test(
        'hint/placeholder text holds >= 4.5:1 (Build 33 accessibility '
        'repair -- was ~2.49:1)', () {
      final ratio = contrastRatio(EastColors.hint, EastColors.background);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('utilityInk holds >= 4.5:1', () {
      final ratio = contrastRatio(EastColors.utilityInk, EastColors.background);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });
  });

  group(
      'Dark palette -- meaningful text against EastColorScheme.dark.background',
      () {
    const dark = EastColorScheme.dark;

    test('ink (primary text) holds >= 4.5:1', () {
      final ratio = contrastRatio(dark.ink, dark.background);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('secondary text holds >= 4.5:1', () {
      final ratio = contrastRatio(dark.secondary, dark.background);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test(
        'hint/placeholder text holds >= 4.5:1 (Build 33 accessibility '
        'repair -- was ~3.70:1)', () {
      final ratio = contrastRatio(dark.hint, dark.background);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('utilityInk holds >= 4.5:1', () {
      final ratio = contrastRatio(dark.utilityInk, dark.background);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });
  });

  group('Journal gated export label (Build 33 accessibility repair)', () {
    // Mirrors lib/screens/journal_screen.dart's `_takeItWithYouAction`
    // non-Keeper style exactly: `EastColors.of(context).ink.withValues(
    // alpha: 0.70)` rendered over the screen's own background, blended via
    // the same `Color.alphaBlend` compositing Flutter itself uses to paint
    // a semi-transparent foreground over an opaque background.
    const gatedAlpha = 0.70;

    test(
        'Light: the gated label holds >= 4.5:1 (was ~2.95:1 at the '
        'previous 52% alpha)', () {
      final gated = Color.alphaBlend(
        EastColors.ink.withValues(alpha: gatedAlpha),
        EastColors.background,
      );
      final ratio = contrastRatio(gated, EastColors.background);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test(
        'Dark: the gated label holds >= 4.5:1 (was ~4.09:1 at the '
        'previous 52% alpha)', () {
      const dark = EastColorScheme.dark;
      final gated = Color.alphaBlend(
        dark.ink.withValues(alpha: gatedAlpha),
        dark.background,
      );
      final ratio = contrastRatio(gated, dark.background);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test(
        'regression guard: the previous 52% alpha would fail this '
        'threshold in both palettes', () {
      const dark = EastColorScheme.dark;
      final lightOld = Color.alphaBlend(
        EastColors.ink.withValues(alpha: 0.52),
        EastColors.background,
      );
      final darkOld = Color.alphaBlend(
        dark.ink.withValues(alpha: 0.52),
        dark.background,
      );
      expect(contrastRatio(lightOld, EastColors.background), lessThan(4.5));
      expect(contrastRatio(darkOld, dark.background), lessThan(4.5));
    });

    test(
        'the gated tone stays visibly receded relative to the fully-'
        'opaque Keeper state (entitlement must remain distinguishable)', () {
      final gatedLuminance = relativeLuminance(
        Color.alphaBlend(
          EastColors.ink.withValues(alpha: gatedAlpha),
          EastColors.background,
        ),
      );
      final activeLuminance = relativeLuminance(EastColors.ink);
      // A gated (non-Keeper) label must remain visually lighter/receded
      // than the fully-opaque active-Keeper ink -- never look identical,
      // which would misrepresent entitlement state.
      expect(gatedLuminance, greaterThan(activeLuminance));
    });
  });

  test(
      'the locked background/ink/secondary tokens named in this task are '
      'pixel-unchanged', () {
    expect(EastColors.background, const Color(0xFFE2E0D9));
    expect(EastColors.ink, const Color(0xFF2C2924));
    expect(EastColorScheme.dark.background, const Color(0xFF1C1B18));
    expect(EastColorScheme.dark.ink, const Color(0xFFD8D4CB));
    expect(EastColorScheme.dark.secondary, const Color(0xFFA9A49B));
  });
}
