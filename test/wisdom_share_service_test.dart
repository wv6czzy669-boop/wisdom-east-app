import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/services/wisdom_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('share card fits short, medium, and longest real wisdom', () {
    const renderer = WisdomShareCardRenderer();
    final longest = wisdoms.map((entry) => entry['text']! as String).reduce(
        (first, second) => first.length >= second.length ? first : second);

    for (final wisdom in [
      'Be still.',
      'The quiet path becomes visible when urgency loosens its grip.',
      longest,
    ]) {
      final layout = renderer.layoutFor(wisdom);
      expect(layout.textSize.width, lessThanOrEqualTo(810));
      expect(layout.textSize.height, lessThanOrEqualTo(760));
      expect(layout.fontSize, greaterThanOrEqualTo(44));
      expect(layout.lineHeight, greaterThanOrEqualTo(1.24));
      expect(layout.didExceedMaxLines, isFalse);
    }
  });

  test('share card renders an exact 1080 by 1350 PNG', () async {
    const renderer = WisdomShareCardRenderer();
    final bytes = await renderer.render('The silence remembers.');
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    expect(frame.image.width, WisdomShareCardRenderer.pixelWidth);
    expect(frame.image.height, WisdomShareCardRenderer.pixelHeight);
    expect(bytes, isNotEmpty);

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

class _RecordingRenderer extends WisdomShareCardRenderer {
  final List<String> wisdoms = [];

  @override
  Future<Uint8List> render(String wisdom) async {
    wisdoms.add(wisdom);
    return Uint8List.fromList([1, 2, 3, 4]);
  }
}
