// Build 26 Phase 3D-E (safety-gap correction, round 4): dedicated coverage
// for `DailyWisdomRecord.encode`/`decode`'s `revealId` shape validation.
//
// Root-caused defect this file directly targets: `_readOptionalRevealId`
// previously accepted only a canonical UUID v4 (a locally-duplicated regex
// pattern, `_canonicalUuidV4Pattern`, distinct from the shared
// `lib/utils/canonical_uuid.dart` helper already used by `KeptRecord` and
// `FavoriteItem`). A genuine migrated UUID v5 -- exactly what
// `DailyAccessRepository.reconcileRevealIdForOccurrence` legitimately
// writes for a Build 25 occurrence already Kept before the Build 26
// upgrade -- was therefore silently rejected on the very next decode
// (read-back), which `_applyRevealIdCorrection` then (correctly, given its
// own contract) treated as a failed verification and reverted. The write
// always happened; it was always undone one line later. The fix widens
// `_readOptionalRevealId` to `isSupportedRevealId` (v4 or v5), matching the
// policy already used for `KeptRecord.revealId`/`FavoriteItem.revealId`.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';

void main() {
  final revealedAt = DateTime.utc(2026, 8, 1, 20, 0);
  final unlockAt = revealedAt.add(DailyWisdomRecord.lockDuration);

  // The exact two identifiers from the reported Mac evidence.
  const existingV4 = 'c947bbb4-f86a-4db3-87c9-ed5e718bbd98';
  const resolvedMigratedV5 = 'affbc527-29c4-5d19-b678-1bc7f9dfb7d4';

  test(
      '1. a genuine Build 26-native v4 revealId still encodes and decodes '
      'correctly', () {
    final record = DailyWisdomRecord(
      text: 'Fresh Build 26 reveal',
      revealedAt: revealedAt,
      unlockAt: unlockAt,
      revealId: existingV4,
    );

    final decoded = DailyWisdomRecord.decode(record.encode());

    expect(decoded.revealId, existingV4);
    expect(decoded.text, record.text);
    expect(
      decoded.revealedAt.millisecondsSinceEpoch,
      record.revealedAt.millisecondsSinceEpoch,
    );
    expect(
      decoded.unlockAt.millisecondsSinceEpoch,
      record.unlockAt.millisecondsSinceEpoch,
    );
  });

  test(
      '2. a genuine migrated v5 revealId now encodes and decodes correctly '
      '(this is the exact fix -- previously threw FormatException on '
      'decode)', () {
    final record = DailyWisdomRecord(
      text: 'A Build 25 occurrence already Kept before the upgrade',
      revealedAt: revealedAt,
      unlockAt: unlockAt,
      revealId: resolvedMigratedV5,
    );

    final decoded = DailyWisdomRecord.decode(record.encode());

    expect(decoded.revealId, resolvedMigratedV5);
    expect(decoded.text, record.text);
  });

  test(
      '3. a record with no revealId at all still decodes (Build 25 '
      'pre-backfill compatibility)', () {
    final record = DailyWisdomRecord(
      text: 'Build 25 wisdom, not yet backfilled',
      revealedAt: revealedAt,
      unlockAt: unlockAt,
    );

    final decoded = DailyWisdomRecord.decode(record.encode());

    expect(decoded.revealId, isNull);
  });

  test('4. a malformed revealId string is rejected on decode', () {
    const malformed = '{"text":"x","revealedAtMs":0,"unlockAtMs":86400000,'
        '"revealId":"not-a-uuid"}';

    expect(
      () => DailyWisdomRecord.decode(malformed),
      throwsA(isA<FormatException>()),
    );
  });

  test(
      '5. an unsupported UUID version (v1) is rejected on decode, even '
      'though it is otherwise a well-formed RFC 4122 string', () {
    // Version nibble '1' (not '4' or '5'); variant nibble 'a' is valid.
    const unsupportedV1 = '{"text":"x","revealedAtMs":0,'
        '"unlockAtMs":86400000,'
        '"revealId":"11111111-1111-1111-a111-111111111111"}';

    expect(
      () => DailyWisdomRecord.decode(unsupportedV1),
      throwsA(isA<FormatException>()),
    );
  });

  test('6. an unsupported UUID version (v6) is rejected on decode', () {
    const unsupportedV6 = '{"text":"x","revealedAtMs":0,'
        '"unlockAtMs":86400000,'
        '"revealId":"11111111-1111-6111-a111-111111111111"}';

    expect(
      () => DailyWisdomRecord.decode(unsupportedV6),
      throwsA(isA<FormatException>()),
    );
  });

  test(
      '7. whitespace around an otherwise-valid v5 revealId is rejected -- '
      'never trimmed or coerced into shape', () {
    final padded = '{"text":"x","revealedAtMs":0,'
        '"unlockAtMs":86400000,'
        '"revealId":" $resolvedMigratedV5 "}';

    expect(
      () => DailyWisdomRecord.decode(padded),
      throwsA(isA<FormatException>()),
    );
  });

  test(
      '8. an invalid variant nibble on an otherwise v5-shaped revealId is '
      'rejected', () {
    // Version nibble '5' (correct), variant nibble 'c' (invalid; must be
    // 8/9/a/b).
    const invalidVariant = '{"text":"x","revealedAtMs":0,'
        '"unlockAtMs":86400000,'
        '"revealId":"11111111-1111-5111-c111-111111111111"}';

    expect(
      () => DailyWisdomRecord.decode(invalidVariant),
      throwsA(isA<FormatException>()),
    );
  });
}
