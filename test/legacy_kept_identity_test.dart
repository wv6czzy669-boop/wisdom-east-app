// Build 26 Phase 3D-E safety-gap correction, round 2: dedicated coverage for
// `parseLegacySavedReflectionId` -- the genuinely timezone-independent
// legacy save-instant parser that replaced an earlier, rejected
// `DateTime.toLocal()`-based calendar-day rule in
// `KeptRepository.reconcileMigratedRevealId`.
//
// The exact Build 25 source this mirrors
// (`lib/services/saved_reflections_service.dart`, present in this
// repository's history prior to commit `046dd36` "Complete protected Kept
// storage cutover"):
//
//   String _createId() {
//     final now = DateTime.now().microsecondsSinceEpoch;
//     final serial = _generatedIdSerial++;
//     return 'sr-v1-$now-$serial';
//   }
//
// `now` is `DateTime.now().microsecondsSinceEpoch` -- always the absolute
// Unix epoch microsecond count, identical regardless of the device's
// timezone at the moment the item was Kept.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/utils/legacy_kept_identity.dart';

void main() {
  group('parseLegacySavedReflectionId', () {
    test(
        '1. parses the exact real physical-device fixture id, recovering '
        'its documented embedded UTC instant', () {
      final info = parseLegacySavedReflectionId('sr-v1-1785622374122602-0');

      expect(info, isNotNull);
      // Independently verified: 1785622374122602 microseconds since epoch
      // == 2026-08-01T22:12:54.122602Z (about 13 seconds before this same
      // fixture's own reflectedAt local wall-clock reading of
      // 2026-08-02T01:13:07.484133 in UTC+03:00).
      expect(
        info!.savedAt,
        DateTime.utc(2026, 8, 1, 22, 12, 54, 122, 602),
      );
      expect(info.savedAt.isUtc, isTrue);
    });

    test('2. parses a multi-digit serial component', () {
      final info = parseLegacySavedReflectionId('sr-v1-1700000000000000-42');

      expect(info, isNotNull);
      expect(
        info!.savedAt,
        DateTime.fromMicrosecondsSinceEpoch(1700000000000000, isUtc: true),
      );
    });

    test('3. parses a zero microsecond value', () {
      final info = parseLegacySavedReflectionId('sr-v1-0-0');

      expect(info, isNotNull);
      expect(info!.savedAt, DateTime.utc(1970, 1, 1));
    });

    test('4. rejects a `legacy-v1-<index>-<hash>` id (no timestamp at all)',
        () {
      expect(
        parseLegacySavedReflectionId('legacy-v1-3-abcd1234'),
        isNull,
      );
    });

    test(
        '5. rejects a `duplicate-v1-<index>-<hash>` id (no timestamp at '
        'all)', () {
      expect(
        parseLegacySavedReflectionId('duplicate-v1-2-deadbeef'),
        isNull,
      );
    });

    test('6. rejects a non-numeric microsecond component', () {
      expect(
        parseLegacySavedReflectionId('sr-v1-not-a-number-0'),
        isNull,
      );
    });

    test('7. rejects a missing serial segment', () {
      expect(
        parseLegacySavedReflectionId('sr-v1-1785622374122602'),
        isNull,
      );
    });

    test('8. rejects a negative-looking microsecond component', () {
      expect(
        parseLegacySavedReflectionId('sr-v1--1785622374122602-0'),
        isNull,
      );
    });

    test('9. rejects a non-numeric serial component', () {
      expect(
        parseLegacySavedReflectionId('sr-v1-1785622374122602-abc'),
        isNull,
      );
    });

    test('10. rejects trailing garbage after the serial component', () {
      expect(
        parseLegacySavedReflectionId('sr-v1-1785622374122602-0-extra'),
        isNull,
      );
    });

    test('11. rejects an empty string', () {
      expect(parseLegacySavedReflectionId(''), isNull);
    });

    test(
        '12. rejects a raw canonical UUID (an ordinary Build 26 id shape, '
        'never a legacy id)', () {
      expect(
        parseLegacySavedReflectionId(
          '11111111-1111-4111-8111-111111111111',
        ),
        isNull,
      );
    });

    test('13. rejects a bare "sr-v1" prefix with nothing else', () {
      expect(parseLegacySavedReflectionId('sr-v1'), isNull);
    });

    test('14. rejects extra segments between the prefix and the numbers', () {
      expect(
        parseLegacySavedReflectionId('sr-v1-extra-1785622374122602-0'),
        isNull,
      );
    });
  });

  group('deriveLegacyMigrationRevealId', () {
    test(
        '15. is a pure, deterministic function of the legacy id -- the same '
        'id always derives the same revealId', () {
      const legacyId = 'sr-v1-1785622374122602-0';

      final first = deriveLegacyMigrationRevealId(legacyId);
      final second = deriveLegacyMigrationRevealId(legacyId);

      expect(first, second);
    });

    test('16. different legacy ids derive different revealIds', () {
      final a = deriveLegacyMigrationRevealId('sr-v1-1785622374122602-0');
      final b = deriveLegacyMigrationRevealId('sr-v1-1785622374122602-1');

      expect(a, isNot(b));
    });

    test('17. an injected uuidV5Factory overrides the default derivation', () {
      final result = deriveLegacyMigrationRevealId(
        'sr-v1-1785622374122602-0',
        uuidV5Factory: (name) => 'forced-value-for-$name'.substring(0, 12),
      );

      expect(
          result,
          isNot(deriveLegacyMigrationRevealId(
            'sr-v1-1785622374122602-0',
          )));
    });
  });
}
