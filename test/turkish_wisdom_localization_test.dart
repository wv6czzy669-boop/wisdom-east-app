import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/data/wisdoms_tr.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/localization/visual_fit.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/services/wisdom_localization_resolver.dart';
import 'package:wisdom_app/theme/east_design.dart';

Map<String, String> get _englishById => <String, String>{
      for (final wisdom in wisdoms)
        wisdom['id'] as String: wisdom['text'] as String,
    };

bool _hasSemanticDirectAddress(String english) => RegExp(
      r'\b(?:you|your|yours|yourself)\b|^(?:Begin|Choose|Do not|Let|Release|Stay|Trust)\b',
      caseSensitive: false,
    ).hasMatch(english);

void main() {
  group('Turkish wisdom corpus integrity', () {
    test('contains exactly the canonical 603 IDs in canonical order', () {
      final canonicalIds = wisdoms
          .map((wisdom) => wisdom['id'] as String)
          .toList(growable: false);

      expect(wisdoms, hasLength(603));
      expect(turkishWisdomCatalog, hasLength(603));
      expect(turkishWisdomCatalog.keys.toList(), canonicalIds);
      expect(turkishWisdomCatalog.keys.toSet(), canonicalIds.toSet());
    });

    test('every entry is one complete, clean Unicode sentence', () {
      for (final entry in turkishWisdomCatalog.entries) {
        final value = entry.value;
        expect(value, isNotEmpty, reason: entry.key);
        expect(value.trim(), value, reason: '${entry.key} surrounding space');
        expect(value, isNot(contains('\n')), reason: '${entry.key} newline');
        expect(value, isNot(contains('\uFFFD')),
            reason: '${entry.key} broken Unicode');
        expect(RegExp(r'[.!?]$').hasMatch(value), isTrue,
            reason: '${entry.key} terminal punctuation');
        expect(RegExp(r'[.!?].+[.!?]').hasMatch(value), isFalse,
            reason: '${entry.key} must remain one sentence');
      }
    });

    test('contains no accidental English source copies', () {
      final englishTexts = _englishById.values.toSet();
      for (final entry in turkishWisdomCatalog.entries) {
        expect(englishTexts, isNot(contains(entry.value)), reason: entry.key);
      }
    });

    test('God and Tanrı have exact zero-to-zero parity', () {
      final englishGodIds = _englishById.entries
          .where((entry) => RegExp(r'\bGod\b').hasMatch(entry.value))
          .map((entry) => entry.key)
          .toSet();
      final turkishGodIds = turkishWisdomCatalog.entries
          .where((entry) => RegExp(r'\bTanrı\b').hasMatch(entry.value))
          .map((entry) => entry.key)
          .toSet();

      expect(englishGodIds, isEmpty);
      expect(turkishGodIds, englishGodIds);
    });

    test('sensitive spiritual concepts appear only when source-required', () {
      const requiredSourceConcept = <String, String>{
        'kader': r'\bdestiny\b',
        'evren': r'\buniverse\b',
        'enerji': r'\benergy\b',
        'ego': r'\bego\b',
        'kutsal': r'\b(?:sacred|holy|bless)',
        'kutsan': r'\bbless',
        '(?:dualar|duaya)': r'\bprayer',
        'tapın': r'\b(?:temple|worship)',
        'lütuf': r'\bgrace\b',
        'merhamet': r'\bmercy\b',
        'adan': r'\bdevotion\b',
      };

      for (final entry in turkishWisdomCatalog.entries) {
        final source = _englishById[entry.key]!.toLowerCase();
        final target = entry.value.toLowerCase();
        for (final concept in requiredSourceConcept.entries) {
          final targetConcept = RegExp(
            '(^|[^a-zçğıöşü])${concept.key}',
            caseSensitive: false,
          );
          if (targetConcept.hasMatch(target)) {
            expect(RegExp(concept.value).hasMatch(source), isTrue,
                reason: '${entry.key} introduces ${concept.key}');
          }
        }
      }

      final corpus = turkishWisdomCatalog.values.join('\n').toLowerCase();
      for (final absent in const <String>[
        'yazgı',
        'nasip',
        'olması gerekiyordu',
        'titreşim',
        'frekans',
        'tezahür',
        'manifest',
        'ruhsal olarak gerekli',
        'hak ettin',
        'acının nedeni',
        'mucize',
        'allah',
        'rab',
        'yaratıcı',
      ]) {
        final absentConcept = RegExp(
          '(^|[^a-zçğıöşü])$absent([^a-zçğıöşü]|\$)',
          caseSensitive: false,
        );
        expect(absentConcept.hasMatch(corpus), isFalse, reason: absent);
      }
    });

    test('explicit Turkish direct address has a source-semantic basis', () {
      final explicitAddress =
          RegExp(r'\b(?:sen|sana|seni|senin)\b', caseSensitive: false);
      for (final entry in turkishWisdomCatalog.entries) {
        if (!explicitAddress.hasMatch(entry.value)) continue;
        expect(
          _hasSemanticDirectAddress(_englishById[entry.key]!),
          isTrue,
          reason: '${entry.key} introduces direct address',
        );
      }
    });
  });

  group('Turkish wisdom resolution and data safety', () {
    const resolver = WisdomLocalizationResolver();

    test('known Turkish ID resolves reviewed text', () {
      const id = 'east_wisdom_0001';
      expect(
        resolver.resolve(
          wisdomId: id,
          locale: const Locale('tr'),
          persistedSnapshot: _unusedSnapshot,
        ),
        turkishWisdomCatalog[id],
      );
    });

    test('unavailable localized entry falls back to canonical English', () {
      final first = wisdoms.first;
      expect(
        resolver.resolve(
          wisdomId: first['id'] as String,
          locale: const Locale('en'),
          persistedSnapshot: _unusedSnapshot,
        ),
        first['text'],
      );
    });

    test('unknown and legacy-null IDs preserve their snapshots', () {
      expect(
        resolver.resolve(
          wisdomId: 'unknown-wisdom',
          locale: const Locale('tr'),
          persistedSnapshot: 'Historical unknown snapshot.',
        ),
        'Historical unknown snapshot.',
      );
      expect(
        resolver.resolve(
          wisdomId: null,
          locale: const Locale('tr'),
          persistedSnapshot: 'Historical legacy snapshot.',
        ),
        'Historical legacy snapshot.',
      );
    });

    test('daily occurrence identity and 24-hour lock remain unchanged', () {
      final source = wisdoms.first;
      final revealedAt = DateTime.utc(2026, 8, 23, 9);
      final record = DailyWisdomRecord(
        text: source['text'] as String,
        wisdomId: source['id'] as String,
        revealId: 'aaaaaaaa-1111-4111-8111-111111111111',
        revealedAt: revealedAt,
        unlockAt: revealedAt.add(DailyWisdomRecord.lockDuration),
      );

      final display = resolver.resolve(
        wisdomId: record.wisdomId,
        locale: const Locale('tr'),
        persistedSnapshot: record.text,
      );

      expect(display, turkishWisdomCatalog[record.wisdomId]);
      expect(record.revealId, 'aaaaaaaa-1111-4111-8111-111111111111');
      expect(record.wisdomId, source['id']);
      expect(record.text, source['text']);
      expect(record.revealedAt, revealedAt);
      expect(record.unlockAt.difference(record.revealedAt),
          DailyWisdomRecord.lockDuration);
    });

    test('Kept identity, snapshot, and Reflection remain untouched', () {
      final source = wisdoms[41];
      final instant = DateTime.utc(2026, 8, 23, 9);
      final record = KeptRecord(
        id: 'kept-record',
        revealId: 'aaaaaaaa-1111-4111-8111-111111111111',
        wisdomId: source['id'] as String,
        wisdomText: source['text'] as String,
        revealedAt: instant,
        keptAt: instant,
        reflectionText: 'Kullanıcının özgün yansıması — unchanged.',
        reflectedAt: instant,
        updatedAt: instant,
        mutationId: 'bbbbbbbb-2222-4222-8222-222222222222',
      );

      final display = resolver.resolve(
        wisdomId: record.wisdomId,
        locale: const Locale('tr'),
        persistedSnapshot: record.wisdomText,
      );

      expect(display, turkishWisdomCatalog[record.wisdomId]);
      expect(record.id, 'kept-record');
      expect(record.revealId, 'aaaaaaaa-1111-4111-8111-111111111111');
      expect(record.wisdomId, source['id']);
      expect(record.wisdomText, source['text']);
      expect(
          record.reflectionText, 'Kullanıcının özgün yansıması — unchanged.');
    });

    test('Turkish is an approved runtime product locale', () {
      expect(EastLocaleRegistry.runtimeSupported, contains(const Locale('tr')));
    });
  });

  testWidgets('all 603 Turkish wisdoms pass hard and proportional fit limits',
      (tester) async {
    final garamond = FontLoader(EastTypography.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/EBGaramond-Variable.ttf'));
    await garamond.load();

    const oneRenderedLine =
        EastVisualFit.wisdomFontSize * EastVisualFit.wisdomHeight;
    var maximumHeight = 0.0;
    var maximumId = '';
    final disproportionate = <String>[];
    for (final entry in turkishWisdomCatalog.entries) {
      final sourceHeight =
          EastVisualFit.measureWisdomHeight(_englishById[entry.key]!);
      final targetHeight = EastVisualFit.measureWisdomHeight(entry.value);
      if (targetHeight > maximumHeight) {
        maximumHeight = targetHeight;
        maximumId = entry.key;
      }

      expect(
        targetHeight,
        lessThanOrEqualTo(EastVisualFit.englishWisdomMaximumHeight),
        reason: '${entry.key} exceeds the 728 px hard ceiling',
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

    // Locked after the first deterministic full-corpus measurement. A future
    // copy edit that creates a new worst case must be reviewed deliberately.
    expect(maximumId, 'east_wisdom_0033');
    expect(maximumHeight, 336.0);
    expect(disproportionate, isEmpty,
        reason:
            'Disproportionate translations:\n${disproportionate.join('\n')}');
  });
}

const String _unusedSnapshot = 'Persisted English snapshot.';
