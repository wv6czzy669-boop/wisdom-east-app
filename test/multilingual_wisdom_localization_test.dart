import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/data/localized_wisdoms.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/services/wisdom_localization_resolver.dart';
import 'package:wisdom_app/theme/east_design.dart';

import 'test_support/visual_fit.dart';
import 'test_support/wisdom_localization_review.dart';

Map<String, String> get _englishById => <String, String>{
      for (final wisdom in wisdoms)
        wisdom['id'] as String: wisdom['text'] as String,
    };

Locale _localeForTag(String tag) => EastLocaleRegistry.targets
    .singleWhere((definition) => definition.tag == tag)
    .locale;

bool _sourceHasDirectAddress(String source) => RegExp(
      r'\b(?:you|your|yours|yourself)\b|^(?:Begin|Choose|Do not|Let|Release|Return|Stay|Trust)\b',
      caseSensitive: false,
    ).hasMatch(source);

void main() {
  group('reviewed multilingual wisdom catalogs', () {
    test('approved and unresolved IDs exactly cover the canonical corpus', () {
      final canonicalIds = wisdoms
          .map((wisdom) => wisdom['id'] as String)
          .toList(growable: false);
      final canonicalIdSet = canonicalIds.toSet();

      expect(wisdoms, hasLength(603));
      for (final localeCatalog in reviewedLocalizedWisdomCatalogs.entries) {
        final tag = localeCatalog.key;
        final approved = localeCatalog.value;
        final unresolved = unresolvedWisdomLocalizations[tag] ??
            const <UnresolvedWisdomLocalization>[];
        final unresolvedIds =
            unresolved.map((issue) => issue.wisdomId).toList(growable: false);

        expect(approved.keys.toSet().length, approved.length, reason: tag);
        expect(unresolvedIds.toSet().length, unresolvedIds.length, reason: tag);
        expect(
            approved.keys.toSet().intersection(unresolvedIds.toSet()), isEmpty,
            reason: tag);
        expect(
          <String>{...approved.keys, ...unresolvedIds},
          canonicalIdSet,
          reason: tag,
        );
        expect(approved.length + unresolved.length, 603, reason: tag);
        if (unresolved.isEmpty) {
          expect(approved.keys.toList(), canonicalIds, reason: tag);
        }
      }
    });

    test('every approved value is non-empty, clean, valid Unicode', () {
      for (final localeCatalog in reviewedLocalizedWisdomCatalogs.entries) {
        for (final entry in localeCatalog.value.entries) {
          final reason = '${localeCatalog.key}/${entry.key}';
          expect(entry.value, isNotEmpty, reason: reason);
          expect(entry.value.trim(), entry.value, reason: reason);
          expect(entry.value, isNot(contains('\n')), reason: reason);
          expect(entry.value, isNot(contains('\uFFFD')), reason: reason);
        }
      }
    });

    test('Japanese entries are one complete Japanese sentence', () {
      final japanese = reviewedLocalizedWisdomCatalogs['ja']!;
      for (final entry in japanese.entries) {
        expect(entry.value.endsWith('。'), isTrue, reason: entry.key);
        expect('。'.allMatches(entry.value), hasLength(1), reason: entry.key);
      }
    });

    test('Korean entries are one complete Korean sentence', () {
      final korean = reviewedLocalizedWisdomCatalogs['ko']!;
      for (final entry in korean.entries) {
        expect(entry.value.endsWith('.'), isTrue, reason: entry.key);
        expect(RegExp(r'[.!?]').allMatches(entry.value), hasLength(1),
            reason: entry.key);
      }
    });

    test('Traditional Chinese entries are one complete sentence', () {
      final traditionalChinese = reviewedLocalizedWisdomCatalogs['zh-Hant']!;
      for (final entry in traditionalChinese.entries) {
        expect(entry.value.endsWith('。'), isTrue, reason: entry.key);
        expect('。'.allMatches(entry.value), hasLength(1), reason: entry.key);
      }
    });

    test('Arabic entries are one complete Arabic sentence', () {
      final arabic = reviewedLocalizedWisdomCatalogs['ar']!;
      for (final entry in arabic.entries) {
        expect(entry.value.endsWith('.'), isTrue, reason: entry.key);
        expect(RegExp(r'[.!?]').allMatches(entry.value), hasLength(1),
            reason: entry.key);
      }
    });

    test('Thai entries are complete Thai-script aphorisms', () {
      final thai = reviewedLocalizedWisdomCatalogs['th']!;
      for (final entry in thai.entries) {
        expect(RegExp(r'[ก-๙]').hasMatch(entry.value), isTrue,
            reason: entry.key);
        expect(RegExp(r'[A-Za-z]').hasMatch(entry.value), isFalse,
            reason: entry.key);
      }
    });

    test('Latin-script entries are one complete sentence', () {
      for (final tag in const <String>[
        'tr',
        'de',
        'fr',
        'es',
        'pt-BR',
        'it',
        'nl',
        'pl',
        'vi',
      ]) {
        for (final entry in reviewedLocalizedWisdomCatalogs[tag]!.entries) {
          expect(RegExp(r'[.!?]$').hasMatch(entry.value), isTrue,
              reason: '$tag/${entry.key}');
          expect(RegExp(r'[.!?]').allMatches(entry.value), hasLength(1),
              reason: '$tag/${entry.key}');
        }
      }
    });

    test('Japanese high-risk concepts have source parity', () {
      final rules = <String, RegExp>{
        '運命': RegExp(r'\bdestiny\b', caseSensitive: false),
        '宇宙': RegExp(r'\buniverse\b', caseSensitive: false),
        '活力': RegExp(r'\benergy\b', caseSensitive: false),
        '自我': RegExp(r'\bego\b', caseSensitive: false),
        '神聖': RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        '神殿': RegExp(r'\btemple\b', caseSensitive: false),
        '祈り': RegExp(r'\bprayers?\b', caseSensitive: false),
        '崇拝': RegExp(r'\bworshipping\b', caseSensitive: false),
        '慈悲': RegExp(r'\bmercy\b', caseSensitive: false),
        '恵み': RegExp(r'\b(?:grace|blessings?)\b', caseSensitive: false),
        '献身': RegExp(r'\bdevotion\b', caseSensitive: false),
        '祝福': RegExp(r'\bbless(?:ed|ing|ings)?\b', caseSensitive: false),
      };

      for (final entry in reviewedLocalizedWisdomCatalogs['ja']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!entry.value.contains(rule.key)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key}');
        }
      }

      final corpus = reviewedLocalizedWisdomCatalogs['ja']!.values.join('\n');
      expect(RegExp(r'(^|[^一-龠])神(?:様)?([^一-龠]|$)').hasMatch(corpus), isFalse,
          reason: 'Japanese introduces God where English has none');
      for (final absent in const <String>[
        '宿命',
        'カルマ',
        '波動',
        '周波数',
        '引き寄せ',
        '具現化',
        '奇跡',
        'アッラー',
      ]) {
        expect(corpus.contains(absent), isFalse, reason: absent);
      }
    });

    test('German high-risk concepts and God have source parity', () {
      final rules = <RegExp, RegExp>{
        RegExp(r'\bSchicksal\b', caseSensitive: false):
            RegExp(r'\bdestiny\b', caseSensitive: false),
        RegExp(r'\bUniversum\b', caseSensitive: false):
            RegExp(r'\buniverse\b', caseSensitive: false),
        RegExp(r'\bEnergie\b', caseSensitive: false):
            RegExp(r'\benergy\b', caseSensitive: false),
        RegExp(r'\bEgo\b', caseSensitive: false):
            RegExp(r'\bego\b', caseSensitive: false),
        RegExp(r'\bheilig\w*\b', caseSensitive: false):
            RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        RegExp(r'\bTempel\b', caseSensitive: false):
            RegExp(r'\btemple\b', caseSensitive: false),
        RegExp(r'\bGebet\w*\b', caseSensitive: false):
            RegExp(r'\bprayers?\b', caseSensitive: false),
        RegExp(r'\banbet\w*\b', caseSensitive: false):
            RegExp(r'\bworshipping\b', caseSensitive: false),
        RegExp(r'\b(?:Barmherzigkeit|Erbarmen)\b', caseSensitive: false):
            RegExp(r'\bmercy\b', caseSensitive: false),
        RegExp(r'\bGnade\b', caseSensitive: false):
            RegExp(r'\bgrace\b', caseSensitive: false),
        RegExp(r'\b(?:Segn\w*|gesegnet\w*)\b', caseSensitive: false):
            RegExp(r'\b(?:bless\w*|grace)\b', caseSensitive: false),
        RegExp(r'\bHingabe\b', caseSensitive: false):
            RegExp(r'\b(?:surrender|devotion)\b', caseSensitive: false),
        RegExp(r'\bAkzeptanz\b', caseSensitive: false):
            RegExp(r'\bacceptance\b', caseSensitive: false),
      };

      for (final entry in reviewedLocalizedWisdomCatalogs['de']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!rule.key.hasMatch(entry.value)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key.pattern}');
        }
      }

      final corpus = reviewedLocalizedWisdomCatalogs['de']!.values.join('\n');
      expect(
          RegExp(r'\b(?:Gott|Allah)\b', caseSensitive: false).hasMatch(corpus),
          isFalse,
          reason: 'German introduces God where English has none');
      for (final absent in const <String>[
        'Karma',
        'Schwingung',
        'Frequenz',
        'Manifestation',
        'Wunder',
      ]) {
        expect(corpus.toLowerCase().contains(absent.toLowerCase()), isFalse,
            reason: absent);
      }
    });

    test('German direct address has a source-semantic basis', () {
      final directAddress = RegExp(
        r'\b(?:du|dein\w*|dich|dir)\b',
        caseSensitive: false,
      );
      for (final entry in reviewedLocalizedWisdomCatalogs['de']!.entries) {
        if (!directAddress.hasMatch(entry.value)) continue;
        expect(_sourceHasDirectAddress(_englishById[entry.key]!), isTrue,
            reason: entry.key);
      }
    });

    test('French high-risk concepts, God, and direct address have parity', () {
      final rules = <RegExp, RegExp>{
        RegExp(r'(^|[^A-Za-zÀ-ÿ])destin([^A-Za-zÀ-ÿ]|$)', caseSensitive: false):
            RegExp(r'\bdestiny\b', caseSensitive: false),
        RegExp(r'\bunivers\b', caseSensitive: false):
            RegExp(r'\buniverse\b', caseSensitive: false),
        RegExp(r'\bénergie\b', caseSensitive: false):
            RegExp(r'\benergy\b', caseSensitive: false),
        RegExp(r'\bego\b', caseSensitive: false):
            RegExp(r'\bego\b', caseSensitive: false),
        RegExp(r'\bsacré\w*\b', caseSensitive: false):
            RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        RegExp(r'\btemple\b', caseSensitive: false):
            RegExp(r'\btemple\b', caseSensitive: false),
        RegExp(r'\bprière\w*\b', caseSensitive: false):
            RegExp(r'\bprayers?\b', caseSensitive: false),
        RegExp(r'\bvénér\w*\b', caseSensitive: false):
            RegExp(r'\bworshipping\b', caseSensitive: false),
        RegExp(r'\bmiséricorde\b', caseSensitive: false):
            RegExp(r'\bmercy\b', caseSensitive: false),
        RegExp(r'\bgrâce\b', caseSensitive: false):
            RegExp(r'\bgrace\b', caseSensitive: false),
        RegExp(r'\bbéni\w*\b|\bbénédiction\w*\b', caseSensitive: false):
            RegExp(r'\bbless\w*\b', caseSensitive: false),
        RegExp(r'\bdévotion\b', caseSensitive: false):
            RegExp(r'\bdevotion\b', caseSensitive: false),
        RegExp(r'\bacceptation\b', caseSensitive: false):
            RegExp(r'\bacceptance\b', caseSensitive: false),
      };
      final directAddress = RegExp(
        r'\b(?:vous|votre|vos)\b',
        caseSensitive: false,
      );

      for (final entry in reviewedLocalizedWisdomCatalogs['fr']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!rule.key.hasMatch(entry.value)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key.pattern}');
        }
        if (directAddress.hasMatch(entry.value)) {
          expect(_sourceHasDirectAddress(source), isTrue, reason: entry.key);
        }
      }

      final corpus = reviewedLocalizedWisdomCatalogs['fr']!.values.join('\n');
      expect(
          RegExp(r'\b(?:Dieu|Allah)\b', caseSensitive: false).hasMatch(corpus),
          isFalse,
          reason: 'French introduces God where English has none');
      for (final absent in const <String>[
        'karma',
        'vibration',
        'fréquence',
        'manifestation',
        'miracle',
      ]) {
        expect(corpus.toLowerCase().contains(absent), isFalse, reason: absent);
      }
    });

    test('Korean high-risk concepts, God, and direct address have parity', () {
      final rules = <RegExp, RegExp>{
        RegExp('운명'): RegExp(r'\bdestiny\b', caseSensitive: false),
        RegExp('우주'): RegExp(r'\buniverse\b', caseSensitive: false),
        RegExp('에너지'): RegExp(r'\benergy\b', caseSensitive: false),
        RegExp('자아'): RegExp(r'\bego\b', caseSensitive: false),
        RegExp('신성|거룩'): RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        RegExp('사원'): RegExp(r'\btemple\b', caseSensitive: false),
        RegExp('기도'): RegExp(r'\bprayers?\b', caseSensitive: false),
        RegExp('숭배'): RegExp(r'\bworshipping\b', caseSensitive: false),
        RegExp('자비'): RegExp(r'\bmercy\b', caseSensitive: false),
        RegExp('은총'): RegExp(r'\bgrace\b', caseSensitive: false),
        RegExp('헌신'): RegExp(r'\bdevotion\b', caseSensitive: false),
        RegExp('축복'): RegExp(r'\b(?:bless\w*|grace)\b', caseSensitive: false),
        RegExp('받아들임|수용'): RegExp(r'\bacceptance\b', caseSensitive: false),
        RegExp('내맡'): RegExp(r'\bsurrender\b', caseSensitive: false),
      };
      final directAddress = RegExp(
        r'당신|(^|\s)너(?:는|를|의|에게|와|도|가|로|만|$)|(^|\s)네(?:가|게|겐|$)',
      );

      for (final entry in reviewedLocalizedWisdomCatalogs['ko']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!rule.key.hasMatch(entry.value)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key.pattern}');
        }
        if (directAddress.hasMatch(entry.value)) {
          expect(_sourceHasDirectAddress(source), isTrue, reason: entry.key);
        }
      }

      final corpus = reviewedLocalizedWisdomCatalogs['ko']!.values.join('\n');
      expect(RegExp(r'하나님|하느님|알라').hasMatch(corpus), isFalse,
          reason: 'Korean introduces God where English has none');
      for (final absent in const <String>[
        '카르마',
        '파동',
        '주파수',
        '끌어당김',
        '기적',
      ]) {
        expect(corpus.contains(absent), isFalse, reason: absent);
      }
    });

    test(
        'Traditional Chinese high-risk concepts, God, and direct address have parity',
        () {
      final rules = <RegExp, RegExp>{
        RegExp('命運'): RegExp(r'\bdestiny\b', caseSensitive: false),
        RegExp('宇宙'): RegExp(r'\buniverse\b', caseSensitive: false),
        RegExp('能量'): RegExp(r'\benergy\b', caseSensitive: false),
        RegExp('自我'): RegExp(r'\bego\b', caseSensitive: false),
        RegExp('神聖'): RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        RegExp('殿堂'): RegExp(r'\btemple\b', caseSensitive: false),
        RegExp('祈禱'): RegExp(r'\bprayers?\b', caseSensitive: false),
        RegExp('崇拜'): RegExp(r'\bworshipping\b', caseSensitive: false),
        RegExp('慈悲'): RegExp(r'\bmercy\b', caseSensitive: false),
        RegExp('恩典'): RegExp(r'\bgrace\b', caseSensitive: false),
        RegExp('奉獻'): RegExp(r'\bdevotion\b', caseSensitive: false),
        RegExp('祝福'): RegExp(r'\b(?:bless\w*|grace)\b', caseSensitive: false),
        RegExp('接納'): RegExp(r'\bacceptance\b', caseSensitive: false),
        RegExp('臣服'): RegExp(r'\bsurrender\b', caseSensitive: false),
      };

      for (final entry in reviewedLocalizedWisdomCatalogs['zh-Hant']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!rule.key.hasMatch(entry.value)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key.pattern}');
        }
        if (RegExp('你|您').hasMatch(entry.value)) {
          expect(_sourceHasDirectAddress(source), isTrue, reason: entry.key);
        }
      }

      final corpus =
          reviewedLocalizedWisdomCatalogs['zh-Hant']!.values.join('\n');
      expect(RegExp('上帝|神明|真主|阿拉').hasMatch(corpus), isFalse,
          reason: 'Traditional Chinese introduces God where English has none');
      for (final absent in const <String>[
        '業力',
        '振動',
        '頻率',
        '吸引力法則',
        '顯化',
        '奇蹟',
      ]) {
        expect(corpus.contains(absent), isFalse, reason: absent);
      }
    });

    test('Arabic high-risk concepts, God, and direct address have parity', () {
      final rules = <RegExp, RegExp>{
        RegExp('القدر'): RegExp(r'\bdestiny\b', caseSensitive: false),
        RegExp('الكون'): RegExp(r'\buniverse\b', caseSensitive: false),
        RegExp('الطاقة'): RegExp(r'\benergy\b', caseSensitive: false),
        RegExp('الأنا'): RegExp(r'\bego\b', caseSensitive: false),
        RegExp('مقدس'): RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        RegExp('معبد'): RegExp(r'\btemple\b', caseSensitive: false),
        RegExp('دعاء|أدعية'): RegExp(r'\bprayers?\b', caseSensitive: false),
        RegExp('عبادة'): RegExp(r'\bworshipping\b', caseSensitive: false),
        RegExp('رحمة'): RegExp(r'\bmercy\b', caseSensitive: false),
        RegExp('النعمة'): RegExp(r'\bgrace\b', caseSensitive: false),
        RegExp('تفان'): RegExp(r'\bdevotion\b', caseSensitive: false),
        RegExp(r'(?:^|\s)(?:بركة|بركات|يبارك)'):
            RegExp(r'\b(?:bless\w*|grace)\b', caseSensitive: false),
        RegExp('التقبل'): RegExp(r'\bacceptance\b', caseSensitive: false),
        RegExp('التسليم'): RegExp(r'\bsurrender\b', caseSensitive: false),
      };

      for (final entry in reviewedLocalizedWisdomCatalogs['ar']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!rule.key.hasMatch(entry.value)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key.pattern}');
        }
        if (RegExp('أنت').hasMatch(entry.value)) {
          expect(_sourceHasDirectAddress(source), isTrue, reason: entry.key);
        }
      }

      final corpus = reviewedLocalizedWisdomCatalogs['ar']!.values.join('\n');
      expect(RegExp(r'(^|\s)(?:الله|الرب|الإله)(?:\s|[،.])').hasMatch(corpus),
          isFalse,
          reason: 'Arabic introduces God where English has none');
      for (final absent in const <String>[
        'كارما',
        'ذبذبات',
        'ترددات',
        'قانون الجذب',
        'معجزة',
      ]) {
        expect(corpus.contains(absent), isFalse, reason: absent);
      }
    });

    test('Spanish high-risk concepts, God, and direct address have parity', () {
      final rules = <RegExp, RegExp>{
        RegExp(r'\bdestino\b', caseSensitive: false):
            RegExp(r'\bdestiny\b', caseSensitive: false),
        RegExp(r'\buniverso\b', caseSensitive: false):
            RegExp(r'\buniverse\b', caseSensitive: false),
        RegExp(r'\benergía\b', caseSensitive: false):
            RegExp(r'\benergy\b', caseSensitive: false),
        RegExp(r'\bego\b', caseSensitive: false):
            RegExp(r'\bego\b', caseSensitive: false),
        RegExp(r'\b(?:sagrad\w*|sant[oa]s?)\b', caseSensitive: false):
            RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        RegExp(r'\btemplo\b', caseSensitive: false):
            RegExp(r'\btemple\b', caseSensitive: false),
        RegExp(r'\boraci(?:ón|ones)\b', caseSensitive: false):
            RegExp(r'\bprayers?\b', caseSensitive: false),
        RegExp(r'\badorar\b', caseSensitive: false):
            RegExp(r'\bworshipping\b', caseSensitive: false),
        RegExp(r'\bmisericordia\b', caseSensitive: false):
            RegExp(r'\bmercy\b', caseSensitive: false),
        RegExp(r'\bgracia\b', caseSensitive: false):
            RegExp(r'\bgrace\b', caseSensitive: false),
        RegExp(r'\bdevoción\b', caseSensitive: false):
            RegExp(r'\bdevotion\b', caseSensitive: false),
        RegExp(r'\bbendi\w*\b', caseSensitive: false):
            RegExp(r'\b(?:bless\w*|grace)\b', caseSensitive: false),
        RegExp(r'\baceptación\b', caseSensitive: false):
            RegExp(r'\bacceptance\b', caseSensitive: false),
        RegExp(r'\brendición\b', caseSensitive: false):
            RegExp(r'\bsurrender\b', caseSensitive: false),
      };
      final directAddress = RegExp(
        r'\b(?:tú|tu|tus|te|ti|contigo)\b',
        caseSensitive: false,
      );

      for (final entry in reviewedLocalizedWisdomCatalogs['es']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!rule.key.hasMatch(entry.value)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key.pattern}');
        }
        if (directAddress.hasMatch(entry.value)) {
          expect(_sourceHasDirectAddress(source), isTrue, reason: entry.key);
        }
      }

      final corpus = reviewedLocalizedWisdomCatalogs['es']!.values.join('\n');
      expect(RegExp(r'\b(?:Dios|Alá)\b', caseSensitive: false).hasMatch(corpus),
          isFalse,
          reason: 'Spanish introduces God where English has none');
      for (final absent in const <String>[
        'karma',
        'vibración',
        'frecuencia',
        'manifestación',
        'milagro',
      ]) {
        expect(corpus.toLowerCase().contains(absent), isFalse, reason: absent);
      }
    });

    test(
        'Brazilian Portuguese high-risk concepts, God, and direct address have parity',
        () {
      final rules = <RegExp, RegExp>{
        RegExp(r'\bdestino\b', caseSensitive: false):
            RegExp(r'\bdestiny\b', caseSensitive: false),
        RegExp(r'\buniverso\b', caseSensitive: false):
            RegExp(r'\buniverse\b', caseSensitive: false),
        RegExp(r'\benergia\b', caseSensitive: false):
            RegExp(r'\benergy\b', caseSensitive: false),
        RegExp(r'\bego\b', caseSensitive: false):
            RegExp(r'\bego\b', caseSensitive: false),
        RegExp(r'\b(?:sagrad\w*|sant[oa]s?)\b', caseSensitive: false):
            RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        RegExp(r'\btemplo\b', caseSensitive: false):
            RegExp(r'\btemple\b', caseSensitive: false),
        RegExp(r'\bora(?:ção|ções)\b', caseSensitive: false):
            RegExp(r'\bprayers?\b', caseSensitive: false),
        RegExp(r'\badorar\b', caseSensitive: false):
            RegExp(r'\bworshipping\b', caseSensitive: false),
        RegExp(r'\bmisericórdia\b', caseSensitive: false):
            RegExp(r'\bmercy\b', caseSensitive: false),
        RegExp(r'\bgraça\b', caseSensitive: false):
            RegExp(r'\bgrace\b', caseSensitive: false),
        RegExp(r'\bdevoção\b', caseSensitive: false):
            RegExp(r'\bdevotion\b', caseSensitive: false),
        RegExp(r'\b(?:bênção|bênçãos|abenço\w*)\b', caseSensitive: false):
            RegExp(r'\b(?:bless\w*|grace)\b', caseSensitive: false),
        RegExp(r'\baceitação\b', caseSensitive: false):
            RegExp(r'\bacceptance\b', caseSensitive: false),
        RegExp(r'\brendição\b', caseSensitive: false):
            RegExp(r'\bsurrender\b', caseSensitive: false),
      };

      for (final entry in reviewedLocalizedWisdomCatalogs['pt-BR']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!rule.key.hasMatch(entry.value)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key.pattern}');
        }
        if (RegExp(r'\bvocê\b', caseSensitive: false).hasMatch(entry.value)) {
          expect(_sourceHasDirectAddress(source), isTrue, reason: entry.key);
        }
      }

      final corpus =
          reviewedLocalizedWisdomCatalogs['pt-BR']!.values.join('\n');
      expect(RegExp(r'\b(?:Deus|Alá)\b', caseSensitive: false).hasMatch(corpus),
          isFalse,
          reason: 'Brazilian Portuguese introduces God where English has none');
      for (final absent in const <String>[
        'karma',
        'vibração',
        'frequência',
        'manifestação',
        'milagre',
      ]) {
        expect(corpus.toLowerCase().contains(absent), isFalse, reason: absent);
      }
    });

    test('Italian high-risk concepts, God, and direct address have parity', () {
      final rules = <RegExp, RegExp>{
        RegExp(r'\bdestino\b', caseSensitive: false):
            RegExp(r'\bdestiny\b', caseSensitive: false),
        RegExp(r'\buniverso\b', caseSensitive: false):
            RegExp(r'\buniverse\b', caseSensitive: false),
        RegExp(r'\benergia\b', caseSensitive: false):
            RegExp(r'\benergy\b', caseSensitive: false),
        RegExp(r'\bego\b', caseSensitive: false):
            RegExp(r'\bego\b', caseSensitive: false),
        RegExp(r'\b(?:sacr\w*|sant[oa]s?)\b', caseSensitive: false):
            RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        RegExp(r'\btempio\b', caseSensitive: false):
            RegExp(r'\btemple\b', caseSensitive: false),
        RegExp(r'\bpreghier\w*\b', caseSensitive: false):
            RegExp(r'\bprayers?\b', caseSensitive: false),
        RegExp(r'\badorare\b', caseSensitive: false):
            RegExp(r'\bworshipping\b', caseSensitive: false),
        RegExp(r'\bmisericordia\b', caseSensitive: false):
            RegExp(r'\bmercy\b', caseSensitive: false),
        RegExp(r'\bgrazia\b', caseSensitive: false):
            RegExp(r'\bgrace\b', caseSensitive: false),
        RegExp(r'\bdevozione\b', caseSensitive: false):
            RegExp(r'\bdevotion\b', caseSensitive: false),
        RegExp(r'\bbened\w*\b', caseSensitive: false):
            RegExp(r'\b(?:bless\w*|grace)\b', caseSensitive: false),
        RegExp(r'\baccettazione\b', caseSensitive: false):
            RegExp(r'\bacceptance\b', caseSensitive: false),
        RegExp(r'\bresa\b', caseSensitive: false):
            RegExp(r'\bsurrender\b', caseSensitive: false),
      };
      final directAddress = RegExp(
        r'\b(?:tu|tuo|tuoi|tua|tue|ti|te)\b',
        caseSensitive: false,
      );

      for (final entry in reviewedLocalizedWisdomCatalogs['it']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!rule.key.hasMatch(entry.value)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key.pattern}');
        }
        if (directAddress.hasMatch(entry.value)) {
          expect(_sourceHasDirectAddress(source), isTrue, reason: entry.key);
        }
      }

      final corpus = reviewedLocalizedWisdomCatalogs['it']!.values.join('\n');
      expect(
          RegExp(r'\b(?:Dio|Allah)\b', caseSensitive: false).hasMatch(corpus),
          isFalse,
          reason: 'Italian introduces God where English has none');
      for (final absent in const <String>[
        'karma',
        'vibrazione',
        'frequenza',
        'manifestazione',
        'miracolo',
      ]) {
        expect(corpus.toLowerCase().contains(absent), isFalse, reason: absent);
      }
    });

    test('Thai high-risk concepts, God, and direct address have parity', () {
      final rules = <String, RegExp>{
        'โชคชะตา': RegExp(r'\bdestiny\b', caseSensitive: false),
        'จักรวาล': RegExp(r'\buniverse\b', caseSensitive: false),
        'อัตตา': RegExp(r'\bego\b', caseSensitive: false),
        'ศักดิ์สิทธิ์': RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        'วิหาร': RegExp(r'\btemple\b', caseSensitive: false),
        'คำอธิษฐาน': RegExp(r'\bprayers?\b', caseSensitive: false),
        'บูชา': RegExp(r'\bworshipping\b', caseSensitive: false),
        'พระคุณ': RegExp(r'\bgrace\b', caseSensitive: false),
        'อุทิศตน': RegExp(r'\bdevotion\b', caseSensitive: false),
      };

      for (final entry in reviewedLocalizedWisdomCatalogs['th']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!entry.value.contains(rule.key)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key}');
        }
        final directAddress = entry.value
            .replaceAll('พระคุณ', '')
            .replaceAll('ขอบคุณ', '')
            .contains('คุณ');
        if (directAddress) {
          expect(_sourceHasDirectAddress(source), isTrue, reason: entry.key);
        }
      }

      final corpus = reviewedLocalizedWisdomCatalogs['th']!.values.join('\n');
      expect(RegExp(r'พระเจ้า|อัลลอฮ์|อัลลาห์').hasMatch(corpus), isFalse,
          reason: 'Thai introduces God where English has none');
      for (final absent in const <String>[
        'กรรมเก่า',
        'คลื่นความถี่',
        'กฎแรงดึงดูด',
        'ปาฏิหาริย์',
      ]) {
        expect(corpus.contains(absent), isFalse, reason: absent);
      }
    });

    test('Dutch high-risk concepts, God, and direct address have parity', () {
      final rules = <RegExp, RegExp>{
        RegExp(r'\b(?:lot|lotsbestemming)\b', caseSensitive: false):
            RegExp(r'\bdestiny\b', caseSensitive: false),
        RegExp(r'\buniversum\b', caseSensitive: false):
            RegExp(r'\buniverse\b', caseSensitive: false),
        RegExp(r'\benergie\b', caseSensitive: false):
            RegExp(r'\benergy\b', caseSensitive: false),
        RegExp(r'\bego\b', caseSensitive: false):
            RegExp(r'\bego\b', caseSensitive: false),
        RegExp(r'\bheilig\w*\b', caseSensitive: false):
            RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        RegExp(r'\btempel\b', caseSensitive: false):
            RegExp(r'\btemple\b', caseSensitive: false),
        RegExp(r'\bgebed\w*\b', caseSensitive: false):
            RegExp(r'\bprayers?\b', caseSensitive: false),
        RegExp(r'\baanbid\w*\b', caseSensitive: false):
            RegExp(r'\bworshipping\b', caseSensitive: false),
        RegExp(r'\bbarmhartigheid\b', caseSensitive: false):
            RegExp(r'\bmercy\b', caseSensitive: false),
        RegExp(r'\bgenade\b', caseSensitive: false):
            RegExp(r'\b(?:grace|mercy)\b', caseSensitive: false),
        RegExp(r'\btoewijding\b', caseSensitive: false):
            RegExp(r'\bdevotion\b', caseSensitive: false),
        RegExp(r'\bzegen\w*\b', caseSensitive: false):
            RegExp(r'\b(?:bless\w*|grace)\b', caseSensitive: false),
        RegExp(r'\baanvaarding\b', caseSensitive: false):
            RegExp(r'\bacceptance\b', caseSensitive: false),
        RegExp(r'\bovergave\b', caseSensitive: false):
            RegExp(r'\bsurrender\b', caseSensitive: false),
      };
      final directAddress = RegExp(
        r'\b(?:je|jij|jou|jouw|jezelf)\b',
        caseSensitive: false,
      );

      for (final entry in reviewedLocalizedWisdomCatalogs['nl']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!rule.key.hasMatch(entry.value)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key.pattern}');
        }
        if (directAddress.hasMatch(entry.value)) {
          expect(_sourceHasDirectAddress(source), isTrue, reason: entry.key);
        }
      }

      final corpus = reviewedLocalizedWisdomCatalogs['nl']!.values.join('\n');
      expect(RegExp(r'\b(?:God|Allah)\b').hasMatch(corpus), isFalse,
          reason: 'Dutch introduces God where English has none');
      for (final absent in const <String>[
        'karma',
        'trilling',
        'frequentie',
        'manifestatie',
        'wonder',
      ]) {
        expect(corpus.toLowerCase().contains(absent), isFalse, reason: absent);
      }
    });

    test('Polish high-risk concepts, God, and direct address have parity', () {
      final rules = <RegExp, RegExp>{
        RegExp(r'\bprzeznaczeni\w*\b', caseSensitive: false):
            RegExp(r'\b(?:destiny|meant)\b', caseSensitive: false),
        RegExp(r'\bwszechświat\b', caseSensitive: false):
            RegExp(r'\buniverse\b', caseSensitive: false),
        RegExp(r'\benergi\w*\b', caseSensitive: false):
            RegExp(r'\benergy\b', caseSensitive: false),
        RegExp(r'(^|[^A-Za-zÀ-ž])ego([^A-Za-zÀ-ž]|$)', caseSensitive: false):
            RegExp(r'\bego\b', caseSensitive: false),
        RegExp(r'\bświęt\w*\b', caseSensitive: false):
            RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        RegExp(r'\bświątyni\w*\b', caseSensitive: false):
            RegExp(r'\btemple\b', caseSensitive: false),
        RegExp(r'\bmodlitw\w*\b', caseSensitive: false):
            RegExp(r'\bprayers?\b', caseSensitive: false),
        RegExp(r'\bczci\w*\b', caseSensitive: false):
            RegExp(r'\bworshipping\b', caseSensitive: false),
        RegExp(r'\bmiłosierdzi\w*\b', caseSensitive: false):
            RegExp(r'\bmercy\b', caseSensitive: false),
        RegExp(r'\błask\w*\b', caseSensitive: false):
            RegExp(r'\bgrace\b', caseSensitive: false),
        RegExp(r'\boddani\w*\b', caseSensitive: false):
            RegExp(r'\bdevotion\b', caseSensitive: false),
        RegExp(r'\bbłogosław\w*\b', caseSensitive: false):
            RegExp(r'\b(?:bless\w*|grace)\b', caseSensitive: false),
        RegExp(r'\bakceptacj\w*\b', caseSensitive: false):
            RegExp(r'\bacceptance\b', caseSensitive: false),
        RegExp(r'\bpoddani\w*\b', caseSensitive: false):
            RegExp(r'\bsurrender\b', caseSensitive: false),
      };
      final directAddress = RegExp(
        r'\b(?:cię|ciebie|tobie|twój|twoja|twoje|twoją|twojego|twojej|twoim|twoich)\b',
        caseSensitive: false,
      );

      for (final entry in reviewedLocalizedWisdomCatalogs['pl']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!rule.key.hasMatch(entry.value)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key.pattern}');
        }
        if (directAddress.hasMatch(entry.value)) {
          expect(_sourceHasDirectAddress(source), isTrue, reason: entry.key);
        }
      }

      final corpus = reviewedLocalizedWisdomCatalogs['pl']!.values.join('\n');
      expect(RegExp(r'\b(?:Bóg|Allah)\b').hasMatch(corpus), isFalse,
          reason: 'Polish introduces God where English has none');
      for (final absent in const <String>[
        'karma',
        'wibracja',
        'częstotliwość',
        'manifestacja',
        'cud',
      ]) {
        expect(corpus.toLowerCase().contains(absent), isFalse, reason: absent);
      }
    });

    test('Vietnamese high-risk concepts, God, and direct address have parity',
        () {
      final rules = <RegExp, RegExp>{
        RegExp(r'\bđịnh mệnh\b', caseSensitive: false):
            RegExp(r'\bdestiny\b', caseSensitive: false),
        RegExp(r'\bvũ trụ\b', caseSensitive: false):
            RegExp(r'\buniverse\b', caseSensitive: false),
        RegExp(r'\bnăng lượng\b', caseSensitive: false):
            RegExp(r'\benergy\b', caseSensitive: false),
        RegExp(r'\bbản ngã\b', caseSensitive: false):
            RegExp(r'\bego\b', caseSensitive: false),
        RegExp(r'\bthiêng liêng\b', caseSensitive: false):
            RegExp(r'\b(?:sacred|holy)\b', caseSensitive: false),
        RegExp(r'\bngôi đền\b', caseSensitive: false):
            RegExp(r'\btemple\b', caseSensitive: false),
        RegExp(r'\blời cầu nguyện\b', caseSensitive: false):
            RegExp(r'\bprayers?\b', caseSensitive: false),
        RegExp(r'\btôn thờ\b', caseSensitive: false):
            RegExp(r'\bworshipping\b', caseSensitive: false),
        RegExp(r'\blòng thương xót\b', caseSensitive: false):
            RegExp(r'\bmercy\b', caseSensitive: false),
        RegExp(r'\bân sủng\b', caseSensitive: false):
            RegExp(r'\bgrace\b', caseSensitive: false),
        RegExp(r'\bsự tận tâm\b', caseSensitive: false):
            RegExp(r'\bdevotion\b', caseSensitive: false),
        RegExp(r'\b(?:phước lành|chúc lành)\b', caseSensitive: false):
            RegExp(r'\b(?:bless\w*|grace)\b', caseSensitive: false),
        RegExp(r'\bbuông mình\b', caseSensitive: false):
            RegExp(r'\bsurrender\b', caseSensitive: false),
      };

      for (final entry in reviewedLocalizedWisdomCatalogs['vi']!.entries) {
        final source = _englishById[entry.key]!;
        for (final rule in rules.entries) {
          if (!rule.key.hasMatch(entry.value)) continue;
          expect(rule.value.hasMatch(source), isTrue,
              reason: '${entry.key} introduces ${rule.key.pattern}');
        }
        if (RegExp(r'\bbạn\b', caseSensitive: false).hasMatch(entry.value)) {
          expect(_sourceHasDirectAddress(source), isTrue, reason: entry.key);
        }
      }

      final corpus = reviewedLocalizedWisdomCatalogs['vi']!.values.join('\n');
      expect(RegExp(r'\b(?:Thượng đế|Chúa|Allah)\b').hasMatch(corpus), isFalse,
          reason: 'Vietnamese introduces God where English has none');
      for (final absent in const <String>[
        'nghiệp lực',
        'rung động',
        'tần số',
        'luật hấp dẫn',
        'phép màu',
      ]) {
        expect(corpus.toLowerCase().contains(absent), isFalse, reason: absent);
      }
    });
  });

  testWidgets('Latin reviewed wisdoms pass hard and proportional fit limits',
      (tester) async {
    final garamond = FontLoader(EastTypography.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/EBGaramond-Variable.ttf'));
    await garamond.load();

    const oneRenderedLine =
        EastVisualFit.wisdomFontSize * EastVisualFit.wisdomHeight;
    for (final tag in const <String>[
      'de',
      'fr',
      'es',
      'pt-BR',
      'it',
      'nl',
      'pl',
      'vi',
    ]) {
      final disproportionate = <String>[];
      for (final entry in reviewedLocalizedWisdomCatalogs[tag]!.entries) {
        final sourceHeight =
            EastVisualFit.measureWisdomHeight(_englishById[entry.key]!);
        final targetHeight = EastVisualFit.measureWisdomHeight(entry.value);
        expect(
          targetHeight,
          lessThanOrEqualTo(EastVisualFit.englishWisdomMaximumHeight),
          reason: '$tag/${entry.key} exceeds the 728 px hard ceiling',
        );
        final proportionalLimit =
            sourceHeight * 1.5 > sourceHeight + oneRenderedLine
                ? sourceHeight * 1.5
                : sourceHeight + oneRenderedLine;
        if (targetHeight > proportionalLimit) {
          disproportionate.add(
            '${entry.key}: $sourceHeight -> $targetHeight '
            '(limit $proportionalLimit)',
          );
        }
      }
      expect(disproportionate, isEmpty,
          reason: '$tag disproportionate:\n${disproportionate.join('\n')}');
    }
  });

  group('multilingual resolver and data safety', () {
    const resolver = WisdomLocalizationResolver();

    test('every reviewed locale resolves by immutable canonical ID', () {
      const id = 'east_wisdom_0453';
      for (final localeCatalog in reviewedLocalizedWisdomCatalogs.entries) {
        expect(
          resolver.resolve(
            wisdomId: id,
            locale: _localeForTag(localeCatalog.key),
            persistedSnapshot: _unusedSnapshot,
          ),
          localeCatalog.value[id],
          reason: localeCatalog.key,
        );
      }
    });

    test('missing translation and legacy IDs preserve fallback contracts', () {
      final first = wisdoms.first;
      expect(
        resolver.resolve(
          wisdomId: first['id'] as String,
          locale: const Locale('en'),
          persistedSnapshot: _unusedSnapshot,
        ),
        first['text'],
      );
      expect(
        resolver.resolve(
          wisdomId: 'unknown-wisdom',
          locale: const Locale('ja'),
          persistedSnapshot: 'Historical unknown snapshot.',
        ),
        'Historical unknown snapshot.',
      );
      expect(
        resolver.resolve(
          wisdomId: null,
          locale: const Locale('ja'),
          persistedSnapshot: 'Historical legacy snapshot.',
        ),
        'Historical legacy snapshot.',
      );
    });

    test('locale presentation leaves daily occurrence identity unchanged', () {
      final source = wisdoms[452];
      final revealedAt = DateTime.utc(2026, 8, 23, 9);
      final record = DailyWisdomRecord(
        text: source['text'] as String,
        wisdomId: source['id'] as String,
        revealId: 'aaaaaaaa-1111-4111-8111-111111111111',
        revealedAt: revealedAt,
        unlockAt: revealedAt.add(DailyWisdomRecord.lockDuration),
      );

      for (final localeCatalog in reviewedLocalizedWisdomCatalogs.entries) {
        expect(
          resolver.resolve(
            wisdomId: record.wisdomId,
            locale: _localeForTag(localeCatalog.key),
            persistedSnapshot: record.text,
          ),
          localeCatalog.value[record.wisdomId],
          reason: localeCatalog.key,
        );
      }
      expect(record.revealId, 'aaaaaaaa-1111-4111-8111-111111111111');
      expect(record.wisdomId, source['id']);
      expect(record.text, source['text']);
      expect(record.revealedAt, revealedAt);
      expect(record.unlockAt.difference(record.revealedAt),
          DailyWisdomRecord.lockDuration);
    });

    test('Kept identity, English snapshot, and Reflection stay unchanged', () {
      final source = wisdoms[452];
      final instant = DateTime.utc(2026, 8, 23, 9);
      final record = KeptRecord(
        id: 'kept-record',
        revealId: 'aaaaaaaa-1111-4111-8111-111111111111',
        wisdomId: source['id'] as String,
        wisdomText: source['text'] as String,
        revealedAt: instant,
        keptAt: instant,
        reflectionText: 'Original user reflection — unchanged.',
        reflectedAt: instant,
        updatedAt: instant,
        mutationId: 'bbbbbbbb-2222-4222-8222-222222222222',
      );

      for (final localeCatalog in reviewedLocalizedWisdomCatalogs.entries) {
        expect(
          resolver.resolve(
            wisdomId: record.wisdomId,
            locale: _localeForTag(localeCatalog.key),
            persistedSnapshot: record.wisdomText,
          ),
          localeCatalog.value[record.wisdomId],
          reason: localeCatalog.key,
        );
      }
      expect(record.id, 'kept-record');
      expect(record.revealId, 'aaaaaaaa-1111-4111-8111-111111111111');
      expect(record.wisdomId, source['id']);
      expect(record.wisdomText, source['text']);
      expect(record.reflectionText, 'Original user reflection — unchanged.');
    });

    test('reviewed catalogs are active only through approved product locales',
        () {
      expect(EastLocaleRegistry.runtimeSupported, hasLength(15));
      for (final tag in reviewedLocalizedWisdomCatalogs.keys) {
        expect(
          EastLocaleRegistry.runtimeSupported,
          contains(_localeForTag(tag)),
          reason: tag,
        );
      }
    });
  });
}

const String _unusedSnapshot = 'Persisted English snapshot.';
