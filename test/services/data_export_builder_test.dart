import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/services/data_export_builder.dart';

void main() {
  const builder = DataExportBuilder();
  final exportedAt = DateTime.utc(2026, 8, 16, 10, 30);

  FavoriteItem item({
    required String id,
    required String revealId,
    required String text,
    DateTime? keptAt,
    String? reflection,
    DateTime? reflectedAt,
  }) {
    return FavoriteItem(
      id: id,
      revealId: revealId,
      text: text,
      date: 'display date',
      keptAt: keptAt?.toIso8601String(),
      reflection: reflection,
      reflectedAt: reflectedAt?.toIso8601String(),
    );
  }

  Map<String, Object?> decodeJson(DataExportDocument document) {
    return jsonDecode(utf8.decode(document.jsonBytes)) as Map<String, Object?>;
  }

  test('produces both JSON and TXT payloads', () {
    final document = builder.build(
      items: const [],
      journalOwnerName: null,
      exportedAt: exportedAt,
    );

    expect(document.jsonBytes, isNotEmpty);
    expect(document.txtBytes, isNotEmpty);
  });

  test('deterministic filenames use the EAST-Data-YYYY-MM-DD shape, with '
      'no owner name in either', () {
    final document = builder.build(
      items: const [],
      journalOwnerName: 'Doğukan Işık',
      exportedAt: exportedAt,
    );

    expect(document.jsonFilename, 'EAST-Data-2026-08-16.json');
    expect(document.txtFilename, 'EAST-Data-2026-08-16.txt');
  });

  group('JSON schema', () {
    test('is versioned with a stable format name', () {
      final document = builder.build(
        items: const [],
        journalOwnerName: null,
        exportedAt: exportedAt,
      );
      final decoded = decodeJson(document);

      expect(decoded['format'], 'EAST Data Export');
      expect(decoded['version'], 1);
      expect(decoded['exportedAt'], exportedAt.toUtc().toIso8601String());
    });

    test('is valid, parseable, pretty-printed UTF-8 JSON', () {
      final document = builder.build(
        items: [
          item(
            id: '1',
            revealId: 'a5f3c111-1111-4111-8111-000000000001',
            text: 'A kept wisdom',
            keptAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        journalOwnerName: null,
        exportedAt: exportedAt,
      );

      final text = utf8.decode(document.jsonBytes);
      expect(() => jsonDecode(text), returnsNormally);
      // Pretty-printed: more than one line.
      expect(text.split('\n').length, greaterThan(1));
    });

    test('journalOwnerName is included when present, and never invented '
        'when absent', () {
      final withName = decodeJson(
        builder.build(
          items: const [],
          journalOwnerName: 'Doğukan Işık',
          exportedAt: exportedAt,
        ),
      );
      expect(withName['journalOwnerName'], 'Doğukan Işık');

      final withoutName = decodeJson(
        builder.build(
          items: const [],
          journalOwnerName: null,
          exportedAt: exportedAt,
        ),
      );
      expect(withoutName['journalOwnerName'], isNull);
      expect(withoutName.containsKey('journalOwnerName'), isTrue);
    });

    test('active Kept occurrences are exported with exactly the expected '
        'fields -- revealId, wisdom text, and keptAt only', () {
      final document = builder.build(
        items: [
          item(
            id: '1',
            revealId: 'a5f3c111-1111-4111-8111-000000000001',
            text: 'A kept wisdom',
            keptAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        journalOwnerName: null,
        exportedAt: exportedAt,
      );
      final decoded = decodeJson(document);
      final kept = decoded['kept'] as List<Object?>;

      expect(kept, hasLength(1));
      final entry = kept.single as Map<String, Object?>;
      expect(entry.keys.toSet(), {'revealId', 'wisdomText', 'keptAt'});
      expect(entry['revealId'], 'a5f3c111-1111-4111-8111-000000000001');
      expect(entry['wisdomText'], 'A kept wisdom');
      expect(entry['keptAt'], DateTime.utc(2026, 1, 1).toIso8601String());
    });

    test('active Reflections are exported, associated only through '
        'revealId identity -- never by wisdom text', () {
      const sharedText = 'The exact same wisdom text twice';
      final document = builder.build(
        items: [
          item(
            id: '1',
            revealId: 'a5f3c111-1111-4111-8111-000000000001',
            text: sharedText,
            keptAt: DateTime.utc(2026, 1, 1),
            // No reflection on this occurrence.
          ),
          item(
            id: '2',
            revealId: 'a5f3c111-1111-4111-8111-000000000002',
            text: sharedText,
            keptAt: DateTime.utc(2026, 1, 2),
            reflection: 'My private thought about it.',
            reflectedAt: DateTime.utc(2026, 1, 3),
          ),
        ],
        journalOwnerName: null,
        exportedAt: exportedAt,
      );
      final decoded = decodeJson(document);

      final kept = decoded['kept'] as List<Object?>;
      expect(kept, hasLength(2));

      final reflections = decoded['reflections'] as List<Object?>;
      expect(reflections, hasLength(1));
      final reflectionEntry = reflections.single as Map<String, Object?>;
      expect(reflectionEntry.keys.toSet(),
          {'revealId', 'reflectionText', 'reflectedAt'});
      expect(
        reflectionEntry['revealId'],
        'a5f3c111-1111-4111-8111-000000000002',
      );
      expect(reflectionEntry['reflectionText'], 'My private thought about it.');
      expect(
        reflectionEntry['reflectedAt'],
        DateTime.utc(2026, 1, 3).toIso8601String(),
      );
    });

    test('duplicate wisdom text with different revealIds remains two '
        'distinct Kept occurrences', () {
      const sharedText = 'Identical text, different occurrences';
      final document = builder.build(
        items: [
          item(
            id: '1',
            revealId: 'a5f3c111-1111-4111-8111-000000000001',
            text: sharedText,
            keptAt: DateTime.utc(2026, 1, 1),
          ),
          item(
            id: '2',
            revealId: 'a5f3c111-1111-4111-8111-000000000002',
            text: sharedText,
            keptAt: DateTime.utc(2026, 1, 2),
          ),
        ],
        journalOwnerName: null,
        exportedAt: exportedAt,
      );
      final decoded = decodeJson(document);
      final kept = decoded['kept'] as List<Object?>;

      expect(kept, hasLength(2));
      final revealIds = kept
          .cast<Map<String, Object?>>()
          .map((e) => e['revealId'])
          .toSet();
      expect(revealIds, {
        'a5f3c111-1111-4111-8111-000000000001',
        'a5f3c111-1111-4111-8111-000000000002',
      });
    });

    test('an item with no revealId (no stable identity) is never '
        'exported', () {
      const noIdentity = FavoriteItem(
        id: 'legacy-1',
        text: 'A legacy item with no revealId',
        date: 'display date',
      );
      final document = builder.build(
        items: [noIdentity],
        journalOwnerName: null,
        exportedAt: exportedAt,
      );
      final decoded = decodeJson(document);

      expect(decoded['kept'], isEmpty);
      expect(decoded['reflections'], isEmpty);
    });

    test('Kept content is sorted oldest -> newest, deterministically', () {
      final document = builder.build(
        items: [
          item(
            id: '3',
            revealId: 'a5f3c111-1111-4111-8111-000000000003',
            text: 'Newest',
            keptAt: DateTime.utc(2026, 3, 1),
          ),
          item(
            id: '1',
            revealId: 'a5f3c111-1111-4111-8111-000000000001',
            text: 'Oldest',
            keptAt: DateTime.utc(2026, 1, 1),
          ),
          item(
            id: '2',
            revealId: 'a5f3c111-1111-4111-8111-000000000002',
            text: 'Middle',
            keptAt: DateTime.utc(2026, 2, 1),
          ),
        ],
        journalOwnerName: null,
        exportedAt: exportedAt,
      );
      final decoded = decodeJson(document);
      final kept = decoded['kept'] as List<Object?>;
      final texts =
          kept.cast<Map<String, Object?>>().map((e) => e['wisdomText']);

      expect(texts, ['Oldest', 'Middle', 'Newest']);
    });

    test('no CloudKit/sync/purchase/analytics/operational field ever '
        'appears anywhere in the document', () {
      final document = builder.build(
        items: [
          item(
            id: '1',
            revealId: 'a5f3c111-1111-4111-8111-000000000001',
            text: 'A kept wisdom',
            keptAt: DateTime.utc(2026, 1, 1),
            reflection: 'A reflection',
            reflectedAt: DateTime.utc(2026, 1, 2),
          ),
        ],
        journalOwnerName: 'A Name',
        exportedAt: exportedAt,
      );
      final jsonText = utf8.decode(document.jsonBytes);
      final txtText = utf8.decode(document.txtBytes);

      const forbidden = [
        'recordSystemFields',
        'accountFingerprint',
        'dataEpoch',
        'mutationId',
        'outbox',
        'tombstone',
        'localId',
        'CKRecord',
        'CloudKit',
        'unlockAt',
        'revealedAt',
        'purchase',
        'receipt',
        'transactionId',
        'analytics',
        'ratingRequest',
      ];
      for (final term in forbidden) {
        expect(jsonText.contains(term), isFalse, reason: 'JSON leaked "$term"');
        expect(txtText.contains(term), isFalse, reason: 'TXT leaked "$term"');
      }
    });
  });

  group('TXT structure', () {
    test('is valid, readable UTF-8 and contains the expected header/'
        'structure', () {
      final document = builder.build(
        items: const [],
        journalOwnerName: null,
        exportedAt: exportedAt,
      );
      final text = utf8.decode(document.txtBytes);

      expect(text, contains('EAST.'));
      expect(text, contains('Data Export'));
      expect(text, contains('Exported:'));
    });

    test('owner name appears when present, never invented when absent', () {
      final withName = utf8.decode(
        builder
            .build(
              items: const [],
              journalOwnerName: 'Doğukan Işık',
              exportedAt: exportedAt,
            )
            .txtBytes,
      );
      expect(withName, contains('Doğukan Işık'));

      final withoutName = utf8.decode(
        builder
            .build(
              items: const [],
              journalOwnerName: null,
              exportedAt: exportedAt,
            )
            .txtBytes,
      );
      expect(withoutName, isNot(contains('For:')));
    });

    test('an occurrence with no Reflection shows the wisdom/date cleanly, '
        'with no invented empty Reflection section', () {
      final text = utf8.decode(
        builder
            .build(
              items: [
                item(
                  id: '1',
                  revealId: 'a5f3c111-1111-4111-8111-000000000001',
                  text: 'A wisdom with no reflection',
                  keptAt: DateTime.utc(2026, 1, 1),
                ),
              ],
              journalOwnerName: null,
              exportedAt: exportedAt,
            )
            .txtBytes,
      );

      expect(text, contains('A wisdom with no reflection'));
      expect(text, isNot(contains('Reflection:')));
    });

    test('an occurrence with a Reflection includes it under an unobtrusive '
        '"Reflection:" label, with revealId present only as unobtrusive '
        'reference metadata', () {
      final text = utf8.decode(
        builder
            .build(
              items: [
                item(
                  id: '1',
                  revealId: 'a5f3c111-1111-4111-8111-000000000001',
                  text: 'A wisdom with a reflection',
                  keptAt: DateTime.utc(2026, 1, 1),
                  reflection: 'My own private words about it.',
                  reflectedAt: DateTime.utc(2026, 1, 2),
                ),
              ],
              journalOwnerName: null,
              exportedAt: exportedAt,
            )
            .txtBytes,
      );

      expect(text, contains('A wisdom with a reflection'));
      expect(text, contains('Reflection:'));
      expect(text, contains('My own private words about it.'));
      expect(
        text,
        contains('Reference: a5f3c111-1111-4111-8111-000000000001'),
      );
    });
  });
}
