// Build 26 Phase 4C-2: CloudKitModifyRecordsRequest/Result -- the save-side
// half of the private CloudKit record transport contract. See
// docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §11 (Phase 4C-2 addendum) for
// the exact envelope this mirrors.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/cloud_east_sync_state_projection.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync_platform/cloud_east_sync_state_wire_envelope.dart';
import 'package:wisdom_app/sync_platform/cloud_kept_wisdom_wire_envelope.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_modify_records_contract.dart';

void main() {
  const revealId = 'c947bbb4-f86a-4db3-87c9-ed5e718bbd98';
  const mutationId = '22222222-2222-4222-8222-222222222222';
  final epoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');

  CloudKeptWisdomProjection activeProjection() {
    return CloudKeptWisdomProjection.tryParseRemote({
      'recordName': 'east-kept-$revealId',
      'isTombstone': false,
      'revealId': revealId,
      'wisdomText': 'This wisdom text must never appear in a diagnostic.',
      'revealedAtMs': 1754078400000,
      'keptAtMs': 1754078700000,
      'reflectionText':
          'This reflection text must never appear in a diagnostic either.',
      'reflectedAtMs': 1754078700000,
      'updatedAtMs': 1754078700000,
      'mutationId': mutationId,
      'dataEpoch': epoch.value,
      'schemaVersion': KeptRecordCurrentSchemaVersionForTest.value,
    })!;
  }

  CloudEastSyncStateProjection syncStateProjection() {
    return CloudEastSyncStateProjection.current(
      dataEpoch: epoch,
      mutationId: mutationId,
      resetAt: DateTime.utc(2026, 8, 1, 20, 0),
    );
  }

  group('1. a valid modify request', () {
    test('builds a channel-argument map with the exact record entries', () {
      final request = CloudKitModifyRecordsRequest(records: [
        CloudKitRecordChangeInput.keptWisdom(activeProjection()),
        CloudKitRecordChangeInput.syncState(syncStateProjection()),
      ]);
      final arguments = request.toChannelArguments();
      expect(arguments['records'], isA<List<Object?>>());
      expect((arguments['records'] as List).length, 2);
    });
  });

  group('2. empty modify request behavior', () {
    test('is a well-defined no-op, not an error', () {
      const request = CloudKitModifyRecordsRequest(records: []);
      expect((request.toChannelArguments()['records'] as List), isEmpty);

      final result = CloudKitModifyRecordsResult.allSucceeded(const []);
      expect(
        result.overallStatus,
        CloudKitModifyRecordsOverallStatus.allSucceeded,
      );
      expect(result.outcomes, isEmpty);
    });
  });

  group('3. record type is always drawn from the two frozen constants', () {
    test('keptWisdom uses CloudKeptWisdomWireEnvelope.recordType', () {
      final input = CloudKitRecordChangeInput.keptWisdom(activeProjection());
      expect(input.recordType, CloudKeptWisdomWireEnvelope.recordType);
    });

    test('syncState uses CloudEastSyncStateWireEnvelope.recordType', () {
      final input = CloudKitRecordChangeInput.syncState(syncStateProjection());
      expect(input.recordType, CloudEastSyncStateWireEnvelope.recordType);
    });
  });

  group('4. unknown top-level result key rejected', () {
    test('a result map with an extra unrecognized key parses as unknown', () {
      final result = CloudKitModifyRecordsResult.tryParse({
        'overallStatus': 'allSucceeded',
        'outcomes': <Object?>[],
        'somethingUnexpected': true,
      });
      expect(
        result.overallStatus,
        CloudKitModifyRecordsOverallStatus.unknown,
      );
    });
  });

  group('5. malformed record outcome rejected', () {
    test('an outcome missing recordName fails the whole parse closed', () {
      final result = CloudKitModifyRecordsResult.tryParse({
        'overallStatus': 'allSucceeded',
        'outcomes': [
          {'success': true, 'systemFields': 'abc'},
        ],
      });
      expect(
        result.overallStatus,
        CloudKitModifyRecordsOverallStatus.unknown,
      );
    });

    test('a success outcome carrying an errorCode is rejected', () {
      final outcome = CloudKitRecordModifyOutcome.tryParse({
        'recordName': 'east-kept-$revealId',
        'success': true,
        'systemFields': 'abc',
        'errorCode': 'serverRecordChanged',
      });
      expect(outcome, isNull);
    });
  });

  group('6. a successful batch result parses', () {
    test('every outcome is success with systemFields', () {
      final result = CloudKitModifyRecordsResult.tryParse({
        'overallStatus': 'allSucceeded',
        'outcomes': [
          {
            'recordName': 'east-kept-$revealId',
            'success': true,
            'systemFields': 'opaque-blob-a',
          },
        ],
      });
      expect(
        result.overallStatus,
        CloudKitModifyRecordsOverallStatus.allSucceeded,
      );
      expect(result.outcomes.single.success, isTrue);
      expect(result.outcomes.single.systemFields, 'opaque-blob-a');
    });
  });

  group('7. partial failure preserves per-record outcomes', () {
    test('one success and one failure both survive parsing distinctly', () {
      final result = CloudKitModifyRecordsResult.tryParse({
        'overallStatus': 'partialFailure',
        'outcomes': [
          {
            'recordName': 'east-kept-aaaa',
            'success': true,
            'systemFields': 'opaque-blob-a',
          },
          {
            'recordName': 'east-kept-bbbb',
            'success': false,
            'errorCode': 'networkFailure',
          },
        ],
      });
      expect(
        result.overallStatus,
        CloudKitModifyRecordsOverallStatus.partialFailure,
      );
      expect(result.outcomes[0].success, isTrue);
      expect(result.outcomes[1].success, isFalse);
      expect(result.outcomes[1].errorCode, 'networkFailure');
    });
  });

  group('8. server-record-changed conflict remains a per-record outcome', () {
    test('never a distinct top-level overallStatus', () {
      final result = CloudKitModifyRecordsResult.tryParse({
        'overallStatus': 'partialFailure',
        'outcomes': [
          {
            'recordName': 'east-kept-$revealId',
            'success': false,
            'errorCode': 'serverRecordChanged',
          },
        ],
      });
      expect(
        result.overallStatus,
        CloudKitModifyRecordsOverallStatus.partialFailure,
      );
      expect(result.outcomes.single.errorCode, 'serverRecordChanged');
    });
  });

  group('9. retryable transport failure', () {
    test('carries no per-record outcomes', () {
      final result = CloudKitModifyRecordsResult.tryParse({
        'overallStatus': 'transportFailure',
        'errorCode': 'networkUnavailable',
      });
      expect(
        result.overallStatus,
        CloudKitModifyRecordsOverallStatus.transportFailure,
      );
      expect(result.outcomes, isEmpty);
      expect(result.errorCode, 'networkUnavailable');
    });
  });

  group('10. permanent transport failure', () {
    test('is structurally identical in shape to a retryable one', () {
      final result = CloudKitModifyRecordsResult.tryParse({
        'overallStatus': 'transportFailure',
        'errorCode': 'notAuthenticated',
      });
      expect(
        result.overallStatus,
        CloudKitModifyRecordsOverallStatus.transportFailure,
      );
      expect(result.errorCode, 'notAuthenticated');
    });

    test('a transportFailure missing errorCode fails parsing closed', () {
      final result = CloudKitModifyRecordsResult.tryParse({
        'overallStatus': 'transportFailure',
      });
      expect(
        result.overallStatus,
        CloudKitModifyRecordsOverallStatus.unknown,
      );
    });
  });

  group('17. opaque systemFields/tokens never appear in diagnostics', () {
    test('CloudKitRecordChangeInput.toString omits previousSystemFields', () {
      final input = CloudKitRecordChangeInput.keptWisdom(
        activeProjection(),
        previousSystemFields: 'super-secret-opaque-blob',
      );
      expect(input.toString(), isNot(contains('super-secret-opaque-blob')));
    });

    test('CloudKitRecordModifyOutcome.toString omits systemFields', () {
      final outcome = CloudKitRecordModifyOutcome.success(
        recordName: 'east-kept-$revealId',
        systemFields: 'super-secret-opaque-blob',
      );
      expect(
        outcome.toString(),
        isNot(contains('super-secret-opaque-blob')),
      );
    });
  });

  group('18. wisdom/Reflection content never appear in diagnostics', () {
    test('CloudKitRecordChangeInput.toString omits fields entirely', () {
      final input = CloudKitRecordChangeInput.keptWisdom(activeProjection());
      expect(
        input.toString(),
        isNot(contains('This wisdom text must never appear')),
      );
      expect(
        input.toString(),
        isNot(contains('This reflection text must never appear')),
      );
    });

    test('CloudKitModifyRecordsRequest.toString never renders record fields',
        () {
      final request = CloudKitModifyRecordsRequest(records: [
        CloudKitRecordChangeInput.keptWisdom(activeProjection()),
      ]);
      expect(
        request.toString(),
        isNot(contains('This wisdom text must never appear')),
      );
    });
  });

  group('19. daily-access fields remain rejected at the transport boundary',
      () {
    test(
        'CloudKitRecordChangeInput.keptWisdom only ever emits allowlisted '
        'wire keys', () {
      final input = CloudKitRecordChangeInput.keptWisdom(activeProjection());
      final keys = input.fields.keys.cast<String>().toSet();
      expect(keys.difference(CloudKeptWisdomWireEnvelope.allowedKeys), isEmpty);
    });

    test(
        'CloudKitRecordChangeInput.syncState only ever emits allowlisted '
        'wire keys', () {
      final input = CloudKitRecordChangeInput.syncState(syncStateProjection());
      final keys = input.fields.keys.cast<String>().toSet();
      expect(
        keys.difference(CloudEastSyncStateWireEnvelope.allowedKeys),
        isEmpty,
      );
    });
  });
}

/// A tiny local indirection so this test file never has to import
/// `lib/models/kept_record.dart` directly just to read one schema-version
/// constant -- keeps this file's own import list obviously free of any
/// Kept/Reflection domain dependency, mirroring the transport-boundary
/// files it tests.
class KeptRecordCurrentSchemaVersionForTest {
  static const int value = 3;
}
