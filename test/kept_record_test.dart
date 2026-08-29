import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_record.dart';

void main() {
  // Fixed fixtures only — no random UUID generation in pure serialization
  // tests.
  const revealIdV4 = '123e4567-e89b-42d3-a456-426614174000';
  const revealIdV5 = '123e4567-e89b-52d3-a456-426614174000';
  const mutationIdV4 = 'a1b2c3d4-0000-4000-8000-000000000001';

  final revealedAt = DateTime.utc(2026, 6, 18, 9, 30);
  final keptAt = DateTime.utc(2026, 6, 18, 9, 31);
  final reflectedAt = DateTime.utc(2026, 6, 18, 21, 0);
  final updatedAt = DateTime.utc(2026, 6, 18, 21, 0);

  KeptRecord buildRecord({
    String id = 'kept-1',
    String revealId = revealIdV4,
    String wisdomText = 'What is meant for you does not panic.',
    DateTime? revealedAtValue,
    DateTime? keptAtValue,
    String? reflectionText,
    DateTime? reflectedAtValue,
    DateTime? updatedAtValue,
    String mutationId = mutationIdV4,
  }) {
    return KeptRecord(
      id: id,
      revealId: revealId,
      wisdomText: wisdomText,
      revealedAt: revealedAtValue ?? revealedAt,
      keptAt: keptAtValue ?? keptAt,
      reflectionText: reflectionText,
      reflectedAt: reflectedAtValue,
      updatedAt: updatedAtValue ?? updatedAt,
      mutationId: mutationId,
    );
  }

  test('complete record round-trips through encode/decode', () {
    final original = buildRecord(
      reflectionText: 'Stayed with me.',
      reflectedAtValue: reflectedAt,
    );

    final decoded = KeptRecord.decode(original.encode());

    expect(decoded, original);
    expect(decoded.reflectionText, 'Stayed with me.');
    expect(decoded.reflectedAt, reflectedAt);
  });

  test('record without reflection round-trips through encode/decode', () {
    final original = buildRecord();

    final decoded = KeptRecord.decode(original.encode());

    expect(decoded, original);
    expect(decoded.reflectionText, isNull);
    expect(decoded.reflectedAt, isNull);
  });

  test('non-UTC input is normalized to UTC without changing the instant', () {
    final localRevealedAt = DateTime(2026, 6, 18, 12, 30);
    final localKeptAt = DateTime(2026, 6, 18, 12, 31);
    final localUpdatedAt = DateTime(2026, 6, 18, 12, 31);
    final localReflectedAt = DateTime(2026, 6, 18, 20, 0);

    final record = buildRecord(
      revealedAtValue: localRevealedAt,
      keptAtValue: localKeptAt,
      updatedAtValue: localUpdatedAt,
      reflectionText: 'Local time reflection.',
      reflectedAtValue: localReflectedAt,
    );

    expect(record.revealedAt.isUtc, isTrue);
    expect(record.keptAt.isUtc, isTrue);
    expect(record.updatedAt.isUtc, isTrue);
    expect(record.reflectedAt!.isUtc, isTrue);
    expect(
      record.revealedAt.millisecondsSinceEpoch,
      localRevealedAt.millisecondsSinceEpoch,
    );
    expect(
      record.keptAt.millisecondsSinceEpoch,
      localKeptAt.millisecondsSinceEpoch,
    );
    expect(
      record.updatedAt.millisecondsSinceEpoch,
      localUpdatedAt.millisecondsSinceEpoch,
    );
    expect(
      record.reflectedAt!.millisecondsSinceEpoch,
      localReflectedAt.millisecondsSinceEpoch,
    );
  });

  test('canonical UUID v4 revealId is accepted', () {
    expect(() => buildRecord(revealId: revealIdV4), returnsNormally);
  });

  test('canonical UUID v5 revealId is accepted', () {
    expect(() => buildRecord(revealId: revealIdV5), returnsNormally);
  });

  test('v1, v3, and other non-4/5 UUID versions are rejected as revealId', () {
    const v1 = '123e4567-e89b-12d3-a456-426614174000';
    const v3 = '123e4567-e89b-32d3-a456-426614174000';
    const v2 = '123e4567-e89b-22d3-a456-426614174000';
    const v6 = '123e4567-e89b-62d3-a456-426614174000';

    for (final invalid in [v1, v3, v2, v6]) {
      expect(
        () => buildRecord(revealId: invalid),
        throwsFormatException,
        reason: 'Expected $invalid to be rejected.',
      );
    }
  });

  test('invalid UUID variant nibble is rejected', () {
    const invalidVariant = '123e4567-e89b-42d3-c456-426614174000';

    expect(
      () => buildRecord(revealId: invalidVariant),
      throwsFormatException,
    );
  });

  test('whitespace-padded UUID is rejected', () {
    const padded = ' 123e4567-e89b-42d3-a456-426614174000 ';

    expect(() => buildRecord(revealId: padded), throwsFormatException);
  });

  test('malformed UUID is rejected', () {
    const noHyphens = '123e4567e89b42d3a456426614174000';
    const braced = '{123e4567-e89b-42d3-a456-426614174000}';
    const garbage = 'not-a-uuid';

    for (final invalid in [noHyphens, braced, garbage]) {
      expect(
        () => buildRecord(revealId: invalid),
        throwsFormatException,
        reason: 'Expected $invalid to be rejected.',
      );
    }
  });

  test('non-UUID legacy id remains accepted as record id', () {
    expect(
      () => buildRecord(id: 'legacy-v1-3-a1b2c3d4'),
      returnsNormally,
    );
    expect(
      () => buildRecord(id: 'sr-v1-1737400000000-2'),
      returnsNormally,
    );
  });

  test('blank id is rejected', () {
    expect(() => buildRecord(id: '   '), throwsFormatException);
    expect(() => buildRecord(id: ''), throwsFormatException);
  });

  test('blank wisdomText is rejected', () {
    expect(() => buildRecord(wisdomText: '   '), throwsFormatException);
    expect(() => buildRecord(wisdomText: ''), throwsFormatException);
  });

  test('blank reflectionText is rejected', () {
    expect(
      () => buildRecord(reflectionText: '   '),
      throwsFormatException,
    );
  });

  test('reflection limit is 1000 user-perceived characters', () {
    final acceptedEmojiReflection = List.filled(1000, '👨‍👩‍👧‍👦').join();
    expect(
      () => buildRecord(
        reflectionText: acceptedEmojiReflection,
        reflectedAtValue: reflectedAt,
      ),
      returnsNormally,
    );

    final exactlyAtLimit = List.filled(1000, 'a').join();
    expect(
      () => buildRecord(
        reflectionText: exactlyAtLimit,
        reflectedAtValue: reflectedAt,
      ),
      returnsNormally,
    );

    final overLimit = List.filled(1001, 'a').join();
    expect(
      () => buildRecord(
        reflectionText: overLimit,
        reflectedAtValue: reflectedAt,
      ),
      throwsFormatException,
    );

    final overLimitEmoji = List.filled(1001, '👨‍👩‍👧‍👦').join();
    expect(
      () => buildRecord(
        reflectionText: overLimitEmoji,
        reflectedAtValue: reflectedAt,
      ),
      throwsFormatException,
    );
  });

  test('an existing 250-character schema-3 record remains decodable', () {
    final encoded = buildRecord(
      reflectionText: 'x' * 250,
      reflectedAtValue: reflectedAt,
    ).encode();

    final decoded = KeptRecord.decode(encoded);

    expect(decoded.reflectionText, 'x' * 250);
    expect(decoded.encode()['schemaVersion'], 3);
  });

  test('reflectedAt without reflectionText is rejected', () {
    expect(
      () => buildRecord(reflectedAtValue: reflectedAt),
      throwsFormatException,
    );
  });

  test('reflectionText with null reflectedAt is accepted', () {
    expect(
      () => buildRecord(reflectionText: 'Not yet dated.'),
      returnsNormally,
    );
  });

  test('updatedAt earlier than keptAt is rejected', () {
    expect(
      () => buildRecord(
        updatedAtValue: keptAt.subtract(const Duration(minutes: 1)),
      ),
      throwsFormatException,
    );
  });

  test('unsupported schema version is rejected on decode', () {
    final map = buildRecord().encode();
    map['schemaVersion'] = 2;

    expect(() => KeptRecord.decode(map), throwsFormatException);
  });

  test('missing required key is rejected on decode', () {
    final map = buildRecord().encode();
    map.remove('wisdomText');

    expect(() => KeptRecord.decode(map), throwsFormatException);
  });

  test('wrong field type is rejected on decode', () {
    final map = buildRecord().encode();
    map['revealedAtMs'] = 'not-an-int';

    expect(() => KeptRecord.decode(map), throwsFormatException);
  });

  test('unknown additive key is ignored on decode', () {
    final map = buildRecord().encode();
    map['futureSyncField'] = 'reserved for a later phase';

    expect(() => KeptRecord.decode(map), returnsNormally);
    expect(KeptRecord.decode(map), buildRecord());
  });

  test('copyWith preserves id and revealId and every other identity field', () {
    final original = buildRecord();

    final updated = original.copyWith(
      reflectionText: 'A new reflection.',
      reflectedAt: reflectedAt,
    );

    expect(updated.id, original.id);
    expect(updated.revealId, original.revealId);
    expect(updated.wisdomText, original.wisdomText);
    expect(updated.revealedAt, original.revealedAt);
    expect(updated.keptAt, original.keptAt);
    expect(updated.reflectionText, 'A new reflection.');
    expect(updated.reflectedAt, reflectedAt);
  });

  test('clearReflection clears both reflectionText and reflectedAt', () {
    final withReflection = buildRecord(
      reflectionText: 'Something kept.',
      reflectedAtValue: reflectedAt,
    );

    final cleared = withReflection.copyWith(clearReflection: true);

    expect(cleared.reflectionText, isNull);
    expect(cleared.reflectedAt, isNull);
    expect(cleared.id, withReflection.id);
    expect(cleared.revealId, withReflection.revealId);
  });

  test('value equality and hashCode are based on field values, not identity',
      () {
    final first = buildRecord(
      reflectionText: 'Same content.',
      reflectedAtValue: reflectedAt,
    );
    final second = buildRecord(
      reflectionText: 'Same content.',
      reflectedAtValue: reflectedAt,
    );
    final different = buildRecord(
      reflectionText: 'Different content.',
      reflectedAtValue: reflectedAt,
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first, isNot(different));
  });

  test('encode/encodeString produce a deterministic, exact key/value shape',
      () {
    final record = buildRecord(
      id: 'kept-1',
      revealId: revealIdV4,
      wisdomText: 'What is meant for you does not panic.',
      reflectionText: 'Stayed with me.',
      reflectedAtValue: reflectedAt,
      mutationId: mutationIdV4,
    );

    final encoded = record.encode();

    // 'What is meant for you does not panic.' is itself a real canonical
    // wisdom (east_wisdom_0001) with no ambiguous duplicate, so the
    // constructor's historical-recovery resolver (Build 33) correctly
    // populates wisdomId even though this fixture never passed one in.
    expect(encoded, {
      'schemaVersion': 3,
      'id': 'kept-1',
      'revealId': revealIdV4,
      'wisdomText': 'What is meant for you does not panic.',
      'wisdomId': 'east_wisdom_0001',
      'revealedAtMs': revealedAt.millisecondsSinceEpoch,
      'keptAtMs': keptAt.millisecondsSinceEpoch,
      'reflectionText': 'Stayed with me.',
      'reflectedAtMs': reflectedAt.millisecondsSinceEpoch,
      'updatedAtMs': updatedAt.millisecondsSinceEpoch,
      'mutationId': mutationIdV4,
    });

    final encodedAgain = record.encode();
    expect(encodedAgain, encoded);

    final roundTripped = KeptRecord.decodeString(record.encodeString());
    expect(roundTripped, record);
    expect(jsonDecode(record.encodeString()), encoded);
  });
}
