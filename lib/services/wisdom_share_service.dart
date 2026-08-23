import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/east_design.dart';
import '../localization/east_locale_registry.dart';
import '../localization/east_typography_resolver.dart';

abstract interface class WisdomShareHandler {
  Future<void> shareWisdom({
    required String wisdom,
    required Rect sharePositionOrigin,
  });
}

typedef WisdomShareLauncher = Future<ShareResult> Function(ShareParams params);

class WisdomShareService implements WisdomShareHandler {
  WisdomShareService({
    WisdomShareCardRenderer? renderer,
    WisdomShareLauncher? shareLauncher,
  })  : _renderer = renderer ?? const WisdomShareCardRenderer(),
        _shareLauncher = shareLauncher ?? SharePlus.instance.share;

  final WisdomShareCardRenderer _renderer;
  final WisdomShareLauncher _shareLauncher;

  @override
  Future<void> shareWisdom({
    required String wisdom,
    required Rect sharePositionOrigin,
  }) async {
    final bytes = await _renderer.render(wisdom);
    await _share(bytes, sharePositionOrigin);
  }

  Future<void> shareWisdomForLocale({
    required String wisdom,
    required Rect sharePositionOrigin,
    required Locale locale,
  }) async {
    final bytes = await _renderer.renderForLocale(wisdom, locale: locale);
    await _share(bytes, sharePositionOrigin);
  }

  Future<void> _share(Uint8List bytes, Rect sharePositionOrigin) async {
    await _shareLauncher(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'image/png',
          ),
        ],
        fileNameOverrides: const ['east-wisdom.png'],
        subject: 'EAST.',
        sharePositionOrigin: sharePositionOrigin,
        downloadFallbackEnabled: false,
      ),
    );
  }
}

class WisdomShareCardLayout {
  const WisdomShareCardLayout({
    required this.fontSize,
    required this.lineHeight,
    required this.textBoxWidth,
    required this.wisdomTop,
    required this.textSize,
    required this.didExceedMaxLines,
    required this.fontFamily,
    required this.textDirection,
  });

  final double fontSize;
  final double lineHeight;
  final double textBoxWidth;
  final double wisdomTop;
  final Size textSize;
  final bool didExceedMaxLines;
  final String fontFamily;
  final TextDirection textDirection;
}

class WisdomShareCardRenderer {
  const WisdomShareCardRenderer();

  static const int pixelWidth = 1080;
  static const int pixelHeight = 1920;
  static const Color backgroundColor = EastColors.background;
  static const Color foregroundColor = EastColors.ink;
  static const String fontFamily = 'EBGaramond';

  static const double wisdomOpticalCenterY = 900;

  // Update 3: small centered line beneath the "EAST." wordmark, replacing
  // the removed bottom ritual circle. Uses `EastColors.secondary` -- the
  // same *Light* value the in-app `eastMutedTextColor` token resolves to
  // for a Light-appearance context -- at full opacity with no additional
  // `.withValues(alpha: ...)` reduction. This share card is a static
  // export artifact (see class doc comment) and is pinned to Light
  // regardless of the live app's Appearance, so it deliberately reads the
  // constant here rather than the theme-reactive `eastMutedTextColor`
  // (`theme/muted_text_color.dart`), which now requires a `BuildContext`
  // this canvas-only renderer never has.
  static const double wordmarkLineGap = 13;
  static const double wordmarkLineThickness = 1;
  // Correction: the line's width is derived from the actual rendered
  // "EAST." wordmark width (`brandPainter.width`, computed at render time)
  // rather than a fixed constant — a fixed 30px line was shorter than the
  // wordmark itself, the opposite of the approved direction ("extend a
  // little past the left and right edges of the wordmark"). This is the
  // extra width added on *each* side beyond the wordmark's own width.
  static const double wordmarkLineOverhang = 10;

  static const double _minimumWisdomBoxWidth = 620;
  static const double _maximumWisdomBoxWidth = 820;
  static const double _wisdomBoxHeight = 980;
  static const double _maximumFontSize = 92;
  static const double _minimumFontSize = 52;
  static const double _maximumLineHeight = 1.42;
  static const double _minimumLineHeight = 1.28;

  WisdomShareCardLayout layoutFor(
    String wisdom, {
    Locale locale = const Locale('en'),
  }) {
    final trimmedWisdom = wisdom.trim();
    final typography = EastTypographyResolver.forLocale(locale);
    final editorialLength = ((trimmedWisdom.length - 12) / 72).clamp(0.0, 1.0);
    final textBoxWidth = ui.lerpDouble(
      _minimumWisdomBoxWidth,
      _maximumWisdomBoxWidth,
      editorialLength,
    )!;
    var fontSize = ui.lerpDouble(
      _maximumFontSize,
      72,
      editorialLength,
    )!;
    var lineHeight = ui.lerpDouble(
      _maximumLineHeight,
      1.32,
      editorialLength,
    )!;
    TextPainter painter;

    while (true) {
      painter = _wisdomPainter(
        trimmedWisdom,
        locale: locale,
        fontSize: fontSize,
        lineHeight: lineHeight,
      )..layout(maxWidth: textBoxWidth);

      if (painter.height <= _wisdomBoxHeight && !painter.didExceedMaxLines) {
        break;
      }

      if (fontSize > _minimumFontSize) {
        fontSize = (fontSize - 2).clamp(
          _minimumFontSize,
          _maximumFontSize,
        );
        continue;
      }

      if (lineHeight > _minimumLineHeight) {
        lineHeight = (lineHeight - 0.02).clamp(
          _minimumLineHeight,
          _maximumLineHeight,
        );
        continue;
      }

      break;
    }

    return WisdomShareCardLayout(
      fontSize: fontSize,
      lineHeight: lineHeight,
      textBoxWidth: textBoxWidth,
      wisdomTop: wisdomOpticalCenterY - (painter.height / 2),
      textSize: painter.size,
      didExceedMaxLines: painter.didExceedMaxLines,
      fontFamily: typography.family,
      textDirection: EastLocaleRegistry.textDirectionFor(locale),
    );
  }

  Future<Uint8List> render(String wisdom) =>
      renderForLocale(wisdom, locale: const Locale('en'));

  Future<Uint8List> renderForLocale(
    String wisdom, {
    required Locale locale,
  }) async {
    final trimmedWisdom = wisdom.trim();
    if (trimmedWisdom.isEmpty) {
      throw ArgumentError.value(wisdom, 'wisdom', 'Wisdom cannot be empty.');
    }

    final layout = layoutFor(trimmedWisdom, locale: locale);
    if (layout.didExceedMaxLines || layout.textSize.height > _wisdomBoxHeight) {
      throw StateError('Wisdom does not fit the share card safely.');
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(
        0,
        0,
        pixelWidth.toDouble(),
        pixelHeight.toDouble(),
      ),
    );
    canvas.drawColor(backgroundColor, BlendMode.src);

    final brandPainter = TextPainter(
      text: const TextSpan(
        text: 'EAST.',
        style: TextStyle(
          color: foregroundColor,
          fontFamily: fontFamily,
          fontSize: 46,
          fontWeight: FontWeight.w400,
          letterSpacing: 2.4,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: _maximumWisdomBoxWidth);
    const brandTop = 168.0;
    brandPainter.paint(
      canvas,
      Offset(
        (pixelWidth - brandPainter.width) / 2,
        brandTop,
      ),
    );

    // Update 3A: a small, flat, centered line directly beneath the "EAST."
    // wordmark — no glow, no gradient, no rounded-capsule appearance (a
    // sharp-cornered filled rectangle, not a stroke with round caps). The
    // top edge is snapped to a whole device pixel so this thin (1px) line
    // renders as one crisp, fully-opaque row rather than an antialiased
    // blend across two rows — flatter and closer to "no glow" than a
    // sub-pixel-positioned line would be.
    final wordmarkLinePaint = Paint()
      ..color = EastColors.secondary
      ..style = PaintingStyle.fill;
    final wordmarkLineTop =
        (brandTop + brandPainter.height + wordmarkLineGap).roundToDouble();
    final wordmarkLineWidth = brandPainter.width + (wordmarkLineOverhang * 2);
    canvas.drawRect(
      Rect.fromLTWH(
        (pixelWidth - wordmarkLineWidth) / 2,
        wordmarkLineTop,
        wordmarkLineWidth,
        wordmarkLineThickness,
      ),
      wordmarkLinePaint,
    );

    final wisdomPainter = _wisdomPainter(
      trimmedWisdom,
      locale: locale,
      fontSize: layout.fontSize,
      lineHeight: layout.lineHeight,
    )..layout(maxWidth: layout.textBoxWidth);
    wisdomPainter.paint(
      canvas,
      Offset(
        (pixelWidth - wisdomPainter.width) / 2,
        layout.wisdomTop,
      ),
    );

    // Update 3B: the bottom ritual circle is removed completely — no
    // outline, no placeholder, no invisible reserved widget/paint call.

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelWidth, pixelHeight);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Wisdom share image could not be encoded.');
      }
      return data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    } finally {
      image.dispose();
    }
  }

  TextPainter _wisdomPainter(
    String wisdom, {
    required Locale locale,
    required double fontSize,
    required double lineHeight,
  }) {
    final typography = EastTypographyResolver.forLocale(locale);
    return TextPainter(
      text: TextSpan(
        text: wisdom,
        style: TextStyle(
          color: foregroundColor,
          fontFamily: typography.family,
          fontFamilyFallback: typography.fallbacks,
          fontSize: fontSize,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.8,
          height: lineHeight,
        ),
      ),
      textDirection: EastLocaleRegistry.textDirectionFor(locale),
      textAlign: TextAlign.center,
      maxLines: 14,
    );
  }
}
