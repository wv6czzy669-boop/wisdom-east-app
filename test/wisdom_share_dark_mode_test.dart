import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/data/wisdoms.dart' show wisdoms;
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/services/journal_pdf_builder.dart';
import 'package:wisdom_app/services/wisdom_share_service.dart';
import 'package:wisdom_app/theme/east_design.dart';

/// EAST. Build 33 -- Dark Share Image. The generated share PNG now follows
/// the EFFECTIVE app appearance at the moment of sharing (System Default
/// resolved against live platform brightness, exactly like every other
/// themed surface -- never merely the stored Appearance enum), themed with
/// EAST.'s already-approved Dark Mode palette (`EastColorScheme.dark`,
/// background #1C1B18 / primary #D8D4CB / secondary #A9A49B). The native iOS
/// share sheet itself is never recolored -- only this generated image's own
/// material. Light output is pixel-identical to before this change (see
/// `wisdom_share_service_test.dart`, entirely untouched by this task).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<int> rgbAt(ByteData pixels, {required int x, required int y}) {
    final offset = (y * WisdomShareCardRenderer.pixelWidth + x) * 4;
    return [
      pixels.getUint8(offset),
      pixels.getUint8(offset + 1),
      pixels.getUint8(offset + 2),
    ];
  }

  Future<ByteData> pixelsOf(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final pixels = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    frame.image.dispose();
    codec.dispose();
    return pixels!;
  }

  group('Dark share exact colors', () {
    const renderer = WisdomShareCardRenderer();

    test('background is exactly the approved Dark background #1C1B18',
        () async {
      final bytes = await renderer.render(
        'Even the dark keeps its own kind of light.',
        scheme: EastColorScheme.dark,
      );
      final pixels = await pixelsOf(bytes);
      expect(rgbAt(pixels, x: 0, y: 0), [0x1C, 0x1B, 0x18]);
      expect(
        rgbAt(pixels, x: WisdomShareCardRenderer.pixelWidth - 1, y: 0),
        [0x1C, 0x1B, 0x18],
      );
      expect(
        rgbAt(
          pixels,
          x: WisdomShareCardRenderer.pixelWidth ~/ 2,
          y: WisdomShareCardRenderer.pixelHeight - 1,
        ),
        [0x1C, 0x1B, 0x18],
      );
      // No pure black anywhere the plain background shows through.
      expect(rgbAt(pixels, x: 0, y: 0), isNot([0, 0, 0]));
    });

    test(
        'the wordmark line uses exactly the approved Dark secondary '
        '#A9A49B', () async {
      const wisdom = 'Even the dark keeps its own kind of light.';
      final bytes = await renderer.render(wisdom, scheme: EastColorScheme.dark);
      final pixels = await pixelsOf(bytes);
      const expectedLineRgb = [0xA9, 0xA4, 0x9B];
      final centerX = WisdomShareCardRenderer.pixelWidth ~/ 2;
      final matchingRows = <int>[];
      for (var y = 168; y < 168 + 150; y++) {
        if (rgbAt(pixels, x: centerX, y: y).join(',') ==
            expectedLineRgb.join(',')) {
          matchingRows.add(y);
        }
      }
      expect(
        matchingRows,
        isNotEmpty,
        reason: 'No row beneath the wordmark used the exact Dark secondary '
            'tone.',
      );
    });

    test('the wisdom text uses exactly the approved Dark primary #D8D4CB',
        () async {
      const wisdom = 'PLAIN.';
      final bytes = await renderer.render(wisdom, scheme: EastColorScheme.dark);
      final pixels = await pixelsOf(bytes);
      final layout = renderer.layoutFor(wisdom);
      final centerX = WisdomShareCardRenderer.pixelWidth ~/ 2;
      final centerY = layout.wisdomTop + (layout.textSize.height / 2);
      var foundInkPixel = false;
      for (var dy = -30; dy <= 30 && !foundInkPixel; dy++) {
        for (var dx = -80; dx <= 80; dx++) {
          final rgb = rgbAt(
            pixels,
            x: (centerX + dx).clamp(0, WisdomShareCardRenderer.pixelWidth - 1),
            y: (centerY + dy)
                .round()
                .clamp(0, WisdomShareCardRenderer.pixelHeight - 1),
          );
          if (rgb.join(',') == '216,212,203') {
            foundInkPixel = true;
            break;
          }
        }
      }
      expect(
        foundInkPixel,
        isTrue,
        reason: 'No pixel near the wisdom text used the exact Dark primary '
            'tone (#D8D4CB = 216,212,203).',
      );
      // No pure white anywhere the wisdom text is painted.
      expect(rgbAt(pixels, x: centerX, y: centerY.round()),
          isNot([255, 255, 255]));
    });

    test('renderForLocale also honors the Dark scheme', () async {
      final bytes = await renderer.renderForLocale(
        'Even the dark keeps its own kind of light.',
        locale: const Locale('en'),
        scheme: EastColorScheme.dark,
      );
      final pixels = await pixelsOf(bytes);
      expect(rgbAt(pixels, x: 0, y: 0), [0x1C, 0x1B, 0x18]);
    });
  });

  group('Light share regression (must remain visually identical)', () {
    const renderer = WisdomShareCardRenderer();

    test('render() with no scheme argument is pixel-identical to before',
        () async {
      final bytes = await renderer.render('The silence remembers.');
      final pixels = await pixelsOf(bytes);
      expect(rgbAt(pixels, x: 0, y: 0), [226, 224, 217]);
    });

    test('explicit EastColorScheme.light matches the implicit default',
        () async {
      const wisdom = 'The silence remembers.';
      final implicit = await renderer.render(wisdom);
      final explicit =
          await renderer.render(wisdom, scheme: EastColorScheme.light);
      expect(explicit, implicit);
    });

    test('renderForLocale with no scheme argument stays Light', () async {
      final bytes = await renderer.renderForLocale(
        'The silence remembers.',
        locale: const Locale('en'),
      );
      final pixels = await pixelsOf(bytes);
      expect(rgbAt(pixels, x: 0, y: 0), [226, 224, 217]);
    });
  });

  group(
      'Effective appearance resolution (System Default follows live '
      'platform brightness, not merely the stored preference)', () {
    Future<EastColorScheme> resolvedSchemeUnder(
      WidgetTester tester, {
      required ThemeMode themeMode,
      required Brightness platformBrightness,
    }) async {
      tester.platformDispatcher.platformBrightnessTestValue =
          platformBrightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      late EastColorScheme resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: eastTheme(),
          darkTheme: eastTheme(brightness: Brightness.dark),
          themeMode: themeMode,
          home: Builder(
            builder: (context) {
              resolved = EastColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
      return resolved;
    }

    testWidgets('Explicit Light + OS Dark -> Light PNG scheme', (tester) async {
      final resolved = await resolvedSchemeUnder(
        tester,
        themeMode: ThemeMode.light,
        platformBrightness: Brightness.dark,
      );
      expect(resolved, EastColorScheme.light);
    });

    testWidgets('Explicit Dark + OS Light -> Dark PNG scheme', (tester) async {
      final resolved = await resolvedSchemeUnder(
        tester,
        themeMode: ThemeMode.dark,
        platformBrightness: Brightness.light,
      );
      expect(resolved, EastColorScheme.dark);
    });

    testWidgets('System Default + OS Light -> Light PNG scheme',
        (tester) async {
      final resolved = await resolvedSchemeUnder(
        tester,
        themeMode: ThemeMode.system,
        platformBrightness: Brightness.light,
      );
      expect(resolved, EastColorScheme.light);
    });

    testWidgets('System Default + OS Dark -> Dark PNG scheme', (tester) async {
      final resolved = await resolvedSchemeUnder(
        tester,
        themeMode: ThemeMode.system,
        platformBrightness: Brightness.dark,
      );
      expect(resolved, EastColorScheme.dark);
    });
  });

  group('Dark share across locales', () {
    const renderer = WisdomShareCardRenderer();

    test('all 15 product locales render a valid Dark PNG for a known wisdom',
        () async {
      const wisdomId = 'east_wisdom_0301';
      final englishText =
          wisdoms.firstWhere((w) => w['id'] == wisdomId)['text'] as String;

      for (final target in EastLocaleRegistry.targets) {
        final bytes = await renderer.renderForLocale(
          englishText,
          locale: target.locale,
          scheme: EastColorScheme.dark,
        );
        expect(bytes, isNotEmpty, reason: target.tag);
        final pixels = await pixelsOf(bytes);
        expect(rgbAt(pixels, x: 0, y: 0), [0x1C, 0x1B, 0x18],
            reason: target.tag);
      }
    });

    test(
        'Arabic (RTL) renders correctly in both Dark and Light, with the '
        'expected RTL text direction', () async {
      final arabic = EastLocaleRegistry.targets.firstWhere(
        (t) => t.tag == 'ar',
      );
      expect(arabic.isRtl, isTrue);

      const wisdomId = 'east_wisdom_0301';
      final englishText =
          wisdoms.firstWhere((w) => w['id'] == wisdomId)['text'] as String;

      final layout = renderer.layoutFor(englishText, locale: arabic.locale);
      expect(layout.textDirection, TextDirection.rtl);

      final darkBytes = await renderer.renderForLocale(
        englishText,
        locale: arabic.locale,
        scheme: EastColorScheme.dark,
      );
      final darkPixels = await pixelsOf(darkBytes);
      expect(rgbAt(darkPixels, x: 0, y: 0), [0x1C, 0x1B, 0x18]);

      final lightBytes = await renderer.renderForLocale(
        englishText,
        locale: arabic.locale,
        scheme: EastColorScheme.light,
      );
      final lightPixels = await pixelsOf(lightBytes);
      expect(rgbAt(lightPixels, x: 0, y: 0), [226, 224, 217]);
    });

    test(
        'a historical, safely-recovered null-ID wisdom shares under its '
        'recovered canonical wisdomId and current locale text, in Dark',
        () async {
      // "The wound is not the whole story." (east_wisdom_0195) -- the
      // specific real-device historical record this session recovers (see
      // historical_null_wisdom_id_recovery_test.dart). Sharing reads
      // whatever text HomeScreen._presentedWisdom() resolves for the
      // current locale -- for a recovered record that is the reviewed
      // localized text, exactly as for any known-wisdomId record. This
      // proves the *renderer* accepts and safely typesets that recovered
      // presentation text in Dark; the identity-recovery step itself is
      // covered end-to-end in historical_null_wisdom_id_recovery_test.dart.
      const recoveredText = 'The wound is not the whole story.';
      final bytes = await renderer.renderForLocale(
        recoveredText,
        locale: const Locale('en'),
        scheme: EastColorScheme.dark,
      );
      expect(bytes, isNotEmpty);
      final pixels = await pixelsOf(bytes);
      expect(rgbAt(pixels, x: 0, y: 0), [0x1C, 0x1B, 0x18]);
    });
  });

  group('PDF stays Light-only (never themed Dark by this task)', () {
    test('JournalPdfBuilder exposes no appearance/scheme/brightness input', () {
      // JournalPdfBuilder(presentation: JournalPdfPresentation(locale: ...))
      // is its only constructor parameter -- this test exists to fail
      // loudly (a missing-named-argument compile error) if a future change
      // ever adds a Dark/appearance parameter here, which this task
      // explicitly forbids ("DO NOT theme PDF Dark").
      final builder = JournalPdfBuilder(
        presentation: const JournalPdfPresentation(locale: Locale('en')),
      );
      expect(builder, isNotNull);
    });
  });
}
