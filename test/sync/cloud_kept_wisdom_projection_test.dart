// Build 26 Phase 4A: CloudKeptWisdomProjection -- the CloudKit-safe
// projection of a saved reveal occurrence. See
// docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §2.3/§2.4/§2.6.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_record_identity.dart';
import 'package:wisdom_app/sync/sync_tombstone.dart';

void main() {
  const revealIdA = 'c947bbb4-f86a-4db3-87c9-ed5e718bbd98';
  const revealIdB = 'affbc527-29c4-5d19-b678-1bc7f9dfb7d4';
  const mutationId = '22222222-2222-4222-8222-222222222222';
  final epoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
  final revealedAt = DateTime.utc(2026, 8, 1, 20, 0);
  final keptAt = DateTime.utc(2026, 8, 1, 20, 5);
  final updatedAt = DateTime.utc(2026, 8, 1, 20, 5);

  KeptRecord buildRecord({
    String revealId = revealIdA,
    String wisdomText = 'Be still and know.',
    String? reflectionText,
    DateTime? reflectedAt,
  }) {
    return KeptRecord(
      id: 'local-id-1',
      revealId: revealId,
      wisdomText: wisdomText,
      revealedAt: revealedAt,
      keptAt: keptAt,
      reflectionText: reflectionText,
      reflectedAt: reflectedAt,
      updatedAt: updatedAt,
      mutationId: mutationId,
    );
  }

  group('active form', () {
    test(
        '1. recordName is derived from revealId, matching '
        'deriveKeptWisdomRecordName exactly', () {
      final projection =
          CloudKeptWisdomProjection.active(buildRecord(), dataEpoch: epoch);
      expect(projection.recordName, deriveKeptWisdomRecordName(revealIdA));
      expect(projection.isTombstone, isFalse);
    });

    test('2. carries every identity and content field verbatim', () {
      final record = buildRecord(
        reflectionText: 'A quiet thought.',
        reflectedAt: updatedAt,
      );
      final projection =
          CloudKeptWisdomProjection.active(record, dataEpoch: epoch);

      expect(projection.revealId, revealIdA);
      expect(projection.wisdomText, 'Be still and know.');
      expect(projection.reflectionText, 'A quiet thought.');
      expect(projection.mutationId, mutationId);
      expect(projection.dataEpoch, epoch);
      expect(projection.schemaVersion, KeptRecord.currentSchemaVersion);
      expect(projection.revealedAtMs, revealedAt.millisecondsSinceEpoch);
      expect(projection.keptAtMs, keptAt.millisecondsSinceEpoch);
      expect(projection.reflectedAtMs, updatedAt.millisecondsSinceEpoch);
    });

    test(
        '3. reflectionText/reflectedAt are absent (not empty-string) when '
        'there is no Reflection', () {
      final projection =
          CloudKeptWisdomProjection.active(buildRecord(), dataEpoch: epoch);
      expect(projection.reflectionText, isNull);
      expect(projection.reflectedAtMs, isNull);
    });

    test('4. deletedAtMs is never present on the active form', () {
      final projection =
          CloudKeptWisdomProjection.active(buildRecord(), dataEpoch: epoch);
      expect(projection.deletedAtMs, isNull);
    });

    test('5. rejects wisdomText over the defensive sync payload limit', () {
      final oversized =
          'x' * (CloudKeptWisdomProjection.maximumWisdomTextLength + 1);
      expect(
        () => CloudKeptWisdomProjection.active(
          buildRecord(wisdomText: oversized),
          dataEpoch: epoch,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test(
        '6. same wisdom text with different revealIds produces different '
        'record names -- never merged, never treated as the same '
        'occurrence', () {
      final projectionA =
          CloudKeptWisdomProjection.active(buildRecord(), dataEpoch: epoch);
      final projectionB = CloudKeptWisdomProjection.active(
        buildRecord(revealId: revealIdB),
        dataEpoch: epoch,
      );

      expect(projectionA.wisdomText, projectionB.wisdomText);
      expect(projectionA.recordName, isNot(projectionB.recordName));
      expect(projectionA.revealId, isNot(projectionB.revealId));
    });

    test(
        '7. timestamps canonicalize sub-millisecond precision away, so '
        'encode/decode-equivalent round-trip never drifts', () {
      final withMicros = buildRecord().copyWith(
        updatedAt: updatedAt.add(const Duration(microseconds: 777)),
      );
      final projection =
          CloudKeptWisdomProjection.active(withMicros, dataEpoch: epoch);
      // The projection stores whole milliseconds; reconstructing a DateTime
      // from them must reproduce exactly the same instant with zero
      // microsecond remainder -- proving no drift survives the projection.
      final reconstructed = DateTime.fromMillisecondsSinceEpoch(
          projection.updatedAtMs,
          isUtc: true);
      expect(reconstructed.microsecond, 0);
      expect(
        reconstructed.millisecondsSinceEpoch,
        updatedAt.millisecondsSinceEpoch,
      );
    });
  });

  group('tombstone form', () {
    SyncTombstone buildTombstone({String revealId = revealIdA}) =>
        SyncTombstone(
          revealId: revealId,
          dataEpoch: epoch,
          updatedAt: updatedAt,
          deletedAt: updatedAt,
          mutationId: mutationId,
        );

    test(
        '8. recordName matches the active form of the same revealId '
        '-- identity never changes on transition to tombstone', () {
      final activeProjection =
          CloudKeptWisdomProjection.active(buildRecord(), dataEpoch: epoch);
      final tombstoneProjection =
          CloudKeptWisdomProjection.tombstone(buildTombstone());

      expect(tombstoneProjection.recordName, activeProjection.recordName);
    });

    test('9. carries no identity or content field at all', () {
      final projection = CloudKeptWisdomProjection.tombstone(buildTombstone());

      expect(projection.isTombstone, isTrue);
      expect(projection.revealId, isNull);
      expect(projection.wisdomText, isNull);
      expect(projection.revealedAtMs, isNull);
      expect(projection.keptAtMs, isNull);
      expect(projection.reflectionText, isNull);
      expect(projection.reflectedAtMs, isNull);
      expect(projection.deletedAtMs, isNotNull);
    });

    test(
        '10. schemaVersion is the tombstone type\'s own, independent '
        'schema version', () {
      final projection = CloudKeptWisdomProjection.tombstone(buildTombstone());
      expect(projection.schemaVersion, SyncTombstone.currentSchemaVersion);
      expect(projection.schemaVersion, isNot(KeptRecord.currentSchemaVersion));
    });
  });

  group('privacy', () {
    test('11. toLogSafeSummary never includes wisdomText or reflectionText',
        () {
      final record = buildRecord(reflectionText: 'Never log this.');
      final projection =
          CloudKeptWisdomProjection.active(record, dataEpoch: epoch);

      final summary = projection.toLogSafeSummary();
      expect(summary.containsKey('wisdomText'), isFalse);
      expect(summary.containsKey('reflectionText'), isFalse);
      expect(summary.values, isNot(contains('Never log this.')));
      expect(summary.values, isNot(contains('Be still and know.')));
      expect(summary['hasReflection'], isTrue);
    });

    test('12. toLogSafeSummary on a tombstone contains only identifiers/flags',
        () {
      final projection = CloudKeptWisdomProjection.tombstone(
        SyncTombstone(
          revealId: revealIdA,
          dataEpoch: epoch,
          updatedAt: updatedAt,
          deletedAt: updatedAt,
          mutationId: mutationId,
        ),
      );
      final summary = projection.toLogSafeSummary();
      expect(summary['isTombstone'], isTrue);
      expect(summary['hasReflection'], isFalse);
    });
  });

  group('tryParseRemote -- malformed records fail closed', () {
    Map<String, dynamic> validActiveFields() => {
          'recordName': deriveKeptWisdomRecordName(revealIdA),
          'schemaVersion': KeptRecord.currentSchemaVersion,
          'isTombstone': false,
          'revealId': revealIdA,
          'wisdomText': 'Be still and know.',
          'revealedAtMs': revealedAt.millisecondsSinceEpoch,
          'keptAtMs': keptAt.millisecondsSinceEpoch,
          'updatedAtMs': updatedAt.millisecondsSinceEpoch,
          'mutationId': mutationId,
          'dataEpoch': epoch.value,
        };

    test('13. a well-formed active record parses successfully', () {
      final parsed =
          CloudKeptWisdomProjection.tryParseRemote(validActiveFields());
      expect(parsed, isNotNull);
      expect(parsed!.revealId, revealIdA);
    });

    test('14. missing schemaVersion fails closed', () {
      final fields = validActiveFields()..remove('schemaVersion');
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test('15. unrecognized schemaVersion fails closed', () {
      final fields = validActiveFields()..['schemaVersion'] = 999;
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test('16. missing isTombstone fails closed (never defaulted)', () {
      final fields = validActiveFields()..remove('isTombstone');
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test('17. a noncanonical revealId fails closed', () {
      final fields = validActiveFields()..['revealId'] = 'not-a-uuid';
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test(
        '18. a recordName that does not match the derivation of its own '
        'revealId fails closed', () {
      final fields = validActiveFields()..['recordName'] = 'east-kept-mismatch';
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test('19. an over-limit wisdomText fails closed', () {
      final fields = validActiveFields()
        ..['wisdomText'] =
            'x' * (CloudKeptWisdomProjection.maximumWisdomTextLength + 1);
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test('20. an over-limit reflectionText fails closed', () {
      final fields = validActiveFields()
        ..['reflectionText'] = 'x' * (KeptRecord.maximumReflectionLength + 1);
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test('21. reflectedAtMs present without reflectionText fails closed', () {
      final fields = validActiveFields()
        ..['reflectedAtMs'] = updatedAt.millisecondsSinceEpoch;
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test('22. a malformed dataEpoch fails closed', () {
      final fields = validActiveFields()..['dataEpoch'] = 'not-a-uuid';
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test('23. a malformed mutationId fails closed', () {
      final fields = validActiveFields()..['mutationId'] = 'not-a-uuid';
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    Map<String, dynamic> validTombstoneFields() => {
          'recordName': deriveKeptWisdomRecordName(revealIdA),
          'schemaVersion': SyncTombstone.currentSchemaVersion,
          'isTombstone': true,
          'deletedAtMs': updatedAt.millisecondsSinceEpoch,
          'updatedAtMs': updatedAt.millisecondsSinceEpoch,
          'mutationId': mutationId,
          'dataEpoch': epoch.value,
        };

    test('24. a well-formed tombstone record parses successfully', () {
      final parsed =
          CloudKeptWisdomProjection.tryParseRemote(validTombstoneFields());
      expect(parsed, isNotNull);
      expect(parsed!.isTombstone, isTrue);
    });

    test('25. a tombstone missing deletedAtMs fails closed', () {
      final fields = validTombstoneFields()..remove('deletedAtMs');
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test(
        '26. a tombstone carrying wisdomText fails closed (malformed -- a '
        'real tombstone this client writes never has this shape)', () {
      final fields = validTombstoneFields()
        ..['wisdomText'] = 'Should never be here.';
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test(
        '27. a tombstone carrying revealId as a wire field fails closed '
        '(revealId is recoverable from recordName only)', () {
      final fields = validTombstoneFields()..['revealId'] = revealIdA;
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test('28. an unrecognized tombstone schemaVersion fails closed', () {
      final fields = validTombstoneFields()..['schemaVersion'] = 999;
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });

    test('29. a completely empty map fails closed without throwing', () {
      expect(CloudKeptWisdomProjection.tryParseRemote({}), isNull);
    });

    test(
        '30. one malformed field never crashes parsing of an otherwise '
        'well-formed record -- tryParseRemote never throws', () {
      final fields = validActiveFields()..['updatedAtMs'] = 'not-an-int';
      expect(
        () => CloudKeptWisdomProjection.tryParseRemote(fields),
        returnsNormally,
      );
      expect(CloudKeptWisdomProjection.tryParseRemote(fields), isNull);
    });
  });
}
