import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:share_plus/share_plus.dart';

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
  static const Color backgroundColor = Color(0xFF030303);
  static const Color foregroundColor = Color(0xFFF4F0E8);
  static const String fontFamily = 'CormorantGaramond';

  static const double wisdomOpticalCenterY = 900;
  static const double ritualCircleCenterY = 1740;
  static const double ritualCircleRadius = 16;

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
          fontWeight: FontWeight.w300,
          letterSpacing: 2.4,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: _maximumWisdomBoxWidth);
    brandPainter.paint(
      canvas,
      Offset(
        (pixelWidth - brandPainter.width) / 2,
        168,
      ),
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

    final ritualCirclePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..isAntiAlias = true
      ..color = foregroundColor.withValues(alpha: 0.32);
    canvas.drawCircle(
      const Offset(pixelWidth / 2, ritualCircleCenterY),
      ritualCircleRadius,
      ritualCirclePaint,
    );

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
          fontWeight: FontWeight.w300,
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
