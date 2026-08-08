// Build 26 Phase 4C-1: CloudKeptWisdomWireEnvelope -- the platform-channel
// wire boundary for CKKeptWisdom. See
// docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §2.3/§2.4/§2.6 and the
// Phase 4C-1 section this turn adds.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_record_identity.dart';
import 'package:wisdom_app/sync/sync_tombstone.dart';
import 'package:wisdom_app/sync_platform/cloud_kept_wisdom_wire_envelope.dart';

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

  Map<Object?, Object?> validRawActivePayload({
    String revealId = revealIdA,
    String wisdomText = 'Be still and know.',
  }) {
    return {
      'recordType': 'CKKeptWisdom',
      'zoneName': 'EASTKeptZone',
      'recordName': deriveKeptWisdomRecordName(revealId),
      'isTombstone': false,
      'revealId': revealId,
      'wisdomText': wisdomText,
      'revealedAtMs': revealedAt.millisecondsSinceEpoch,
      'keptAtMs': keptAt.millisecondsSinceEpoch,
      'updatedAtMs': updatedAt.millisecondsSinceEpoch,
      'mutationId': mutationId,
      'dataEpoch': epoch.value,
      'schemaVersion': KeptRecord.currentSchemaVersion,
    };
  }

  group('1. valid CKKeptWisdom payload', () {
    test('round-trips through encode/tryDecode unchanged', () {
      final projection =
          CloudKeptWisdomProjection.active(buildRecord(), dataEpoch: epoch);
      final wire = CloudKeptWisdomWireEnvelope.encode(projection);
      final decoded = CloudKeptWisdomWireEnvelope.tryDecode(wire);

      expect(decoded, isNotNull);
      expect(decoded, equals(projection));
    });

    test('a hand-built valid raw payload decodes successfully', () {
      final decoded =
          CloudKeptWisdomWireEnvelope.tryDecode(validRawActivePayload());
      expect(decoded, isNotNull);
      expect(decoded!.revealId, revealIdA);
      expect(decoded.wisdomText, 'Be still and know.');
    });
  });

  group('2. same wisdom text, different revealIds', () {
    test('remains distinct -- different recordName, not equal', () {
      final projectionA = CloudKeptWisdomProjection.active(
        buildRecord(revealId: revealIdA, wisdomText: 'Be still and know.'),
        dataEpoch: epoch,
      );
      final projectionB = CloudKeptWisdomProjection.active(
        buildRecord(revealId: revealIdB, wisdomText: 'Be still and know.'),
        dataEpoch: epoch,
      );

      final wireA = CloudKeptWisdomWireEnvelope.encode(projectionA);
      final wireB = CloudKeptWisdomWireEnvelope.encode(projectionB);
      final decodedA = CloudKeptWisdomWireEnvelope.tryDecode(wireA);
      final decodedB = CloudKeptWisdomWireEnvelope.tryDecode(wireB);

      expect(decodedA, isNotNull);
      expect(decodedB, isNotNull);
      expect(decodedA!.recordName, isNot(equals(decodedB!.recordName)));
      expect(decodedA, isNot(equals(decodedB)));
      // The duplicate wisdom text itself remains valid -- neither side is
      // rejected merely for sharing wisdomText with the other.
      expect(decodedA.wisdomText, decodedB.wisdomText);
    });
  });

  group('3. identical revealId', () {
    test('produces the identical, deterministic recordName every time', () {
      final first = CloudKeptWisdomWireEnvelope.tryDecode(
          validRawActivePayload(revealId: revealIdA));
      final second = CloudKeptWisdomWireEnvelope.tryDecode(
          validRawActivePayload(revealId: revealIdA));

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.recordName, second!.recordName);
      expect(first.recordName, deriveKeptWisdomRecordName(revealIdA));
    });
  });

  group('4. optional Reflection absent', () {
    test('decodes with reflectionText and reflectedAtMs both null', () {
      final projection =
          CloudKeptWisdomProjection.active(buildRecord(), dataEpoch: epoch);
      final decoded = CloudKeptWisdomWireEnvelope.tryDecode(
        CloudKeptWisdomWireEnvelope.encode(projection),
      );

      expect(decoded, isNotNull);
      expect(decoded!.reflectionText, isNull);
      expect(decoded.reflectedAtMs, isNull);
    });
  });

  group('5. Reflection present', () {
    test('decodes with reflectionText and reflectedAtMs both populated', () {
      final record = buildRecord(
        reflectionText: 'A quiet thought.',
        reflectedAt: updatedAt,
      );
      final projection =
          CloudKeptWisdomProjection.active(record, dataEpoch: epoch);
      final decoded = CloudKeptWisdomWireEnvelope.tryDecode(
        CloudKeptWisdomWireEnvelope.encode(projection),
      );

      expect(decoded, isNotNull);
      expect(decoded!.reflectionText, 'A quiet thought.');
      expect(decoded.reflectedAtMs, isNotNull);
    });
  });

  group('6. tombstone without content', () {
    test('round-trips with no identity/content field present', () {
      final tombstone = SyncTombstone(
        revealId: revealIdA,
        dataEpoch: epoch,
        updatedAt: updatedAt,
        deletedAt: updatedAt,
        mutationId: mutationId,
      );
      final projection = CloudKeptWisdomProjection.tombstone(tombstone);
      final wire = CloudKeptWisdomWireEnvelope.encode(projection);

      // The wire map itself must not carry any content/identity key at all
      // for a tombstone -- not merely a null value for one.
      expect(wire.containsKey('wisdomText'), isFalse);
      expect(wire.containsKey('reflectionText'), isFalse);
      expect(wire.containsKey('revealId'), isFalse);
      expect(wire.containsKey('revealedAtMs'), isFalse);
      expect(wire.containsKey('keptAtMs'), isFalse);

      final decoded = CloudKeptWisdomWireEnvelope.tryDecode(wire);
      expect(decoded, isNotNull);
      expect(decoded!.isTombstone, isTrue);
      expect(decoded.wisdomText, isNull);
      expect(decoded.revealId, isNull);
      expect(decoded.deletedAtMs, isNotNull);
      expect(decoded.recordName, deriveKeptWisdomRecordName(revealIdA));
    });
  });

  group('7. malformed revealId rejected', () {
    test('a non-canonical revealId fails closed (returns null)', () {
      final raw = validRawActivePayload()
        ..['revealId'] = 'not-a-real-uuid'
        ..['recordName'] = 'east-kept-not-a-real-uuid';
      expect(CloudKeptWisdomWireEnvelope.tryDecode(raw), isNull);
    });
  });

  group('8. wrong schema version rejected', () {
    test('an unrecognized active-form schemaVersion fails closed', () {
      final raw = validRawActivePayload()..['schemaVersion'] = 999;
      expect(CloudKeptWisdomWireEnvelope.tryDecode(raw), isNull);
    });
  });

  group('9. unknown record type rejected', () {
    test('a recordType other than CKKeptWisdom fails closed', () {
      final raw = validRawActivePayload()..['recordType'] = 'CKEastSyncState';
      expect(CloudKeptWisdomWireEnvelope.tryDecode(raw), isNull);
    });

    test('a completely unrecognized recordType fails closed', () {
      final raw = validRawActivePayload()..['recordType'] = 'CKSomethingElse';
      expect(CloudKeptWisdomWireEnvelope.tryDecode(raw), isNull);
    });
  });

  group('10. daily-access field rejected', () {
    // These names are test-only inputs proving the generic allowlist in
    // CloudKeptWisdomWireEnvelope.allowedKeys rejects them -- production
    // code never spells out a daily-access field name anywhere (see
    // docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §11 and
    // cloud_kept_wisdom_wire_envelope.dart's own doc comment).
    const daylyAccessShapedKeys = [
      'dailyWisdomAccess',
      'unlockAt',
      'unlockAtMs',
      'lockDurationMs',
      'dailyAccessState',
      'pendingDailyWisdomReveal',
    ];

    test(
        'a payload smuggling a daily-access-shaped key fails closed even '
        'though every other field is otherwise valid -- rejected purely by '
        'not being in the allowlist, exactly like any other unknown key', () {
      for (final forbidden in daylyAccessShapedKeys) {
        final raw = validRawActivePayload()..[forbidden] = 'anything';
        expect(
          CloudKeptWisdomWireEnvelope.tryDecode(raw),
          isNull,
          reason: 'Expected rejection for forbidden key "$forbidden"',
        );
      }
    });

    test('an entirely unrelated unknown key is rejected the same way', () {
      final raw = validRawActivePayload()..['someFutureField'] = 'anything';
      expect(CloudKeptWisdomWireEnvelope.tryDecode(raw), isNull);
    });
  });

  group('11. type mismatch rejected', () {
    test('wisdomText as a non-String fails closed', () {
      final raw = validRawActivePayload()..['wisdomText'] = 12345;
      expect(CloudKeptWisdomWireEnvelope.tryDecode(raw), isNull);
    });

    test('updatedAtMs as a non-int fails closed', () {
      final raw = validRawActivePayload()
        ..['updatedAtMs'] = '2026-08-01T20:05:00Z';
      expect(CloudKeptWisdomWireEnvelope.tryDecode(raw), isNull);
    });

    test('isTombstone as a non-bool fails closed', () {
      final raw = validRawActivePayload()..['isTombstone'] = 'false';
      expect(CloudKeptWisdomWireEnvelope.tryDecode(raw), isNull);
    });

    test('a non-String key anywhere in the raw map fails closed', () {
      final raw = validRawActivePayload();
      raw[42] = 'an int key, never valid on a wire map';
      expect(CloudKeptWisdomWireEnvelope.tryDecode(raw), isNull);
    });
  });

  group('12. content never appears in diagnostic strings', () {
    const secretWisdom =
        'This exact wisdom text must never appear in any diagnostic string.';
    const secretReflection =
        'This exact reflection text must never appear in any diagnostic '
        'string.';

    test(
        'toLogSafeSummary/toString exclude both, even after a full '
        'encode/decode round trip', () {
      final record = buildRecord(
        wisdomText: secretWisdom,
        reflectionText: secretReflection,
        reflectedAt: updatedAt,
      );
      final projection =
          CloudKeptWisdomProjection.active(record, dataEpoch: epoch);
      final decoded = CloudKeptWisdomWireEnvelope.tryDecode(
        CloudKeptWisdomWireEnvelope.encode(projection),
      );

      expect(decoded, isNotNull);
      final rendered = decoded!.toLogSafeSummary().toString();
      expect(rendered, isNot(contains(secretWisdom)));
      expect(rendered, isNot(contains(secretReflection)));

      final toStringRendered = decoded.toString();
      expect(toStringRendered, isNot(contains(secretWisdom)));
      expect(toStringRendered, isNot(contains(secretReflection)));
    });
  });

  // Build 26 Phase 4E-3a: tryDecodeIncoming -- the fetch-only entry point
  // that requires and separately exposes a record's opaque system fields.
  group('13. tryDecodeIncoming -- active form', () {
    const systemFields = 'c3lzdGVtRmllbGRzQmxvYg==';

    test('accepts valid non-empty system fields', () {
      final raw = validRawActivePayload()..['systemFields'] = systemFields;
      final decoded = CloudKeptWisdomWireEnvelope.tryDecodeIncoming(raw);

      expect(decoded, isNotNull);
      expect(decoded!.systemFields, systemFields);
      expect(decoded.projection.revealId, revealIdA);
    });

    test('missing systemFields fails closed', () {
      final raw = validRawActivePayload();
      expect(raw.containsKey('systemFields'), isFalse);
      expect(CloudKeptWisdomWireEnvelope.tryDecodeIncoming(raw), isNull);
    });

    test('empty-string systemFields fails closed', () {
      final raw = validRawActivePayload()..['systemFields'] = '';
      expect(CloudKeptWisdomWireEnvelope.tryDecodeIncoming(raw), isNull);
    });

    test('non-String systemFields fails closed', () {
      final raw = validRawActivePayload()..['systemFields'] = 12345;
      expect(CloudKeptWisdomWireEnvelope.tryDecodeIncoming(raw), isNull);
    });

    test('non-Base64-shaped systemFields fails closed', () {
      final raw = validRawActivePayload()
        ..['systemFields'] = 'not base64!! contains spaces and bangs';
      expect(CloudKeptWisdomWireEnvelope.tryDecodeIncoming(raw), isNull);
    });

    test('an unknown key still fails closed even with valid systemFields', () {
      final raw = validRawActivePayload()
        ..['systemFields'] = systemFields
        ..['someFutureField'] = 'anything';
      expect(CloudKeptWisdomWireEnvelope.tryDecodeIncoming(raw), isNull);
    });

    test(
        'projection content is byte-identical to plain tryDecode -- '
        'presence of systemFields has no effect on occurrence/conflict '
        'content', () {
      final rawWithoutSystemFields = validRawActivePayload();
      final rawWithSystemFields = validRawActivePayload()
        ..['systemFields'] = systemFields;

      final plain = CloudKeptWisdomWireEnvelope.tryDecode(
        rawWithoutSystemFields,
      );
      final incoming = CloudKeptWisdomWireEnvelope.tryDecodeIncoming(
        rawWithSystemFields,
      );

      expect(plain, isNotNull);
      expect(incoming, isNotNull);
      expect(incoming!.projection, equals(plain));
    });

    test(
        'systemFields never enters CloudKeptWisdomProjection -- its '
        'toLogSafeSummary/toString/equality are unaffected by the value', () {
      final raw = validRawActivePayload()..['systemFields'] = systemFields;
      final decoded = CloudKeptWisdomWireEnvelope.tryDecodeIncoming(raw);

      expect(decoded, isNotNull);
      final summary = decoded!.projection.toLogSafeSummary();
      expect(summary.values, isNot(contains(systemFields)));
      expect(decoded.projection.toString(), isNot(contains(systemFields)));
    });
  });

  group('14. tryDecodeIncoming -- tombstone form', () {
    const systemFields = 'dG9tYnN0b25lU3lzdGVtRmllbGRz';

    Map<Object?, Object?> validRawTombstonePayload() {
      final tombstone = SyncTombstone(
        revealId: revealIdA,
        dataEpoch: epoch,
        updatedAt: updatedAt,
        deletedAt: updatedAt,
        mutationId: mutationId,
      );
      return CloudKeptWisdomWireEnvelope.encode(
        CloudKeptWisdomProjection.tombstone(tombstone),
      );
    }

    test('accepts valid non-empty system fields', () {
      final raw = validRawTombstonePayload()..['systemFields'] = systemFields;
      final decoded = CloudKeptWisdomWireEnvelope.tryDecodeIncoming(raw);

      expect(decoded, isNotNull);
      expect(decoded!.systemFields, systemFields);
      expect(decoded.projection.isTombstone, isTrue);
      // A soft tombstone is still a real record -- it follows the exact
      // same system-fields requirement an active record does.
      expect(decoded.projection.revealId, isNull);
    });

    test('missing systemFields fails closed', () {
      final raw = validRawTombstonePayload();
      expect(CloudKeptWisdomWireEnvelope.tryDecodeIncoming(raw), isNull);
    });

    test('empty-string systemFields fails closed', () {
      final raw = validRawTombstonePayload()..['systemFields'] = '';
      expect(CloudKeptWisdomWireEnvelope.tryDecodeIncoming(raw), isNull);
    });
  });
}
