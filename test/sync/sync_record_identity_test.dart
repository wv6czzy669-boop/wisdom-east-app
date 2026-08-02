// Build 26 Phase 4A: deterministic CloudKit record-name derivation from the
// canonical revealId. See docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §2.2.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/sync_record_identity.dart';

void main() {
  const revealIdA = 'c947bbb4-f86a-4db3-87c9-ed5e718bbd98'; // v4
  const revealIdB = 'affbc527-29c4-5d19-b678-1bc7f9dfb7d4'; // v5 (migrated)

  test('1. deriveKeptWisdomRecordName is deterministic for the same revealId',
      () {
    final first = deriveKeptWisdomRecordName(revealIdA);
    final second = deriveKeptWisdomRecordName(revealIdA);
    expect(first, second);
  });

  test('2. two different revealIds never produce the same record name', () {
    final nameA = deriveKeptWisdomRecordName(revealIdA);
    final nameB = deriveKeptWisdomRecordName(revealIdB);
    expect(nameA, isNot(nameB));
  });

  test(
      '3. the record name is derived only from revealId, carrying it '
      'verbatim (never from wisdom text or a date)', () {
    final name = deriveKeptWisdomRecordName(revealIdA);
    expect(name, contains(revealIdA));
    expect(name, '$keptWisdomRecordNamePrefix$revealIdA');
  });

  test(
      '4. a v5 migrated revealId derives a record name exactly like a v4 '
      'native revealId (both are canonical identities)', () {
    expect(() => deriveKeptWisdomRecordName(revealIdB), returnsNormally);
  });

  test('5. a noncanonical revealId is rejected (malformed UUID)', () {
    expect(
      () => deriveKeptWisdomRecordName('not-a-uuid'),
      throwsA(isA<FormatException>()),
    );
  });

  test('6. a noncanonical revealId is rejected (unsupported UUID version)', () {
    // Version nibble '1' -- not v4 or v5.
    expect(
      () => deriveKeptWisdomRecordName(
        '11111111-1111-1111-a111-111111111111',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('7. an empty string is rejected', () {
    expect(
      () => deriveKeptWisdomRecordName(''),
      throwsA(isA<FormatException>()),
    );
  });

  test('8. whitespace-padded revealId is rejected, never trimmed', () {
    expect(
      () => deriveKeptWisdomRecordName(' $revealIdA '),
      throwsA(isA<FormatException>()),
    );
  });

  test(
      '9. the derived name can never collide with the sync-state singleton '
      'record name', () {
    final name = deriveKeptWisdomRecordName(revealIdA);
    expect(name, isNot(syncStateRecordName));
    expect(name.startsWith(keptWisdomRecordNamePrefix), isTrue);
  });

  test('10. recordNameMatchesRevealId confirms an exact match only', () {
    final name = deriveKeptWisdomRecordName(revealIdA);
    expect(recordNameMatchesRevealId(name, revealIdA), isTrue);
    expect(recordNameMatchesRevealId(name, revealIdB), isFalse);
  });

  test(
      '11. recordNameMatchesRevealId rejects a noncanonical revealId '
      'without throwing', () {
    expect(recordNameMatchesRevealId('east-kept-x', 'not-a-uuid'), isFalse);
  });

  test(
      '12. recordNameMatchesRevealId never matches a substring or '
      'case-varied name', () {
    final name = deriveKeptWisdomRecordName(revealIdA);
    expect(
        recordNameMatchesRevealId('prefix-$name-suffix', revealIdA), isFalse);
    expect(recordNameMatchesRevealId(name.toUpperCase(), revealIdA), isFalse);
  });
}
