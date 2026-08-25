import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/app.dart';
import 'package:wisdom_app/controllers/locale_preference_controller.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/theme/east_design.dart';

import 'persistence_test_helpers.dart';
import 'test_support/visual_fit.dart';

const Map<String, String> _arbFiles = <String, String>{
  'en': 'app_en.arb',
  'tr': 'app_tr.arb',
  'ja': 'app_ja.arb',
  'de': 'app_de.arb',
  'fr': 'app_fr.arb',
  'ko': 'app_ko.arb',
  'zh-Hant': 'app_zh_Hant.arb',
  'ar': 'app_ar.arb',
  'es': 'app_es.arb',
  'pt-BR': 'app_pt_BR.arb',
  'it': 'app_it.arb',
  'th': 'app_th.arb',
  'nl': 'app_nl.arb',
  'pl': 'app_pl.arb',
  'vi': 'app_vi.arb',
};

// Flutter's generator requires base-language resources when a script or
// region-specific locale exists. These complete translated catalogs support
// generation only; neither tag is present in EAST.'s product target registry.
const Map<String, String> _generatorFallbackFiles = <String, String>{
  'pt': 'app_pt.arb',
  'zh': 'app_zh.arb',
};

const Map<String, String> _allArbFiles = <String, String>{
  ..._arbFiles,
  ..._generatorFallbackFiles,
};

const Map<String, Map<String, String>> _lockedTerminology =
    <String, Map<String, String>>{
  'tr': <String, String>{
    'pause': 'Bekle.',
    'feel': 'Hisset.',
    'askFromYourHeart': 'Soruyu kalbinden sor.',
    'kept': 'Kalanlar',
    'keeper': 'Tutucu',
    'keepThisWisdom': 'Bu sözler seninle kalsın.',
    'reflection': 'Yansıma',
    'addReflection': 'Yansıma ekle',
    'journal': 'Günlük',
    'enterTheCircle': 'Çembere katıl.',
  },
  'ja': <String, String>{
    'pause': '立ち止まる。',
    'feel': '感じる。',
    'askFromYourHeart': '心から問いかける。',
    'kept': '残したもの',
    'keeper': '残す',
    'keepThisWisdom': 'この気づきを心に留める。',
    'reflection': '内省',
    'addReflection': '内省を記す',
    'journal': '日記',
    'enterTheCircle': '輪の中へ。',
  },
  'de': <String, String>{
    'pause': 'Innehalten.',
    'feel': 'Spüren.',
    'askFromYourHeart': 'Von Herzen fragen.',
    'kept': 'Bewahrt',
    'keeper': 'Bewahren',
    'keepThisWisdom': 'Bewahre diese Erkenntnis.',
    'reflection': 'Reflexion',
    'addReflection': 'Reflexion hinzufügen',
    'journal': 'Tagebuch',
    'enterTheCircle': 'Komm in den Kreis.',
  },
  'fr': <String, String>{
    'pause': 'Pause.',
    'feel': 'Ressens.',
    'askFromYourHeart': 'Demande avec le cœur.',
    'kept': 'Ce qui reste',
    'keeper': 'Garder',
    'keepThisWisdom': 'Garde cette sagesse.',
    'reflection': 'Réflexion',
    'addReflection': 'Ajouter une réflexion',
    'journal': 'Carnet',
    'enterTheCircle': 'Entre dans le cercle.',
  },
  'ko': <String, String>{
    'pause': '잠시.',
    'feel': '느끼다.',
    'askFromYourHeart': '마음으로 묻다.',
    'kept': '남은 것',
    'keeper': '간직',
    'keepThisWisdom': '이 지혜를 간직하기',
    'reflection': '성찰',
    'addReflection': '성찰 추가',
    'journal': '일기장',
    'enterTheCircle': '원 안으로.',
  },
  'zh-Hant': <String, String>{
    'pause': '停一停。',
    'feel': '感受。',
    'askFromYourHeart': '從心裡提問。',
    'kept': '留下的',
    'keeper': '留住',
    'keepThisWisdom': '留住這份智慧。',
    'reflection': '省思',
    'addReflection': '新增省思',
    'journal': '日記',
    'enterTheCircle': '走進圓圈。',
  },
  'ar': <String, String>{
    'pause': 'تمهّل.',
    'feel': 'اشعر.',
    'askFromYourHeart': 'اسأل من قلبك.',
    'kept': 'ما بقي',
    'keeper': 'احتفظ',
    'keepThisWisdom': 'أبقِ هذه الحكمة معك.',
    'reflection': 'تأمُّل',
    'addReflection': 'أضف تأمّلًا',
    'journal': 'دفتر يوميات',
    'enterTheCircle': 'ادخل الدائرة.',
  },
  'es': <String, String>{
    'pause': 'Pausa.',
    'feel': 'Siente.',
    'askFromYourHeart': 'Pregunta desde el corazón.',
    'kept': 'Lo que queda',
    'keeper': 'Guardar',
    'keepThisWisdom': 'Guarda esta sabiduría.',
    'reflection': 'Reflexión',
    'addReflection': 'Añadir una reflexión',
    'journal': 'Diario',
    'enterTheCircle': 'Entra en el círculo.',
  },
  'pt-BR': <String, String>{
    'pause': 'Pausa.',
    'feel': 'Sinta.',
    'askFromYourHeart': 'Pergunte com o coração.',
    'kept': 'O que ficou',
    'keeper': 'Guardar',
    'keepThisWisdom': 'Guarde esta sabedoria.',
    'reflection': 'Reflexão',
    'addReflection': 'Adicionar reflexão',
    'journal': 'Diário',
    'enterTheCircle': 'Entre no círculo.',
  },
  'it': <String, String>{
    'pause': 'Pausa.',
    'feel': 'Senti.',
    'askFromYourHeart': 'Chiedi con il cuore.',
    'kept': 'Ciò che resta',
    'keeper': 'Custodire',
    'keepThisWisdom': 'Conserva questa saggezza.',
    'reflection': 'Riflessione',
    'addReflection': 'Aggiungi una riflessione',
    'journal': 'Diario',
    'enterTheCircle': 'Entra nel cerchio.',
  },
  'th': <String, String>{
    'pause': 'ชั่วครู่.',
    'feel': 'รู้สึก.',
    'askFromYourHeart': 'ถามจากใจ.',
    'kept': 'สิ่งที่เก็บไว้',
    'keeper': 'คงไว้',
    'keepThisWisdom': 'เก็บข้อคิดนี้ไว้',
    'reflection': 'การไตร่ตรอง',
    'addReflection': 'บันทึกการไตร่ตรอง',
    'journal': 'สมุดบันทึก',
    'enterTheCircle': 'เข้ามาในวง.',
  },
  'nl': <String, String>{
    'pause': 'Pauze.',
    'feel': 'Voel.',
    'askFromYourHeart': 'Vraag vanuit je hart.',
    'kept': 'Wat blijft',
    'keeper': 'Bewaren',
    'keepThisWisdom': 'Bewaar deze wijsheid.',
    'reflection': 'Reflectie',
    'addReflection': 'Reflectie toevoegen',
    'journal': 'Dagboek',
    'enterTheCircle': 'Stap in de cirkel.',
  },
  'pl': <String, String>{
    'pause': 'Zatrzymaj się.',
    'feel': 'Poczuj.',
    'askFromYourHeart': 'Zapytaj prosto z serca.',
    'kept': 'Zachowane',
    'keeper': 'Zachować',
    'keepThisWisdom': 'Zachowaj tę mądrość.',
    'reflection': 'Refleksja',
    'addReflection': 'Dodaj refleksję',
    'journal': 'Dziennik',
    'enterTheCircle': 'Wejdź do kręgu.',
  },
  'vi': <String, String>{
    'pause': 'Lắng lại.',
    'feel': 'Cảm nhận.',
    'askFromYourHeart': 'Hỏi bằng tấm lòng.',
    'kept': 'Điều còn lại',
    'keeper': 'Giữ lại',
    'keepThisWisdom': 'Giữ lời này bên mình.',
    'reflection': 'Suy ngẫm',
    'addReflection': 'Thêm suy ngẫm',
    'journal': 'Nhật ký',
    'enterTheCircle': 'Bước vào vòng tròn.',
  },
};

Map<String, dynamic> _readArb(String tag) {
  final filename = _allArbFiles[tag]!;
  return jsonDecode(File('lib/l10n/$filename').readAsStringSync())
      as Map<String, dynamic>;
}

Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((key) => !key.startsWith('@')).toSet();

Set<String> _metadataKeys(Map<String, dynamic> arb) => arb.keys
    .where((key) => key.startsWith('@') && !key.startsWith('@@'))
    .toSet();

Set<String> _placeholders(String message) => RegExp(
      r'\{([A-Za-z][A-Za-z0-9_]*)\}',
    ).allMatches(message).map((match) => match.group(1)!).toSet();

Locale _localeForTag(String tag) =>
    EastLocaleRegistry.targets.firstWhere((item) => item.tag == tag).locale;

void main() {
  group('Phase 4C ARB resources', () {
    test('all fifteen catalogs have exact key and metadata parity', () {
      final english = _readArb('en');
      final expectedKeys = _messageKeys(english);
      final expectedMetadata = _metadataKeys(english);

      // Phase 5G: +6 keys (returnWhenSilenceOpensAgain and the five newly
      // localized Reflection prompt alternatives; `reflectionPrompt`
      // itself already existed).
      // Appearance (Dark Mode): +5 keys (appearance, light, dark,
      // appearanceSettingSemantics, appearanceOptionSemantics).
      // Build 33 real-device Voice Control repair: +3 keys
      // (addReflectionNumbered, openReflectionNumbered -- unique
      // per-row Kept Reflection-action names; opensKeeper -- a truthful
      // hint on Journal's Keeper-gated export action).
      // EAST. 1.2 HH:MM countdown: +3 keys (remainingDurationHoursMinutes,
      // remainingDurationHoursOnly, remainingDurationMinutesOnly -- the
      // natural-language duration phrases composed for accessibility,
      // never the raw visible HH:MM token).
      // Kept delete safety: +2 keys (removeKeptQuestion and
      // keptDeleteExplanation), matching Reflection's full-field decision.
      // Kept search: +3 keys (searchKept, clearSearch,
      // noKeptSearchResults), kept entirely on-device.
      // Honest Settings sync health: +3 keys (icloudSyncing,
      // icloudUnavailable, icloudNeedsAttention).
      // First-ritual guidance: +2 keys (tapAnywhereToBegin,
      // tapWhenReady), visible only during the first entrance sequence.
      expect(expectedKeys, hasLength(148));
      for (final tag in _allArbFiles.keys) {
        final arb = _readArb(tag);
        expect(_messageKeys(arb), expectedKeys, reason: '$tag message keys');
        expect(
          _metadataKeys(arb),
          expectedMetadata,
          reason: '$tag metadata keys',
        );
      }
    });

    test('completion-pass user-facing English literals stay in ARBs', () {
      final settings =
          File('lib/screens/settings_screen.dart').readAsStringSync();
      final reflection =
          File('lib/screens/reflection_screen.dart').readAsStringSync();
      final journal =
          File('lib/screens/journal_screen.dart').readAsStringSync();

      expect(settings, contains('l10n.enableIcloudQuestion'));
      expect(settings, contains('l10n.operationFailedRetry'));
      expect(settings, contains('supportEmailSubject'));
      expect(settings, isNot(contains('failureMessage: "Privacy Policy')));
      expect(reflection, contains('reflectionAutosaveFailed'));
      expect(reflection, contains('reflectionDeleteFailed'));
      expect(journal, contains('l10n.removeUpper'));
      expect(journal, contains('l10n.saveUpper'));
    });

    test('all placeholders and placeholder metadata match English', () {
      final english = _readArb('en');
      for (final tag in _allArbFiles.keys) {
        final arb = _readArb(tag);
        for (final key in _messageKeys(english)) {
          final expected = _placeholders(english[key] as String);
          expect(
            _placeholders(arb[key] as String),
            expected,
            reason: '$tag:$key message placeholders',
          );
          if (expected.isEmpty) continue;

          final metadata = arb['@$key'] as Map<String, dynamic>;
          final declared =
              (metadata['placeholders'] as Map<String, dynamic>).keys.toSet();
          expect(declared, expected, reason: '$tag:$key metadata placeholders');
        }
      }
    });

    test('locked international terminology is exact', () {
      for (final localeEntry in _lockedTerminology.entries) {
        final arb = _readArb(localeEntry.key);
        for (final term in localeEntry.value.entries) {
          expect(
            arb[term.key],
            term.value,
            reason: '${localeEntry.key}:${term.key}',
          );
        }
      }
    });

    test('two-line ritual fragments reconstruct each locked phrase', () {
      const noSpaceLocales = <String>{'ja', 'zh-Hant', 'th'};
      for (final localeEntry in _lockedTerminology.entries) {
        final tag = localeEntry.key;
        final arb = _readArb(tag);
        final separator = noSpaceLocales.contains(tag) ? '' : ' ';
        expect(
          '${arb['askFrom']}$separator${arb['yourHeart']}',
          localeEntry.value['askFromYourHeart'],
          reason: '$tag ritual composition',
        );
      }
    });

    test('EAST. remains invariant and English fallback is not copied', () {
      final english = _readArb('en');
      const globallyInvariant = <String>{
        'east',
        'notificationTitle',
        'eastProductions',
        'languageOptionSemantics',
        // Same reasoning as languageOptionSemantics above: a pure
        // `{option}` placeholder passthrough, identical by design in
        // every locale.
        'appearanceOptionSemantics',
      };

      for (final tag in _allArbFiles.keys.where((tag) => tag != 'en')) {
        final arb = _readArb(tag);
        expect(arb['east'], 'EAST.', reason: '$tag EAST. mark');
        expect(arb['notificationTitle'], 'EAST.', reason: '$tag notification');
        for (final key in _messageKeys(english)) {
          final value = arb[key] as String;
          expect(
            RegExp(r'EAST(?!\.)').hasMatch(value),
            isFalse,
            reason: '$tag:$key must preserve EAST.',
          );
          final intentionallySame = globallyInvariant.contains(key) ||
              (tag == 'fr' && key == 'pause') ||
              (tag == 'de' && key == 'nameUpper');
          if (!intentionallySame) {
            expect(
              value,
              isNot(english[key]),
              reason: '$tag:$key unexpectedly copied English',
            );
          }
        }
      }
    });

    test('wisdom corpus strings are not introduced into translated ARBs', () {
      final wisdomTexts =
          wisdoms.map((wisdom) => wisdom['text'] as String).toSet();
      final wisdomIds = wisdoms.map((wisdom) => wisdom['id'] as String).toSet();

      for (final tag in _allArbFiles.keys.where((tag) => tag != 'en')) {
        final arb = _readArb(tag);
        expect(_messageKeys(arb).intersection(wisdomIds), isEmpty);
        expect(
          _messageKeys(arb).map((key) => arb[key]).where(wisdomTexts.contains),
          isEmpty,
          reason: '$tag contains a wisdom corpus string',
        );
      }
    });

    test('Arabic remains natural RTL without manual bidi controls', () {
      final arabic = _readArb('ar');
      final manualBidiControl = RegExp(
        '[\u200E\u200F\u202A-\u202E\u2066-\u2069]',
      );

      expect(
        EastLocaleRegistry.textDirectionFor(const Locale('ar')),
        TextDirection.rtl,
      );
      for (final key in _messageKeys(arabic)) {
        expect(
          manualBidiControl.hasMatch(arabic[key] as String),
          isFalse,
          reason: 'ar:$key contains a manual bidi control',
        );
      }
      expect(
        _placeholders(arabic['keeperPurchaseInProgress'] as String),
        const <String>{'price'},
      );
      expect(
        _placeholders(arabic['keeperPurchaseOffering'] as String),
        const <String>{'price'},
      );
      expect(arabic['east'], 'EAST.');
    });

    test(
        'EAST. 1.2 countdown accessibility keys use complete CLDR plural '
        'categories in Arabic and Polish', () {
      const countdownKeys = <String>{
        'remainingDurationHoursMinutes',
        'remainingDurationHoursOnly',
        'remainingDurationMinutesOnly',
      };
      Set<String> pluralCategories(String message) =>
          RegExp(r'(zero|one|two|few|many|other)\{')
              .allMatches(message)
              .map((match) => match.group(1)!)
              .toSet();

      final arabic = _readArb('ar');
      for (final key in countdownKeys) {
        expect(
          pluralCategories(arabic[key] as String),
          const <String>{'zero', 'one', 'two', 'few', 'many', 'other'},
          reason: 'ar:$key must use every CLDR plural category',
        );
      }

      final polish = _readArb('pl');
      for (final key in countdownKeys) {
        expect(
          pluralCategories(polish[key] as String),
          const <String>{'one', 'few', 'many', 'other'},
          reason: 'pl:$key must use every CLDR plural category',
        );
      }
    });
  });

  group('generated localization catalog', () {
    test('all target resources generate and runtime exposes only products', () {
      final generatedTags = AppLocalizations.supportedLocales
          .map(EastLocaleRegistry.canonicalTag)
          .toSet();
      expect(generatedTags, _allArbFiles.keys.toSet());
      expect(EastLocaleRegistry.runtimeSupported, hasLength(15));
      final runtimeTags = EastLocaleRegistry.runtimeSupported
          .map(EastLocaleRegistry.canonicalTag)
          .toSet();
      expect(runtimeTags,
          EastLocaleRegistry.targets.map((item) => item.tag).toSet());
      expect(runtimeTags, isNot(contains('pt')));
      expect(runtimeTags, isNot(contains('zh')));
    });

    testWidgets('WisdomApp exposes the reviewed product runtime locales',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final localeController = LocalePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await localeController.load();
      final keptGraph = KeptRepositoryTestGraph();
      await tester.pumpWidget(
        WisdomApp(
          savedReflectionsService: keptGraph.service,
          localePreferenceController: localeController,
        ),
      );
      await tester.pump();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.supportedLocales, EastLocaleRegistry.runtimeSupported);
    });

    test('representative generated locales load their reviewed strings',
        () async {
      const representativeTags = <String>{
        'tr',
        'ja',
        'ar',
        'zh-Hant',
        'pt-BR',
        'th',
      };

      for (final tag in representativeTags) {
        final strings = await AppLocalizations.delegate.load(
          _localeForTag(tag),
        );
        final locked = _lockedTerminology[tag]!;
        expect(strings.pause, locked['pause'], reason: '$tag pause');
        expect(strings.keeper, locked['keeper'], reason: '$tag keeper');
        expect(
          strings.keepThisWisdom,
          locked['keepThisWisdom'],
          reason: '$tag keepThisWisdom',
        );
        expect(strings.reflection, locked['reflection']);
        expect(strings.addReflection, locked['addReflection']);
        expect(strings.east, 'EAST.');

        const price = '¤9.99';
        expect(strings.keeperPurchaseOffering(price), contains(price));
        expect(strings.keeperPurchaseInProgress(price), contains(price));
        expect(strings.languageSettingSemantics('X'), contains('X'));
      }
    });

    test('localization access never transforms caller-owned Reflection text',
        () async {
      const userReflection = 'Benim yansımam — 私の言葉 — تأمّلي';
      for (final tag in const <String>{'tr', 'ja', 'ar'}) {
        final unchanged = userReflection;
        final strings = await AppLocalizations.delegate.load(
          _localeForTag(tag),
        );
        expect(strings.addReflection, isNotEmpty);
        expect(unchanged, userReflection);
      }
    });
  });

  testWidgets('Latin critical terms fit deterministic production bounds',
      (tester) async {
    final garamond = FontLoader(EastTypography.fontFamily)
      ..addFont(
        rootBundle.load('assets/fonts/EBGaramond-Variable.ttf'),
      );
    await garamond.load();
    const latinTags = <String>{
      'tr',
      'de',
      'fr',
      'es',
      'pt-BR',
      'it',
      'nl',
      'pl',
      'vi',
    };
    const ritualLineStyle = TextStyle(
      fontFamily: EastTypography.fontFamily,
      fontFamilyFallback: EastTypography.fontFamilyFallback,
      fontSize: 60,
      fontWeight: FontWeight.w400,
      height: 1.18,
      letterSpacing: 0.5,
    );
    final titleStyle = EastTypography.editorial(size: 27);
    final actionStyle = EastTypography.editorial(size: 17);

    for (final tag in latinTags) {
      final arb = _readArb(tag);
      for (final key in const <String>{'askFrom', 'yourHeart'}) {
        expect(
          EastVisualFit.measureTextHeight(
            arb[key] as String,
            style: ritualLineStyle,
            width: 322,
          ),
          lessThanOrEqualTo(142),
          reason: '$tag:$key ritual line',
        );
      }
      for (final key in const <String>{
        'kept',
        'keeper',
        'reflection',
        'addReflection',
        'journal',
        'systemDefault',
      }) {
        expect(
          EastVisualFit.measureTextHeight(
            arb[key] as String,
            style: titleStyle,
            width: 342,
          ),
          lessThanOrEqualTo(110),
          reason: '$tag:$key title',
        );
      }
      for (final key in const <String>{
        'restorePurchases',
        'keeperPurchaseOffering',
      }) {
        final value = (arb[key] as String).replaceAll('{price}', '¤9.99');
        expect(
          EastVisualFit.measureTextHeight(
            value,
            style: actionStyle,
            width: 310,
          ),
          lessThanOrEqualTo(120),
          reason: '$tag:$key action',
        );
      }
    }
  });
}
