import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/services/wisdom_share_service.dart';
import 'package:wisdom_app/theme/east_design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'a Kept share cannot appear after its writing session expires during rendering',
      () async {
    final renderer = _DelayedRenderer();
    var allowed = true;
    var shares = 0;
    final service = WisdomShareService(
        renderer: renderer,
        shareLauncher: (_) async {
          shares++;
          return const ShareResult('', ShareResultStatus.success);
        });
    final pending = service.shareWisdomForLocale(
      wisdom: 'A privately kept wisdom.',
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
      locale: const Locale('en'),
      mayPresent: () => allowed,
    );
    allowed = false;
    renderer.result.complete(Uint8List.fromList([1, 2, 3]));
    await pending;
    expect(shares, 0);
  });

  test('share card safely typesets every real wisdom', () {
    const renderer = WisdomShareCardRenderer();
    final longest = wisdoms.map((entry) => entry['text']! as String).reduce(
        (first, second) => first.length >= second.length ? first : second);

    final realWisdoms =
        wisdoms.map((entry) => entry['text']! as String).toList();
    final layouts = realWisdoms.map(renderer.layoutFor).toList();

    for (final layout in layouts) {
      expect(layout.textSize.width, lessThanOrEqualTo(layout.textBoxWidth));
      expect(layout.textSize.height, lessThanOrEqualTo(980));
      expect(layout.fontSize, greaterThanOrEqualTo(52));
      expect(layout.lineHeight, greaterThanOrEqualTo(1.28));
      expect(layout.didExceedMaxLines, isFalse);
      expect(
        layout.wisdomTop + (layout.textSize.height / 2),
        WisdomShareCardRenderer.wisdomOpticalCenterY,
      );
    }

    final shortLayout = renderer.layoutFor('Be still.');
    final longLayout = renderer.layoutFor(longest);
    expect(shortLayout.textBoxWidth, lessThan(longLayout.textBoxWidth));
    expect(shortLayout.fontSize, greaterThan(longLayout.fontSize));
    expect(shortLayout.lineHeight, greaterThan(longLayout.lineHeight));
    expect(
      WisdomShareCardRenderer.wisdomOpticalCenterY,
      lessThan(WisdomShareCardRenderer.pixelHeight / 2),
    );
  });

  test('share card renders an exact 1080 by 1920 PNG', () async {
    const renderer = WisdomShareCardRenderer();
    final bytes = await renderer.render('The silence remembers.');
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    expect(frame.image.width, WisdomShareCardRenderer.pixelWidth);
    expect(frame.image.height, WisdomShareCardRenderer.pixelHeight);
    expect(bytes, isNotEmpty);

    final pixels = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(pixels, isNotNull);
    expect(_rgbAt(pixels!, x: 0, y: 0), [226, 224, 217]);

    // Update 3B: the bottom ritual circle is gone entirely — nothing but
    // the plain background color remains at and around its former
    // location (roughly 90.6% down the 1920-tall canvas, matching the
    // removed `ritualCircleCenterY = 1740` constant).
    const formerCircleCenterY = 1740;
    const formerCircleRadius = 16;
    expect(
      _rgbAt(
        pixels,
        x: WisdomShareCardRenderer.pixelWidth ~/ 2,
        y: formerCircleCenterY,
      ),
      [226, 224, 217],
    );
    expect(
      _rgbAt(
        pixels,
        x: WisdomShareCardRenderer.pixelWidth ~/ 2 + formerCircleRadius,
        y: formerCircleCenterY,
      ),
      [226, 224, 217],
      reason: 'The former circle stroke location must now be plain '
          'background — no outline, no placeholder.',
    );

    frame.image.dispose();
    codec.dispose();
  });

  test(
      'a small centered line appears beneath "EAST." using the exact '
      'shared eastMutedTextColor token, and nothing else near the wordmark '
      'changed', () async {
    const renderer = WisdomShareCardRenderer();
    final bytes = await renderer.render('The silence remembers.');
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final pixels = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(pixels, isNotNull);

    // eastMutedTextColor = 0xFF625D54, used at full opacity (no additional
    // alpha reduction), matching the in-app "Return when the silence opens
    // again." style exactly. The exact TextPainter height of "EAST." is not
    // hardcoded here (it depends on font metrics this sandbox cannot
    // independently recompute) — instead this scans the region just below
    // the wordmark for the thin, pixel-snapped line the renderer draws.
    const expectedLineRgb = [0x62, 0x5D, 0x54];
    final centerX = WisdomShareCardRenderer.pixelWidth ~/ 2;
    final matchingRows = <int>[];
    for (var y = 168; y < 168 + 150; y++) {
      if (_rgbAt(pixels!, x: centerX, y: y).join(',') ==
          expectedLineRgb.join(',')) {
        matchingRows.add(y);
      }
    }

    expect(
      matchingRows,
      isNotEmpty,
      reason: 'No row beneath the "EAST." wordmark used the exact '
          'eastMutedTextColor token — the line appears to be missing.',
    );
    expect(
      matchingRows.length,
      lessThanOrEqualTo(2),
      reason: 'The wordmark line must be thin (~1px), not a thick block.',
    );
    expect(
      _rgbAt(pixels!, x: centerX, y: matchingRows.first - 3),
      isNot(expectedLineRgb),
      reason: 'The area just above the line must not also be the line '
          'color — it must be a real thin line, not a wide band.',
    );

    // Correction: the line must now extend a little past the left and
    // right edges of the "EAST." wordmark above it, rather than being
    // shorter than the wordmark. Find the line's own full horizontal
    // extent at its row, and separately find the wordmark's widest row
    // (scanning every row between the wordmark's top and the line, since
    // the exact glyph height/metrics are not hardcoded here), then compare.
    final lineY = matchingRows.first;
    int? lineLeft, lineRight;
    for (var x = 0; x < WisdomShareCardRenderer.pixelWidth; x++) {
      if (_rgbAt(pixels, x: x, y: lineY).join(',') ==
          expectedLineRgb.join(',')) {
        lineLeft ??= x;
        lineRight = x;
      }
    }
    expect(lineLeft, isNotNull);
    expect(lineRight, isNotNull);
    final lineWidth = lineRight! - lineLeft! + 1;

    var wordmarkLeft = WisdomShareCardRenderer.pixelWidth;
    var wordmarkRight = 0;
    for (var y = 168; y < lineY; y++) {
      for (var x = 0; x < WisdomShareCardRenderer.pixelWidth; x++) {
        final rgb = _rgbAt(pixels, x: x, y: y);
        // Matches `foregroundColor` (0xFF2C2924) closely enough to count
        // as wordmark glyph, not background or anti-aliasing fringe.
        if (rgb[0] < 100 && rgb[1] < 100 && rgb[2] < 100) {
          if (x < wordmarkLeft) wordmarkLeft = x;
          if (x > wordmarkRight) wordmarkRight = x;
        }
      }
    }
    expect(
      wordmarkRight,
      greaterThan(wordmarkLeft),
      reason: 'Could not locate the "EAST." wordmark above the line.',
    );
    final wordmarkWidth = wordmarkRight - wordmarkLeft + 1;

    expect(
      lineWidth,
      greaterThan(wordmarkWidth),
      reason: 'The line must now be wider than the wordmark, not shorter.',
    );
    expect(
      lineLeft,
      lessThan(wordmarkLeft),
      reason: 'The line must extend past the wordmark\'s left edge.',
    );
    expect(
      lineRight,
      greaterThan(wordmarkRight),
      reason: 'The line must extend past the wordmark\'s right edge.',
    );

    // Still centered under the wordmark (both centered on the canvas).
    final lineCenter = (lineLeft + lineRight) / 2;
    final wordmarkCenter = (wordmarkLeft + wordmarkRight) / 2;
    expect((lineCenter - wordmarkCenter).abs(), lessThan(2));

    frame.image.dispose();
    codec.dispose();
  });

  test('share service passes exact wisdom, PNG name, and valid origin',
      () async {
    final renderer = _RecordingRenderer();
    ShareParams? received;
    final service = WisdomShareService(
      renderer: renderer,
      shareLauncher: (params) async {
        received = params;
        return const ShareResult('dismissed', ShareResultStatus.dismissed);
      },
    );
    const origin = Rect.fromLTWH(40, 80, 220, 160);

    await service.shareWisdom(
      wisdom: 'Exact current wisdom.',
      sharePositionOrigin: origin,
    );

    expect(renderer.wisdoms, ['Exact current wisdom.']);
    expect(received?.fileNameOverrides, ['east-wisdom.png']);
    expect(received?.subject, 'EAST.');
    expect(received?.text, isNull);
    expect(received?.sharePositionOrigin, origin);
    expect(received?.files, hasLength(1));
    expect(await received!.files!.single.readAsBytes(), [1, 2, 3, 4]);
  });
}

List<int> _rgbAt(
  ByteData pixels, {
  required int x,
  required int y,
}) {
  final offset = (y * WisdomShareCardRenderer.pixelWidth + x) * 4;
  return [
    pixels.getUint8(offset),
    pixels.getUint8(offset + 1),
    pixels.getUint8(offset + 2),
  ];
}

class _RecordingRenderer extends WisdomShareCardRenderer {
  final List<String> wisdoms = [];

  @override
  Future<Uint8List> render(
    String wisdom, {
    EastColorScheme scheme = EastColorScheme.light,
  }) async {
    wisdoms.add(wisdom);
    return Uint8List.fromList([1, 2, 3, 4]);
  }
}

class _DelayedRenderer extends WisdomShareCardRenderer {
  final result = Completer<Uint8List>();
  @override
  Future<Uint8List> renderForLocale(
    String wisdom, {
    required Locale locale,
    EastColorScheme scheme = EastColorScheme.light,
  }) =>
      result.future;
}
