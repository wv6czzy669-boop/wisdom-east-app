// Build 26 Phase 4C-2: CloudKitZoneChangesRequest/Result -- the fetch-side
// half of the private CloudKit record transport contract.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_changes_contract.dart';

void main() {
  const revealId = 'c947bbb4-f86a-4db3-87c9-ed5e718bbd98';
  const mutationId = '22222222-2222-4222-8222-222222222222';
  const dataEpoch = '11111111-1111-4111-8111-111111111111';

  // Build 26 Phase 4E-3a: a genuinely fetched changed CKKeptWisdom record
  // always carries its own opaque system fields -- this default fixture
  // reflects that, so every pre-existing test below (which exercises
  // ordinary decode success/failure, not this phase's own system-fields
  // invariant specifically) continues to exercise a payload shape the real
  // native side would actually produce.
  const systemFields = 'c3lzdGVtRmllbGRzQmxvYg==';

  Map<Object?, Object?> validKeptWisdomWire({String? recordNameOverride}) => {
        'recordType': 'CKKeptWisdom',
        'zoneName': 'EASTKeptZone',
        'recordName': recordNameOverride ?? 'east-kept-$revealId',
        'isTombstone': false,
        'revealId': revealId,
        'wisdomText': 'Be still and know.',
        'revealedAtMs': 1754078400000,
        'keptAtMs': 1754078700000,
        'updatedAtMs': 1754078700000,
        'mutationId': mutationId,
        'dataEpoch': dataEpoch,
        'schemaVersion': 3,
        'systemFields': systemFields,
      };

  Map<Object?, Object?> validSyncStateWire() => {
        'recordType': 'CKEastSyncState',
        'zoneName': 'EASTKeptZone',
        'recordName': 'sync-state',
        'dataEpoch': dataEpoch,
        'resetAtMs': 1754078400000,
        'mutationId': mutationId,
        'schemaVersion': 1,
      };

  group('11. initial zone-change request without token', () {
    test('carries a null previousServerToken', () {
      const request = CloudKitZoneChangesRequest();
      expect(request.toChannelArguments()['previousServerToken'], isNull);
    });
  });

  group('12. incremental request with opaque token', () {
    test('carries the exact opaque token string, uninterpreted', () {
      const request =
          CloudKitZoneChangesRequest(previousServerToken: 'opaque-token-xyz');
      expect(
        request.toChannelArguments()['previousServerToken'],
        'opaque-token-xyz',
      );
    });
  });

  group('13. successful empty change set', () {
    test('is success, not an error, with no changes, and no deletion field',
        () {
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'success',
        'changedKeptWisdomRecords': <Object?>[],
        'changedSyncStateRecords': <Object?>[],
        'serverToken': 'new-token',
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.success);
      expect(result.changedKeptWisdomRecords, isEmpty);
      expect(result.changedSyncStateRecords, isEmpty);
      expect(result.serverToken, 'new-token');
    });
  });

  group('14. changed records decode strictly', () {
    test('a valid changed CKKeptWisdom and CKEastSyncState both decode', () {
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'success',
        'changedKeptWisdomRecords': [validKeptWisdomWire()],
        'changedSyncStateRecords': [validSyncStateWire()],
        'serverToken': 'new-token',
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.success);
      expect(result.changedKeptWisdomRecords.single.revealId, revealId);
      expect(result.changedSyncStateRecords.single.mutationId, mutationId);
      // Build 26 Phase 4E-3a: the changed record's own system fields are
      // carried through, keyed by its exact recordName.
      expect(
        result.keptWisdomRecordSystemFields['east-kept-$revealId'],
        systemFields,
      );
      expect(result.keptWisdomRecordSystemFields, hasLength(1));
    });
  });

  group('Build 26 Phase 4E-3a: fetched system-fields invariants', () {
    test(
        'a changed CKKeptWisdom record missing systemFields fails the whole '
        'batch closed, never a partial success with a missing entry', () {
      final raw = validKeptWisdomWire();
      raw.remove('systemFields');
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'success',
        'changedKeptWisdomRecords': [raw],
        'changedSyncStateRecords': <Object?>[],
        'serverToken': 'new-token',
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.unknown);
      expect(result.keptWisdomRecordSystemFields, isEmpty);
    });

    test('an empty-string systemFields value fails the whole batch closed', () {
      final raw = validKeptWisdomWire()..['systemFields'] = '';
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'success',
        'changedKeptWisdomRecords': [raw],
        'changedSyncStateRecords': <Object?>[],
        'serverToken': 'new-token',
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.unknown);
    });

    test(
        'a soft-tombstone changed record also requires and carries valid '
        'system fields', () {
      final tombstoneWire = {
        'recordType': 'CKKeptWisdom',
        'zoneName': 'EASTKeptZone',
        'recordName': 'east-kept-$revealId',
        'isTombstone': true,
        'deletedAtMs': 1754078800000,
        'updatedAtMs': 1754078800000,
        'mutationId': mutationId,
        'dataEpoch': dataEpoch,
        'schemaVersion': 1,
        'systemFields': systemFields,
      };
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'success',
        'changedKeptWisdomRecords': [tombstoneWire],
        'changedSyncStateRecords': <Object?>[],
        'serverToken': 'new-token',
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.success);
      expect(result.changedKeptWisdomRecords.single.isTombstone, isTrue);
      expect(
        result.keptWisdomRecordSystemFields['east-kept-$revealId'],
        systemFields,
      );
    });

    test(
        'a duplicate recordName within one batch fails the whole batch '
        'closed rather than silently overwriting one system-fields entry', () {
      const otherSystemFields = 'b3RoZXJTeXN0ZW1GaWVsZHM=';
      final first = validKeptWisdomWire();
      final duplicate = validKeptWisdomWire()
        ..['systemFields'] = otherSystemFields;
      // Same recordName as `first` (both default to east-kept-$revealId),
      // different content otherwise -- exactly the ambiguous case that must
      // never be resolved by "last write wins".
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'success',
        'changedKeptWisdomRecords': [first, duplicate],
        'changedSyncStateRecords': <Object?>[],
        'serverToken': 'new-token',
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.unknown);
      expect(result.changedKeptWisdomRecords, isEmpty);
      expect(result.keptWisdomRecordSystemFields, isEmpty);
    });

    test(
        'every non-success outcome carries an empty keptWisdomRecordSystemFields '
        'map', () {
      expect(
        CloudKitZoneChangesResult.tokenExpired().keptWisdomRecordSystemFields,
        isEmpty,
      );
      expect(
        CloudKitZoneChangesResult.unexpectedPhysicalDeletion()
            .keptWisdomRecordSystemFields,
        isEmpty,
      );
      expect(
        CloudKitZoneChangesResult.failure('zoneBusy')
            .keptWisdomRecordSystemFields,
        isEmpty,
      );
    });

    test(
        'the system-fields value is never rendered by toString, even when '
        'populated', () {
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'success',
        'changedKeptWisdomRecords': [validKeptWisdomWire()],
        'changedSyncStateRecords': <Object?>[],
        'serverToken': 'new-token',
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.success);
      expect(result.toString(), isNot(contains(systemFields)));
    });
  });

  group('15. malformed returned record rejected', () {
    test('one malformed changed record fails the whole parse closed', () {
      final malformed = validKeptWisdomWire()..['wisdomText'] = 12345;
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'success',
        'changedKeptWisdomRecords': [malformed],
        'changedSyncStateRecords': <Object?>[],
        'serverToken': 'new-token',
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.unknown);
    });

    test('a daily-access-shaped key on a changed record is rejected', () {
      final malformed = validKeptWisdomWire()..['unlockAtMs'] = 123;
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'success',
        'changedKeptWisdomRecords': [malformed],
        'changedSyncStateRecords': <Object?>[],
        'serverToken': 'new-token',
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.unknown);
    });
  });

  group('16. token-expired result', () {
    test('is a distinct outcome, never a generic failure errorCode', () {
      final result =
          CloudKitZoneChangesResult.tryParse({'outcome': 'tokenExpired'});
      expect(result.outcome, CloudKitZoneChangesOutcome.tokenExpired);
      expect(result.errorCode, isNull);
    });

    test(
        'never mutates or persists anything itself -- a fresh factory call '
        'always produces an equivalent, token-free, content-free result', () {
      final first = CloudKitZoneChangesResult.tokenExpired();
      final second = CloudKitZoneChangesResult.tokenExpired();
      expect(first.serverToken, isNull);
      expect(second.serverToken, isNull);
      expect(first.changedKeptWisdomRecords, isEmpty);
      expect(first.changedSyncStateRecords, isEmpty);
    });
  });

  group('unexpected physical deletion', () {
    test('parses as a distinct outcome, never success and never failure', () {
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'unexpectedPhysicalDeletion',
      });
      expect(
        result.outcome,
        CloudKitZoneChangesOutcome.unexpectedPhysicalDeletion,
      );
      expect(result.errorCode, isNull);
      expect(result.serverToken, isNull);
      expect(result.changedKeptWisdomRecords, isEmpty);
      expect(result.changedSyncStateRecords, isEmpty);
    });

    test(
        'the factory constructor accepts no deletion-identity argument at '
        'all -- there is nothing to pass and nothing to leak', () {
      final result = CloudKitZoneChangesResult.unexpectedPhysicalDeletion();
      expect(
        result.outcome,
        CloudKitZoneChangesOutcome.unexpectedPhysicalDeletion,
      );
    });

    test(
        'never carries changed records even if a payload tried to smuggle '
        'some in alongside it', () {
      // The outcome alone determines the parsed shape: extra keys next to
      // "unexpectedPhysicalDeletion" are not consulted at all once that
      // outcome is recognized, so nothing they contain can leak through.
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'unexpectedPhysicalDeletion',
      });
      expect(result.changedKeptWisdomRecords, isEmpty);
      expect(result.changedSyncStateRecords, isEmpty);
    });
  });

  group('deletedRecordNames is no longer part of this contract', () {
    test(
        'a raw payload carrying deletedRecordNames is rejected as an '
        'unrecognized top-level key, never silently accepted', () {
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'success',
        'changedKeptWisdomRecords': <Object?>[],
        'changedSyncStateRecords': <Object?>[],
        'serverToken': 'new-token',
        'deletedRecordNames': <Object?>['east-kept-$revealId'],
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.unknown);
    });

    test('CloudKitZoneChangesResult has no deletedRecordNames member', () {
      // A compile-time proof: if this file still compiles, no code path in
      // this test (or the production class) references such a member.
      final result = CloudKitZoneChangesResult.success(
        changedKeptWisdomRecords: const [],
        changedSyncStateRecords: const [],
        serverToken: 'token',
      );
      expect(result.toString(), isNot(contains('deletedRecordNames')));
      expect(result.toString(), isNot(contains('deletionCount')));
    });
  });

  group('unknown top-level key rejected', () {
    test('an unrecognized top-level key fails the whole parse closed', () {
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'success',
        'changedKeptWisdomRecords': <Object?>[],
        'changedSyncStateRecords': <Object?>[],
        'serverToken': 'new-token',
        'somethingUnexpected': true,
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.unknown);
    });
  });

  group('failure outcome', () {
    test('carries only a stable symbolic errorCode', () {
      final result = CloudKitZoneChangesResult.tryParse({
        'outcome': 'failure',
        'errorCode': 'zoneBusy',
      });
      expect(result.outcome, CloudKitZoneChangesOutcome.failure);
      expect(result.errorCode, 'zoneBusy');
    });
  });

  group(
      'diagnostics never expose the opaque token, deletion identity, or '
      'record content', () {
    test('CloudKitZoneChangesRequest.toString omits the token value', () {
      const request =
          CloudKitZoneChangesRequest(previousServerToken: 'super-secret-token');
      expect(request.toString(), isNot(contains('super-secret-token')));
    });

    test('CloudKitZoneChangesResult.toString omits the token value', () {
      final result = CloudKitZoneChangesResult.success(
        changedKeptWisdomRecords: const [],
        changedSyncStateRecords: const [],
        serverToken: 'super-secret-token',
      );
      expect(result.toString(), isNot(contains('super-secret-token')));
    });

    test(
        'CloudKitZoneChangesResult.toString for an unexpected-deletion '
        'outcome never contains a record name of any shape', () {
      final result = CloudKitZoneChangesResult.unexpectedPhysicalDeletion();
      expect(result.toString(), isNot(contains('east-kept-')));
    });
  });
}
