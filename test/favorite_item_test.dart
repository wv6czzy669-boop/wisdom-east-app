import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';

void main() {
  group('revealId compatibility: old Build 25 current-schema JSON', () {
    test(
        'current-schema JSON without a revealId key still decodes, with '
        'revealId null', () {
      final raw = jsonEncode({
        'schemaVersion': 2,
        'id': 'sr-v1-1000-0',
        'date': 'August 1, 2026',
        'text': 'Be still.',
      });

      final item = FavoriteItem.decodeCurrent(raw);

      expect(item.id, 'sr-v1-1000-0');
      expect(item.text, 'Be still.');
      expect(item.revealId, isNull);
    });

    test(
        'current-schema JSON with reflection fields but no revealId key '
        'still decodes, with revealId null', () {
      final raw = jsonEncode({
        'schemaVersion': 2,
        'id': 'sr-v1-1000-0',
        'date': 'August 1, 2026',
        'text': 'Be still.',
        'reflection': 'A quiet morning.',
        'reflectedAt': '2026-08-01T09:00:00.000Z',
      });

      final item = FavoriteItem.decodeCurrent(raw);

      expect(item.revealId, isNull);
      expect(item.reflection, 'A quiet morning.');
    });

    test(
        'schemaVersion 1 (pre-Build25-schema-bump) JSON without revealId '
        'still decodes', () {
      final raw = jsonEncode({
        'schemaVersion': 1,
        'id': 'sr-v1-1000-0',
        'date': 'August 1, 2026',
        'text': 'Be still.',
      });

      final item = FavoriteItem.decodeCurrent(raw);

      expect(item.revealId, isNull);
    });
  });

  group('revealId compatibility: legacy pipe data', () {
    test('legacy pipe data still decodes, with revealId null', () {
      final item = FavoriteItem.decodeLegacy(
        'August 1, 2026|||Be still.',
        id: 'legacy-v1-0-abcdef01',
      );

      expect(item.id, 'legacy-v1-0-abcdef01');
      expect(item.date, 'August 1, 2026');
      expect(item.text, 'Be still.');
      expect(item.revealId, isNull);
    });
  });

  group('revealId round-trip', () {
    test('a v4 revealId round-trips through encode/decode losslessly', () {
      const v4 = '3f2e1a4c-9b7d-4a6e-8c1f-0d2b5e7a9c11';
      final item = FavoriteItem(
        id: 'sr-v1-1000-0',
        text: 'Be still.',
        date: 'August 1, 2026',
        revealId: v4,
      );

      final decoded = FavoriteItem.decodeCurrent(item.encode());

      expect(decoded.revealId, v4);
    });

    test('a v5 revealId round-trips through encode/decode losslessly', () {
      const v5 = '6fa459ea-ee8a-5ca4-894e-db77e160355e';
      final item = FavoriteItem(
        id: 'legacy-v1-0-abcdef01',
        text: 'Be still.',
        date: 'August 1, 2026',
        revealId: v5,
      );

      final decoded = FavoriteItem.decodeCurrent(item.encode());

      expect(decoded.revealId, v5);
    });

    test('encode() includes the revealId key exactly when non-null', () {
      const v4 = '3f2e1a4c-9b7d-4a6e-8c1f-0d2b5e7a9c11';
      final withRevealId = FavoriteItem(
        id: 'a',
        text: 'b',
        date: 'August 1, 2026',
        revealId: v4,
      );
      final withoutRevealId = FavoriteItem(
        id: 'a',
        text: 'b',
        date: 'August 1, 2026',
      );

      final decodedWith = jsonDecode(withRevealId.encode()) as Map;
      final decodedWithout = jsonDecode(withoutRevealId.encode()) as Map;

      expect(decodedWith['revealId'], v4);
      expect(decodedWithout.containsKey('revealId'), isFalse);
    });
  });

  group('copyWith preserves revealId across reflection edits', () {
    const v4 = '3f2e1a4c-9b7d-4a6e-8c1f-0d2b5e7a9c11';

    test('adding a reflection via copyWith preserves revealId', () {
      final item = FavoriteItem(
        id: 'a',
        text: 'b',
        date: 'August 1, 2026',
        revealId: v4,
      );

      final withReflection = item.copyWith(
        reflection: 'A quiet morning.',
        reflectedAt: '2026-08-01T09:00:00.000Z',
      );

      expect(withReflection.revealId, v4);
    });

    test('editing an existing reflection via copyWith preserves revealId', () {
      final item = FavoriteItem(
        id: 'a',
        text: 'b',
        date: 'August 1, 2026',
        reflection: 'Old reflection.',
        reflectedAt: '2026-08-01T09:00:00.000Z',
        revealId: v4,
      );

      final edited = item.copyWith(reflection: 'New reflection.');

      expect(edited.revealId, v4);
      expect(edited.reflection, 'New reflection.');
    });

    test('clearing a reflection via copyWith preserves revealId', () {
      final item = FavoriteItem(
        id: 'a',
        text: 'b',
        date: 'August 1, 2026',
        reflection: 'Old reflection.',
        reflectedAt: '2026-08-01T09:00:00.000Z',
        revealId: v4,
      );

      final cleared = item.copyWith(clearReflection: true);

      expect(cleared.revealId, v4);
      expect(cleared.reflection, isNull);
    });

    test(
        'copyWith with no revealId argument preserves a null revealId as '
        'null (never invents one)', () {
      final item = FavoriteItem(id: 'a', text: 'b', date: 'August 1, 2026');

      final edited = item.copyWith(reflection: 'A quiet morning.');

      expect(edited.revealId, isNull);
    });
  });

  group('invalid revealId is rejected', () {
    test('a malformed revealId string is rejected', () {
      final raw = jsonEncode({
        'schemaVersion': 2,
        'id': 'a',
        'date': 'August 1, 2026',
        'text': 'b',
        'revealId': 'not-a-uuid',
      });

      expect(
        () => FavoriteItem.decodeCurrent(raw),
        throwsA(isA<FormatException>()),
      );
    });

    test(
        'a version-1 UUID-shaped revealId is rejected (only v4/v5 '
        'accepted)', () {
      final raw = jsonEncode({
        'schemaVersion': 2,
        'id': 'a',
        'date': 'August 1, 2026',
        'text': 'b',
        // version nibble '1', not '4' or '5'.
        'revealId': '3f2e1a4c-9b7d-1a6e-8c1f-0d2b5e7a9c11',
      });

      expect(
        () => FavoriteItem.decodeCurrent(raw),
        throwsA(isA<FormatException>()),
      );
    });

    test('a non-string revealId value is rejected', () {
      final raw = jsonEncode({
        'schemaVersion': 2,
        'id': 'a',
        'date': 'August 1, 2026',
        'text': 'b',
        'revealId': 12345,
      });

      expect(
        () => FavoriteItem.decodeCurrent(raw),
        throwsA(isA<FormatException>()),
      );
    });

    test('a valid revealId is never silently trimmed or rewritten', () {
      const v4 = '3F2E1A4C-9B7D-4A6E-8C1F-0D2B5E7A9C11';
      final raw = jsonEncode({
        'schemaVersion': 2,
        'id': 'a',
        'date': 'August 1, 2026',
        'text': 'b',
        'revealId': v4,
      });

      final item = FavoriteItem.decodeCurrent(raw);

      expect(item.revealId, v4);
    });
  });

  group('null revealId encoding remains backward compatible', () {
    test('an item with no revealId encodes with no revealId key at all', () {
      final item = FavoriteItem(id: 'a', text: 'b', date: 'August 1, 2026');

      final decoded = jsonDecode(item.encode()) as Map;

      expect(decoded.containsKey('revealId'), isFalse);
    });

    test(
        'the exact JSON shape for an item without a revealId is unchanged '
        'from before this field existed', () {
      final item = FavoriteItem(id: 'a', text: 'b', date: 'August 1, 2026');

      expect(
        item.encode(),
        jsonEncode({
          'schemaVersion': 2,
          'id': 'a',
          'date': 'August 1, 2026',
          'text': 'b',
        }),
      );
    });
  });

  group('Reflection length compatibility', () {
    test('old schema-2 records with 250 characters still decode', () {
      final item = FavoriteItem.decodeCurrent(jsonEncode({
        'schemaVersion': 2,
        'id': 'legacy-reflection',
        'date': 'August 1, 2026',
        'text': 'Be still.',
        'reflection': 'x' * 250,
      }));

      expect(item.reflection, 'x' * 250);
    });

    test('schema-2 decoding uses the shared 1000-grapheme limit', () {
      final atLimit = jsonEncode({
        'schemaVersion': 2,
        'id': 'emoji-reflection',
        'date': 'August 1, 2026',
        'text': 'Be still.',
        'reflection': List.filled(1000, '👨‍👩‍👧‍👦').join(),
      });
      final overLimit = jsonEncode({
        'schemaVersion': 2,
        'id': 'emoji-reflection',
        'date': 'August 1, 2026',
        'text': 'Be still.',
        'reflection': List.filled(1001, '👨‍👩‍👧‍👦').join(),
      });

      expect(() => FavoriteItem.decodeCurrent(atLimit), returnsNormally);
      expect(
          () => FavoriteItem.decodeCurrent(overLimit), throwsFormatException);
    });
  });
}
