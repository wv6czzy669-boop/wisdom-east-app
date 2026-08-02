// Build 26 Phase 4C-1: CloudEastSyncStateProjection -- the CloudKit-safe
// projection of the CKEastSyncState singleton control record. See
// docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §2.5/§2.6.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/cloud_east_sync_state_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';

void main() {
  const mutationId = '22222222-2222-4222-8222-222222222222';
  final epoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
  final resetAt = DateTime.utc(2026, 8, 1, 20, 0);

  group('construction', () {
    test(
        'current() carries every field verbatim, with the fixed singleton '
        'identity', () {
      final projection = CloudEastSyncStateProjection.current(
        dataEpoch: epoch,
        mutationId: mutationId,
        resetAt: resetAt,
      );

      expect(projection.dataEpoch, epoch);
      expect(projection.mutationId, mutationId);
      expect(projection.resetAtMs, resetAt.millisecondsSinceEpoch);
      expect(projection.schemaVersion,
          CloudEastSyncStateProjection.currentSchemaVersion);
      expect(CloudEastSyncStateProjection.recordName, 'sync-state');
      expect(CloudEastSyncStateProjection.recordType, 'CKEastSyncState');
      expect(CloudEastSyncStateProjection.zoneName, 'EASTKeptZone');
    });

    test('resetAt is optional -- resetAtMs is null when absent', () {
      final projection = CloudEastSyncStateProjection.current(
        dataEpoch: epoch,
        mutationId: mutationId,
      );
      expect(projection.resetAtMs, isNull);
    });

    test('throws for a non-canonical mutationId', () {
      expect(
        () => CloudEastSyncStateProjection.current(
          dataEpoch: epoch,
          mutationId: 'not-a-uuid',
        ),
        throwsFormatException,
      );
    });
  });

  group('tryParseRemote', () {
    Map<String, dynamic> validFields({int? schemaVersion}) => {
          'schemaVersion': schemaVersion ??
              CloudEastSyncStateProjection.currentSchemaVersion,
          'mutationId': mutationId,
          'dataEpoch': epoch.value,
          'resetAtMs': resetAt.millisecondsSinceEpoch,
        };

    test('accepts a valid payload', () {
      final projection =
          CloudEastSyncStateProjection.tryParseRemote(validFields());
      expect(projection, isNotNull);
      expect(projection!.mutationId, mutationId);
      expect(projection.dataEpoch, epoch);
      expect(projection.resetAtMs, resetAt.millisecondsSinceEpoch);
    });

    test('accepts a valid payload with resetAtMs entirely absent', () {
      final fields = validFields()..remove('resetAtMs');
      final projection = CloudEastSyncStateProjection.tryParseRemote(fields);
      expect(projection, isNotNull);
      expect(projection!.resetAtMs, isNull);
    });

    test('rejects a wrong schemaVersion', () {
      expect(
        CloudEastSyncStateProjection.tryParseRemote(
            validFields(schemaVersion: 999)),
        isNull,
      );
    });

    test('rejects a non-canonical mutationId', () {
      final fields = validFields()..['mutationId'] = 'not-a-uuid';
      expect(CloudEastSyncStateProjection.tryParseRemote(fields), isNull);
    });

    test('rejects an invalid dataEpoch', () {
      final fields = validFields()..['dataEpoch'] = 'not-an-epoch';
      expect(CloudEastSyncStateProjection.tryParseRemote(fields), isNull);
    });

    test('rejects a wrong-typed resetAtMs', () {
      final fields = validFields()..['resetAtMs'] = 'not-an-int';
      expect(CloudEastSyncStateProjection.tryParseRemote(fields), isNull);
    });

    test('rejects a missing schemaVersion entirely', () {
      final fields = validFields()..remove('schemaVersion');
      expect(CloudEastSyncStateProjection.tryParseRemote(fields), isNull);
    });
  });

  group('equality and diagnostics', () {
    test('two projections with identical fields are equal', () {
      final a = CloudEastSyncStateProjection.current(
        dataEpoch: epoch,
        mutationId: mutationId,
        resetAt: resetAt,
      );
      final b = CloudEastSyncStateProjection.current(
        dataEpoch: epoch,
        mutationId: mutationId,
        resetAt: resetAt,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toLogSafeSummary carries only identifiers/timestamps/flags', () {
      final projection = CloudEastSyncStateProjection.current(
        dataEpoch: epoch,
        mutationId: mutationId,
        resetAt: resetAt,
      );
      final summary = projection.toLogSafeSummary();
      expect(summary['recordName'], 'sync-state');
      expect(summary['recordType'], 'CKEastSyncState');
      expect(summary['mutationId'], mutationId);
      expect(summary['dataEpoch'], epoch.value);
      expect(summary['schemaVersion'], 1);
    });
  });
}
