import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Update 4 — iOS app icon replacement.
///
/// These are asset/file-based checks (not app runtime behavior): plain
/// `dart:io` existence checks plus, where a claim is about actual pixel content
/// (opacity, black canvas, centered ring), real PNG decoding via
/// `dart:ui.instantiateImageCodec` — the same mechanism
/// `wisdom_share_service_test.dart` already uses to inspect rendered
/// pixels. No brittle whole-image golden comparison is introduced; this
/// project has no existing golden-image system.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const appIconSetDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  const masterSourcePath = 'assets/icon/app_icon.png';

  test('the 1024x1024 marketing icon exists', () {
    final marketingIcon = File('$appIconSetDir/Icon-App-1024x1024@1x.png');
    expect(
      marketingIcon.existsSync(),
      isTrue,
      reason: 'Missing $appIconSetDir/Icon-App-1024x1024@1x.png',
    );
  });

  test(
      'every AppIcon entry declared in Contents.json exists on disk at its '
      'declared pixel size', () async {
    final contents = jsonDecode(
      File('$appIconSetDir/Contents.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final images = (contents['images'] as List).cast<Map<String, dynamic>>();
    expect(images, isNotEmpty);

    final checked = <String>{};
    for (final entry in images) {
      final filename = entry['filename'] as String;
      // Several idioms (iphone/ipad) legitimately share the same filename
      // at the same declared size — only decode each unique file once.
      if (!checked.add(filename)) continue;

      final size = double.parse((entry['size'] as String).split('x').first);
      final scale = double.parse(
        (entry['scale'] as String).replaceAll('x', ''),
      );
      final expectedPx = (size * scale).round();

      final file = File('$appIconSetDir/$filename');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Missing declared AppIcon file: $filename',
      );

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(
        frame.image.width,
        expectedPx,
        reason: '$filename must be exactly ${expectedPx}x$expectedPx.',
      );
      expect(frame.image.height, expectedPx);
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('every AppIcon PNG file is fully opaque (no alpha channel content)',
      () async {
    final contents = jsonDecode(
      File('$appIconSetDir/Contents.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final images = (contents['images'] as List).cast<Map<String, dynamic>>();
    final filenames = images.map((e) => e['filename'] as String).toSet();

    for (final filename in filenames) {
      final bytes = await File('$appIconSetDir/$filename').readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(pixels, isNotNull);

      // Sample corner, center, and a mid-edge point rather than every
      // pixel (this file can be up to 1024x1024) — sufficient to catch a
      // genuine alpha channel without an expensive full-image scan.
      final w = frame.image.width;
      final h = frame.image.height;
      for (final point in [
        [0, 0],
        [w - 1, 0],
        [0, h - 1],
        [w - 1, h - 1],
        [w ~/ 2, h ~/ 2],
        [w ~/ 2, 0],
      ]) {
        final offset = (point[1] * w + point[0]) * 4;
        final alpha = pixels!.getUint8(offset + 3);
        expect(
          alpha,
          255,
          reason: '$filename must be fully opaque at every sampled pixel '
              '(remove_alpha_ios) — found alpha=$alpha at $point.',
        );
      }
      frame.image.dispose();
      codec.dispose();
    }
  });

  test(
      'the master icon source is exactly 1024x1024, opaque, with a solid '
      'black canvas and a centered ring', () async {
    final bytes = await File(masterSourcePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1024);
    expect(frame.image.height, 1024);

    final pixels = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(pixels, isNotNull);

    int alphaAt(int x, int y) => pixels!.getUint8((y * 1024 + x) * 4 + 3);
    List<int> rgbAt(int x, int y) {
      final o = (y * 1024 + x) * 4;
      return [
        pixels!.getUint8(o),
        pixels.getUint8(o + 1),
        pixels.getUint8(o + 2)
      ];
    }

    // Opaque everywhere (no transparency anywhere in the final iOS icon).
    expect(alphaAt(0, 0), 255);
    expect(alphaAt(512, 512), 255);
    expect(alphaAt(1023, 1023), 255);

    // Solid black canvas away from the ring.
    expect(rgbAt(5, 5), [0, 0, 0]);
    expect(rgbAt(1018, 1018), [0, 0, 0]);
    expect(rgbAt(512, 512), [0, 0, 0], reason: 'The ring is hollow at center.');

    // A centered ring is actually present: somewhere along the vertical
    // centerline, well inside the canvas, there must be a bright
    // (near-white) pixel — proving the ring artwork was composited, not
    // merely a flat black square.
    var foundBrightPixel = false;
    for (var y = 100; y < 300; y++) {
      final rgb = rgbAt(512, y);
      if (rgb[0] > 200 && rgb[1] > 200 && rgb[2] > 200) {
        foundBrightPixel = true;
        break;
      }
    }
    expect(
      foundBrightPixel,
      isTrue,
      reason: 'No bright ring pixel found near the top of the vertical '
          'centerline — the ring artwork may be missing.',
    );

    frame.image.dispose();
    codec.dispose();
  });

  test('Android icon assets were not touched by this change', () {
    // This only proves the expected Android mipmap directories still exist
    // with their own pre-existing icons — it cannot itself prove "no
    // modification" (that is confirmed separately via `git status`), but it
    // guards against this change accidentally deleting or renaming them.
    final androidRes = Directory('android/app/src/main/res');
    expect(androidRes.existsSync(), isTrue);
    final mipmapDirs = androidRes
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.contains('mipmap'));
    expect(mipmapDirs, isNotEmpty);
  });
}
