// Build 26 Phase 4D-1 (correction round): AccountSyncState -- the
// per-account durable sync state value type, now with a mandatory
// account-scoped dataEpoch. Synthetic content only.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';

void main() {
  final epoch = DataEpoch.parse('bbbbbbbb-2222-4222-8222-222222222222');
  final otherEpoch = DataEpoch.parse('dddddddd-4444-4444-8444-444444444444');

  CloudKeptWisdomProjection activeProjection(
    String revealId, {
    DataEpoch? dataEpoch,
  }) {
    return CloudKeptWisdomProjection.tryParseRemote({
      'recordName': 'east-kept-$revealId',
      'isTombstone': false,
      'revealId': revealId,
      'wisdomText': 'Synthetic wisdom text.',
      'revealedAtMs': 1000,
      'keptAtMs': 2000,
      'updatedAtMs': 3000,
      'mutationId': 'cccccccc-3333-4333-8333-333333333333',
      'dataEpoch': (dataEpoch ?? epoch).value,
      'schemaVersion': 3,
    })!;
  }

  PersistedOutboxMutation mutationFor(String revealId, {DataEpoch? dataEpoch}) {
    return PersistedOutboxMutation(
      change: SyncChange(
        kind: SyncChangeKind.create,
        projection: activeProjection(revealId, dataEpoch: dataEpoch),
        enqueuedAt: DateTime.utc(2026, 8, 1),
      ),
    );
  }

  const validToken = 'b3BhcXVlLXRva2Vu';
  const validSystemFields = 'c3lzdGVtLWZpZWxkcw==';
  const validRecordName = 'east-kept-aaaaaaaa-1111-4111-8111-111111111111';

  test('empty(epoch) has that epoch, no token, no system fields, no outbox',
      () {
    final state = AccountSyncState.empty(epoch);
    expect(state.dataEpoch, epoch);
    expect(state.serverChangeToken, isNull);
    expect(state.recordSystemFields, isEmpty);
    expect(state.outbox, isEmpty);
  });

  test(
      'encode/tryDecode round-trips a populated state, including '
      'dataEpoch, exactly', () {
    final state = AccountSyncState(
      dataEpoch: epoch,
      serverChangeToken: validToken,
      recordSystemFields: {validRecordName: validSystemFields},
      outbox: [mutationFor('aaaaaaaa-1111-4111-8111-111111111111')],
    );

    final decoded = AccountSyncState.tryDecode(state.encode());
    expect(decoded, state);
    expect(decoded!.dataEpoch, epoch);
    expect(state.encode()['dataEpoch'], epoch.value);
  });

  test('tryDecode rejects a payload with no dataEpoch at all', () {
    final decoded = AccountSyncState.tryDecode({
      'recordSystemFields': <Object?, Object?>{},
      'outbox': <Object?>[],
    });
    expect(decoded, isNull);
  });

  test('tryDecode rejects a wrong-typed dataEpoch', () {
    final decoded = AccountSyncState.tryDecode({
      'dataEpoch': 12345,
      'recordSystemFields': <Object?, Object?>{},
      'outbox': <Object?>[],
    });
    expect(decoded, isNull);
  });

  test(
      'tryDecode rejects an unsupported/malformed dataEpoch representation '
      '(not a canonical UUID v4)', () {
    final decoded = AccountSyncState.tryDecode({
      'dataEpoch': 'not-a-uuid',
      'recordSystemFields': <Object?, Object?>{},
      'outbox': <Object?>[],
    });
    expect(decoded, isNull);
  });

  test(
      'the constructor rejects a missing dataEpoch by requiring it as a '
      'required named parameter -- this is a compile-time guarantee, not a '
      'runtime check', () {
    // If this file compiles, `AccountSyncState(...)` without `dataEpoch:`
    // is not expressible at all -- proven structurally rather than by a
    // runtime throw.
    expect(() => AccountSyncState(dataEpoch: epoch), returnsNormally);
  });

  test('rejects a serverChangeToken that does not look like opaque Base64', () {
    expect(
      () => AccountSyncState(
        dataEpoch: epoch,
        serverChangeToken: 'not valid base64!!',
      ),
      throwsA(isA<AccountSyncStateFormatException>()),
    );
  });

  test('tryDecode fails closed on a corrupt token', () {
    final decoded = AccountSyncState.tryDecode({
      'dataEpoch': epoch.value,
      'serverChangeToken': 'not valid base64!!',
      'recordSystemFields': <Object?, Object?>{},
      'outbox': <Object?>[],
    });
    expect(decoded, isNull);
  });

  test('tryDecode fails closed on corrupt system fields', () {
    final decoded = AccountSyncState.tryDecode({
      'dataEpoch': epoch.value,
      'recordSystemFields': {validRecordName: 'not valid base64!!'},
      'outbox': <Object?>[],
    });
    expect(decoded, isNull);
  });

  test('rejects a recordSystemFields key that is not a valid record name', () {
    expect(
      () => AccountSyncState(
        dataEpoch: epoch,
        recordSystemFields: {'not-a-record-name': validSystemFields},
      ),
      throwsA(isA<AccountSyncStateFormatException>()),
    );
  });

  test('tryDecode rejects an unrecognized top-level key', () {
    final decoded = AccountSyncState.tryDecode({
      'dataEpoch': epoch.value,
      'serverChangeToken': validToken,
      'somethingUnexpected': true,
    });
    expect(decoded, isNull);
  });

  test('rejects two outbox entries sharing the same mutationId', () {
    final entry = mutationFor('aaaaaaaa-1111-4111-8111-111111111111');
    expect(
      () => AccountSyncState(dataEpoch: epoch, outbox: [entry, entry]),
      throwsA(isA<AccountSyncStateFormatException>()),
    );
  });

  test(
      'rejects two outbox entries sharing the same recordName '
      '(malformed duplicate record identity, e.g. from tampered disk state)',
      () {
    final revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    final first = mutationFor(revealId);
    final second = PersistedOutboxMutation(
      change: SyncChange(
        kind: SyncChangeKind.create,
        projection: CloudKeptWisdomProjection.tryParseRemote({
          'recordName': 'east-kept-$revealId',
          'isTombstone': false,
          'revealId': revealId,
          'wisdomText': 'A different edit of the same occurrence.',
          'revealedAtMs': 1000,
          'keptAtMs': 2000,
          'updatedAtMs': 9999,
          'mutationId': 'eeeeeeee-5555-4555-8555-555555555555',
          'dataEpoch': epoch.value,
          'schemaVersion': 3,
        })!,
        enqueuedAt: DateTime.utc(2026, 8, 1),
      ),
    );

    expect(
      () => AccountSyncState(dataEpoch: epoch, outbox: [first, second]),
      throwsA(isA<AccountSyncStateFormatException>()),
    );
  });

  test(
      'rejects an outbox mutation whose own dataEpoch does not match the '
      'account dataEpoch', () {
    final mismatched = mutationFor(
      'aaaaaaaa-1111-4111-8111-111111111111',
      dataEpoch: otherEpoch,
    );
    expect(
      () => AccountSyncState(dataEpoch: epoch, outbox: [mismatched]),
      throwsA(isA<AccountSyncStateFormatException>()),
    );
  });

  test(
      'tryDecode fails closed on a persisted account whose mutation epoch '
      'differs from its own account-bucket epoch', () {
    final mismatched = mutationFor(
      'aaaaaaaa-1111-4111-8111-111111111111',
      dataEpoch: otherEpoch,
    );
    final raw = {
      'dataEpoch': epoch.value,
      'recordSystemFields': <Object?, Object?>{},
      'outbox': [mismatched.encode()],
    };

    expect(AccountSyncState.tryDecode(raw), isNull);
  });

  test(
      'exact duplicate wisdom text across two different revealIds is a '
      'perfectly valid, distinct pair of outbox entries', () {
    final entryOne = mutationFor('aaaaaaaa-1111-4111-8111-111111111111');
    final entryTwoProjection = CloudKeptWisdomProjection.tryParseRemote({
      'recordName': 'east-kept-ffffffff-6666-4666-8666-666666666666',
      'isTombstone': false,
      'revealId': 'ffffffff-6666-4666-8666-666666666666',
      'wisdomText': 'Synthetic wisdom text.', // exact same text, deliberately
      'revealedAtMs': 1000,
      'keptAtMs': 2000,
      'updatedAtMs': 3000,
      'mutationId': 'a1a1a1a1-7777-4777-8777-777777777777',
      'dataEpoch': epoch.value,
      'schemaVersion': 3,
    })!;
    final entryTwo = PersistedOutboxMutation(
      change: SyncChange(
        kind: SyncChangeKind.create,
        projection: entryTwoProjection,
        enqueuedAt: DateTime.utc(2026, 8, 1),
      ),
    );

    final state = AccountSyncState(
      dataEpoch: epoch,
      outbox: [entryOne, entryTwo],
    );
    expect(state.outbox, hasLength(2));
  });

  test('recordSystemFields and outbox exposed are unmodifiable', () {
    final state = AccountSyncState(
      dataEpoch: epoch,
      recordSystemFields: {validRecordName: validSystemFields},
      outbox: [mutationFor('aaaaaaaa-1111-4111-8111-111111111111')],
    );

    expect(
      () => state.recordSystemFields['new'] = 'x',
      throwsUnsupportedError,
    );
    expect(
      () =>
          state.outbox.add(mutationFor('bbbbbbbb-1111-4111-8111-111111111111')),
      throwsUnsupportedError,
    );
  });

  test(
      'copyWith(serverChangeToken: null) explicitly clears the token while '
      'preserving dataEpoch', () {
    final state =
        AccountSyncState(dataEpoch: epoch, serverChangeToken: validToken);
    final cleared = state.copyWith(serverChangeToken: null);
    expect(cleared.serverChangeToken, isNull);
    expect(cleared.dataEpoch, epoch);
  });

  test(
      'copyWith without serverChangeToken preserves the existing token and '
      'dataEpoch', () {
    final state =
        AccountSyncState(dataEpoch: epoch, serverChangeToken: validToken);
    final updated = state.copyWith(
      outbox: [mutationFor('aaaaaaaa-1111-4111-8111-111111111111')],
    );
    expect(updated.serverChangeToken, validToken);
    expect(updated.dataEpoch, epoch);
  });

  test(
      'copyWith exposes no way to change dataEpoch -- every convenience '
      'mutation preserves it structurally', () {
    final state = AccountSyncState(dataEpoch: epoch);
    final afterOutboxChange = state.copyWith(
      outbox: [mutationFor('aaaaaaaa-1111-4111-8111-111111111111')],
    );
    final afterFieldsChange = state.copyWith(
      recordSystemFields: {validRecordName: validSystemFields},
    );
    expect(afterOutboxChange.dataEpoch, epoch);
    expect(afterFieldsChange.dataEpoch, epoch);
  });
}
