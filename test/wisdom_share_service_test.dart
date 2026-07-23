import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/services/wisdom_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    expect(_rgbAt(pixels!, x: 0, y: 0), [3, 3, 3]);
    expect(
      _rgbAt(
        pixels,
        x: WisdomShareCardRenderer.pixelWidth ~/ 2,
        y: WisdomShareCardRenderer.ritualCircleCenterY.toInt(),
      ),
      [3, 3, 3],
    );
    final circleEdge = _rgbAt(
      pixels,
      x: WisdomShareCardRenderer.pixelWidth ~/ 2 +
          WisdomShareCardRenderer.ritualCircleRadius.toInt(),
      y: WisdomShareCardRenderer.ritualCircleCenterY.toInt(),
    );
    expect(circleEdge.first, greaterThan(3));
    expect(circleEdge.first, lessThan(244));

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
  Future<Uint8List> render(String wisdom) async {
    wisdoms.add(wisdom);
    return Uint8List.fromList([1, 2, 3, 4]);
  }
}
