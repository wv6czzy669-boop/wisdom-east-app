// Build 26 Phase 4C-1: CloudEastSyncStateWireEnvelope -- the
// platform-channel wire boundary for CKEastSyncState. See
// docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §2.5/§2.6.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/cloud_east_sync_state_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync_platform/cloud_east_sync_state_wire_envelope.dart';

void main() {
  const mutationId = '22222222-2222-4222-8222-222222222222';
  final epoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
  final resetAt = DateTime.utc(2026, 8, 1, 20, 0);

  Map<Object?, Object?> validRawPayload({int? schemaVersion}) => {
        'recordType': 'CKEastSyncState',
        'zoneName': 'EASTKeptZone',
        'recordName': 'sync-state',
        'dataEpoch': epoch.value,
        'resetAtMs': resetAt.millisecondsSinceEpoch,
        'mutationId': mutationId,
        'schemaVersion':
            schemaVersion ?? CloudEastSyncStateProjection.currentSchemaVersion,
      };

  group('valid payload', () {
    test('round-trips through encode/tryDecode unchanged', () {
      final projection = CloudEastSyncStateProjection.current(
        dataEpoch: epoch,
        mutationId: mutationId,
        resetAt: resetAt,
      );
      final wire = CloudEastSyncStateWireEnvelope.encode(projection);
      final decoded = CloudEastSyncStateWireEnvelope.tryDecode(wire);

      expect(decoded, isNotNull);
      expect(decoded, equals(projection));
    });

    test('a hand-built valid raw payload decodes successfully', () {
      final decoded =
          CloudEastSyncStateWireEnvelope.tryDecode(validRawPayload());
      expect(decoded, isNotNull);
      expect(decoded!.mutationId, mutationId);
      expect(decoded.dataEpoch, epoch);
    });
  });

  group('rejections', () {
    test('an unrecognized recordType fails closed', () {
      final raw = validRawPayload()..['recordType'] = 'CKKeptWisdom';
      expect(CloudEastSyncStateWireEnvelope.tryDecode(raw), isNull);
    });

    test(
        'a wrong zoneName fails closed (rejects public/default-zone-'
        'shaped payloads)', () {
      final raw = validRawPayload()..['zoneName'] = '_defaultZone';
      expect(CloudEastSyncStateWireEnvelope.tryDecode(raw), isNull);
    });

    test(
        'a wrong recordName fails closed -- there is exactly one legitimate '
        'singleton name', () {
      final raw = validRawPayload()..['recordName'] = 'not-sync-state';
      expect(CloudEastSyncStateWireEnvelope.tryDecode(raw), isNull);
    });

    test('a wrong schemaVersion fails closed', () {
      expect(
        CloudEastSyncStateWireEnvelope.tryDecode(
            validRawPayload(schemaVersion: 999)),
        isNull,
      );
    });

    test(
        'a daily-access-shaped key fails closed even though every other '
        'field is otherwise valid -- rejected purely by not being in the '
        'allowlist, exactly like any other unknown key', () {
      // Test-only inputs proving the generic allowlist in
      // CloudEastSyncStateWireEnvelope.allowedKeys rejects them --
      // production code never spells out a daily-access field name
      // anywhere (see docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §11).
      const daylyAccessShapedKeys = [
        'dailyWisdomAccess',
        'unlockAt',
        'unlockAtMs',
        'lockDurationMs',
        'dailyAccessState',
        'pendingDailyWisdomReveal',
      ];
      for (final forbidden in daylyAccessShapedKeys) {
        final raw = validRawPayload()..[forbidden] = 'anything';
        expect(
          CloudEastSyncStateWireEnvelope.tryDecode(raw),
          isNull,
          reason: 'Expected rejection for forbidden key "$forbidden"',
        );
      }
    });

    test('an entirely unrelated unknown key is rejected the same way', () {
      final raw = validRawPayload()..['someFutureField'] = 'anything';
      expect(CloudEastSyncStateWireEnvelope.tryDecode(raw), isNull);
    });

    test('a non-int resetAtMs fails closed', () {
      final raw = validRawPayload()..['resetAtMs'] = 'not-an-int';
      expect(CloudEastSyncStateWireEnvelope.tryDecode(raw), isNull);
    });

    test('a non-String mutationId fails closed', () {
      final raw = validRawPayload()..['mutationId'] = 12345;
      expect(CloudEastSyncStateWireEnvelope.tryDecode(raw), isNull);
    });

    test('a non-String key anywhere in the raw map fails closed', () {
      final raw = validRawPayload();
      raw[7] = 'an int key, never valid on a wire map';
      expect(CloudEastSyncStateWireEnvelope.tryDecode(raw), isNull);
    });
  });

  group('diagnostics', () {
    test(
        'this record type carries no content, but toLogSafeSummary/'
        'toString still only ever expose identifiers/timestamps/flags', () {
      final projection = CloudEastSyncStateProjection.current(
        dataEpoch: epoch,
        mutationId: mutationId,
        resetAt: resetAt,
      );
      final decoded = CloudEastSyncStateWireEnvelope.tryDecode(
        CloudEastSyncStateWireEnvelope.encode(projection),
      );
      expect(decoded, isNotNull);

      final rendered = decoded!.toLogSafeSummary().toString();
      expect(rendered, contains('sync-state'));
      expect(rendered, contains(mutationId));
    });
  });
}
