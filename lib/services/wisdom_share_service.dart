import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';

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
  });

  final double fontSize;
  final double lineHeight;
  final double textBoxWidth;
  final double wisdomTop;
  final Size textSize;
  final bool didExceedMaxLines;
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
  // the removed bottom ritual circle. Uses the exact same shared
  // `eastMutedTextColor` token (see `theme/muted_text_color.dart`) already
  // used, at full opacity with no additional `.withValues(alpha: ...)`
  // reduction, by the in-app "Return when the silence opens again." text
  // (`_HomePostRevealMessage` in `home_ritual_widgets.dart`).
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

  WisdomShareCardLayout layoutFor(String wisdom) {
    final trimmedWisdom = wisdom.trim();
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
    );
  }

  Future<Uint8List> render(String wisdom) async {
    final trimmedWisdom = wisdom.trim();
    if (trimmedWisdom.isEmpty) {
      throw ArgumentError.value(wisdom, 'wisdom', 'Wisdom cannot be empty.');
    }

    final layout = layoutFor(trimmedWisdom);
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
      ..color = eastMutedTextColor
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
    required double fontSize,
    required double lineHeight,
  }) {
    return TextPainter(
      text: TextSpan(
        text: wisdom,
        style: TextStyle(
          color: foregroundColor,
          fontFamily: fontFamily,
          fontSize: fontSize,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.8,
          height: lineHeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 14,
    );
  }
}
