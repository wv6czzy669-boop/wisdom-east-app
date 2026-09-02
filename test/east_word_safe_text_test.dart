import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/data/localized_wisdoms.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/localization/east_typography_resolver.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/widgets/east_word_safe_text.dart';

const _samples = <String, String>{
  'en': 'Some paths clear when expectation softens.',
  'tr': 'Beklenti yumuşadığında bazı yollar daha da berraklaşır.',
  'ja': '期待がやわらぐと、道がより鮮明になる。',
  'de': 'Wenn Erwartungen weicher werden, werden manche Wege klarer.',
  'fr': 'Quand les attentes s’adoucissent, certains chemins s’éclaircissent.',
  'ko': '기대가 부드러워지면 어떤 길은 더 선명해진다.',
  'zh-Hant': '當期待變得柔和，有些道路會更加清晰。',
  'ar': 'عندما تلين التوقعات تصبح بعض الطرق أكثر وضوحًا.',
  'es': 'Cuando la expectativa se suaviza, algunos caminos se aclaran.',
  'pt-BR':
      'Quando a expectativa se suaviza, alguns caminhos ficam mais claros.',
  'it': 'Quando l’attesa si ammorbidisce, alcune strade diventano più chiare.',
  'th': 'เมื่อความคาดหวังอ่อนลง เส้นทางบางสายจะชัดเจนขึ้น',
  'nl': 'Wanneer verwachting verzacht, worden sommige paden helderder.',
  'pl': 'Gdy oczekiwanie łagodnieje, niektóre drogi stają się wyraźniejsze.',
  'vi': 'Khi kỳ vọng dịu lại, một số con đường trở nên rõ ràng hơn.',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final font in EastTypographyResolver.productionFonts) {
      final loader = FontLoader(font.family)
        ..addFont(rootBundle.load(font.asset));
      await loader.load();
    }
  });

  testWidgets(
    'exact Turkish regression keeps yumuşadığında on one visual line',
    (tester) async {
      final source = _samples['tr']!;
      final style = _styleFor(const Locale('tr'));
      await _pump(
        tester,
        locale: const Locale('tr'),
        text: source,
        width: 296,
        preferredLineWidth: 192,
        textScale: 1,
        style: style,
      );

      final rendered = _renderedText(tester);
      expect(find.text(source), findsOneWidget);
      expect(_renderedSpan(rendered).semanticsLabel, source);
      _expectEveryProtectedWordStaysOnOneLine(
        rendered,
        locale: const Locale('tr'),
        width: 296,
        textScale: 1,
      );
    },
  );

  testWidgets(
    'all 15 locales remain safe at narrow widths and accessibility scale',
    (tester) async {
      for (final definition in EastLocaleRegistry.targets) {
        final source = _samples[definition.tag]!;
        final style = _styleFor(definition.locale);
        for (final screenWidth in const [320.0, 390.0, 430.0]) {
          for (final textScale in const [1.0, 1.6, 2.0]) {
            final width = screenWidth - 24;
            final preferredLineWidth =
                _revealedWisdomWidth(screenWidth, textScale);
            await _pump(
              tester,
              locale: definition.locale,
              text: source,
              width: width,
              preferredLineWidth: preferredLineWidth,
              textScale: textScale,
              style: style,
            );

            final rendered = _renderedText(tester);
            final display = _renderedSpan(rendered).text!;
            final sharedFontSize = rendered.style!.fontSize;
            final sharedLetterSpacing = rendered.style!.letterSpacing;
            expect(
              _renderedSpan(rendered).semanticsLabel,
              source,
              reason: '${definition.tag} must expose the clean source text',
            );
            expect(find.text(source), findsOneWidget, reason: definition.tag);
            expect(tester.takeException(), isNull, reason: definition.tag);

            switch (definition.script) {
              case EastScript.latin:
              case EastScript.arabic:
                expect(
                  display.replaceAll('\n', ' '),
                  source,
                  reason:
                      '${definition.tag} may only replace spaces with wraps',
                );
                _expectEveryProtectedWordStaysOnOneLine(
                  rendered,
                  locale: definition.locale,
                  width: width,
                  textScale: textScale,
                );
              case EastScript.japanese:
              case EastScript.korean:
              case EastScript.traditionalChinese:
              case EastScript.thai:
                expect(
                  display,
                  source,
                  reason: '${definition.tag} must retain native wrapping',
                );
            }

            // The accessibility fit is derived from the complete locale,
            // never from the current wisdom. Prove a completely different
            // sentence receives the exact same typography in this context.
            await _pump(
              tester,
              locale: definition.locale,
              text: _alternateSample(definition.script),
              width: width,
              preferredLineWidth: preferredLineWidth,
              textScale: textScale,
              style: style,
            );
            final alternate = _renderedText(tester);
            expect(
              alternate.style!.fontSize,
              sharedFontSize,
              reason: '${definition.tag} must not size individual wisdoms',
            );
            expect(
              alternate.style!.letterSpacing,
              sharedLetterSpacing,
              reason: '${definition.tag} must keep one shared letter spacing',
            );
          }
        }
      }
    },
  );

  testWidgets(
      'every whitespace-delimited word in all reviewed catalogs fits the '
      'shared locale style', (tester) async {
    for (final definition in EastLocaleRegistry.targets) {
      if (!_usesWhitespaceWordBoundaries(definition.script)) continue;

      final catalog = definition.tag == 'en'
          ? <String, String>{
              for (final wisdom in wisdoms)
                wisdom['id']! as String: wisdom['text']! as String,
            }
          : reviewedLocalizedWisdomCatalogs[definition.tag]!;

      expect(catalog, hasLength(wisdoms.length), reason: definition.tag);
      for (final screenWidth in const [320.0, 390.0, 430.0]) {
        for (final textScale in const [1.0, 1.6, 2.0]) {
          final width = screenWidth - 24;
          await _pump(
            tester,
            locale: definition.locale,
            text: _samples[definition.tag]!,
            width: width,
            preferredLineWidth: _revealedWisdomWidth(screenWidth, textScale),
            textScale: textScale,
            style: _styleFor(definition.locale),
          );
          final sharedStyle = _renderedText(tester).style!;

          for (final source in catalog.values) {
            for (final token in source
                .split(RegExp(r'\s+'))
                .where((word) => word.isNotEmpty)) {
              final painter = TextPainter(
                text: TextSpan(text: token, style: sharedStyle),
                textDirection:
                    EastLocaleRegistry.textDirectionFor(definition.locale),
                textScaler: TextScaler.linear(textScale),
                locale: definition.locale,
                maxLines: 1,
              )..layout();
              expect(
                painter.width,
                lessThanOrEqualTo(width + 0.01),
                reason: '${definition.tag} token "$token" must fit at '
                    '${screenWidth}pt / ${textScale}x using the shared style',
              );
            }
          }
        }
      }
    }
  });
}

String _alternateSample(EastScript script) {
  switch (script) {
    case EastScript.latin:
      return 'A different quiet sentence.';
    case EastScript.arabic:
      return 'جملة هادئة مختلفة.';
    case EastScript.japanese:
      return '別の静かな言葉。';
    case EastScript.korean:
      return '또 다른 고요한 문장.';
    case EastScript.traditionalChinese:
      return '另一句安靜的話。';
    case EastScript.thai:
      return 'อีกหนึ่งประโยคที่เงียบสงบ';
  }
}

bool _usesWhitespaceWordBoundaries(EastScript script) {
  return switch (script) {
    EastScript.latin || EastScript.arabic => true,
    EastScript.japanese ||
    EastScript.korean ||
    EastScript.traditionalChinese ||
    EastScript.thai =>
      false,
  };
}

TextStyle _styleFor(Locale locale) => EastTypographyResolver.textStyleForLocale(
      locale,
      fontSize: 38,
      fontWeight: FontWeight.w400,
      height: 1.48,
      letterSpacing: 0.5,
    );

double _revealedWisdomWidth(double screenWidth, double textScale) {
  final ritualWidth = screenWidth - 68;
  final narrowWidth = screenWidth * 0.60;
  final progress = ((textScale - 1) / 0.6).clamp(0.0, 1.0);
  return narrowWidth + (ritualWidth - narrowWidth) * progress;
}

Future<void> _pump(
  WidgetTester tester, {
  required Locale locale,
  required String text,
  required double width,
  double? preferredLineWidth,
  required double textScale,
  required TextStyle style,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: EastLocaleRegistry.runtimeSupported,
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: SizedBox(
              width: width,
              child: EastWordSafeText(
                text,
                textAlign: TextAlign.center,
                style: style,
                preferredLineWidth: preferredLineWidth,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Text _renderedText(WidgetTester tester) {
  return tester.widget<Text>(
    find.descendant(
      of: find.byType(EastWordSafeText),
      matching: find.byType(Text),
    ),
  );
}

TextSpan _renderedSpan(Text rendered) => rendered.textSpan! as TextSpan;

void _expectEveryProtectedWordStaysOnOneLine(
  Text rendered, {
  required Locale locale,
  required double width,
  required double textScale,
}) {
  final display = _renderedSpan(rendered).text!;
  final direction = EastLocaleRegistry.textDirectionFor(locale);
  final painter = TextPainter(
    text: TextSpan(text: display, style: rendered.style),
    textDirection: direction,
    textAlign: TextAlign.center,
    textScaler: TextScaler.linear(textScale),
    locale: locale,
  )..layout(maxWidth: width);

  var searchOffset = 0;
  for (final token
      in display.split(RegExp(r'\s+')).where((word) => word.isNotEmpty)) {
    final start = display.indexOf(token, searchOffset);
    final end = start + token.length;
    final firstLine = painter.getLineBoundary(TextPosition(offset: start));
    final lastLine = painter.getLineBoundary(TextPosition(offset: end - 1));
    expect(
      lastLine,
      firstLine,
      reason: '"$token" must not be divided between visual lines for '
          '${EastLocaleRegistry.canonicalTag(locale)} at ${textScale}x.',
    );
    searchOffset = end;
  }

  expect(painter.width, lessThanOrEqualTo(width + 0.01));
}
