// Build 26 Phase 4E-1: AccountBootstrapState -- the account-scoped
// first-association/bootstrap progress added to AccountSyncState.
// Synthetic content only.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_envelope.dart';

void main() {
  final epoch = DataEpoch.parse('bbbbbbbb-2222-4222-8222-222222222222');
  const validToken = 'b3BhcXVlLXRva2Vu';
  const validRecordName = 'east-kept-aaaaaaaa-1111-4111-8111-111111111111';
  const fingerprintA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fingerprintB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  PersistedOutboxMutation mutationFor(String revealId) {
    return PersistedOutboxMutation(
      change: SyncChange(
        kind: SyncChangeKind.create,
        projection: CloudKeptWisdomProjection.tryParseRemote({
          'recordName': 'east-kept-$revealId',
          'isTombstone': false,
          'revealId': revealId,
          'wisdomText': 'Synthetic wisdom text.',
          'revealedAtMs': 1000,
          'keptAtMs': 2000,
          'updatedAtMs': 3000,
          'mutationId': 'cccccccc-3333-4333-8333-333333333333',
          'dataEpoch': epoch.value,
          'schemaVersion': 3,
        })!,
        enqueuedAt: DateTime.utc(2026, 8, 1),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 1. legacy bucket without bootstrap field decodes conservatively.
  // ---------------------------------------------------------------------
  test(
      '1. a legacy persisted bucket with no bootstrapState key decodes to '
      'AccountBootstrapState.notStarted, never complete', () {
    final legacyRaw = {
      'dataEpoch': epoch.value,
      'serverChangeToken': validToken,
      'recordSystemFields': <Object?, Object?>{},
      'outbox': <Object?>[],
      // 'bootstrapState' deliberately absent -- exactly what a bucket
      // written before Phase 4E-1 existed looks like.
    };

    final decoded = AccountSyncState.tryDecode(legacyRaw);
    expect(decoded, isNotNull);
    expect(decoded!.bootstrapState, AccountBootstrapState.notStarted);
    expect(decoded.bootstrapState, isNot(AccountBootstrapState.complete));
  });

  // ---------------------------------------------------------------------
  // 2. existing epoch/token/outbox/system fields remain unchanged.
  // ---------------------------------------------------------------------
  test(
      '2. decoding a legacy bucket preserves its existing epoch, token, '
      'outbox, and system fields exactly, changing only the bootstrap '
      'field it never had', () {
    final legacyRaw = {
      'dataEpoch': epoch.value,
      'serverChangeToken': validToken,
      'recordSystemFields': {validRecordName: 'c3lzdGVtLWZpZWxkcw=='},
      'outbox': [
        mutationFor('aaaaaaaa-1111-4111-8111-111111111111').encode(),
      ],
    };

    final decoded = AccountSyncState.tryDecode(legacyRaw)!;
    expect(decoded.dataEpoch, epoch);
    expect(decoded.serverChangeToken, validToken);
    expect(decoded.recordSystemFields[validRecordName], 'c3lzdGVtLWZpZWxkcw==');
    expect(decoded.outbox, hasLength(1));
    expect(decoded.bootstrapState, AccountBootstrapState.notStarted);
  });

  test(
      'a present but unrecognized bootstrapState value fails the whole '
      'decode closed', () {
    final raw = {
      'dataEpoch': epoch.value,
      'recordSystemFields': <Object?, Object?>{},
      'outbox': <Object?>[],
      'bootstrapState': 'not-a-real-state',
    };
    expect(AccountSyncState.tryDecode(raw), isNull);
  });

  test('bootstrapState round-trips exactly through encode/tryDecode', () {
    final state = AccountSyncState(
      dataEpoch: epoch,
      bootstrapState: AccountBootstrapState.remoteBaselinePending,
    );
    final decoded = AccountSyncState.tryDecode(state.encode());
    expect(decoded, state);
    expect(
        decoded!.bootstrapState, AccountBootstrapState.remoteBaselinePending);
    expect(state.encode()['bootstrapState'], 'remoteBaselinePending');
  });

  test(
      'every existing AccountSyncState(...) construction across this '
      'codebase remains valid without a bootstrapState argument -- '
      'defaults to notStarted', () {
    final state = AccountSyncState(dataEpoch: epoch);
    expect(state.bootstrapState, AccountBootstrapState.notStarted);
  });

  // ---------------------------------------------------------------------
  // 3. state transitions are validated.
  // ---------------------------------------------------------------------
  test('3. the forward bootstrap chain is valid, in order', () {
    expect(
      isValidBootstrapTransition(
        AccountBootstrapState.notStarted,
        AccountBootstrapState.remoteBaselinePending,
      ),
      isTrue,
    );
    expect(
      isValidBootstrapTransition(
        AccountBootstrapState.remoteBaselinePending,
        AccountBootstrapState.localReconciliationPending,
      ),
      isTrue,
    );
    expect(
      isValidBootstrapTransition(
        AccountBootstrapState.localReconciliationPending,
        AccountBootstrapState.complete,
      ),
      isTrue,
    );
  });

  test('3b. skipping a step in the forward chain is invalid', () {
    expect(
      isValidBootstrapTransition(
        AccountBootstrapState.notStarted,
        AccountBootstrapState.localReconciliationPending,
      ),
      isFalse,
    );
    expect(
      isValidBootstrapTransition(
        AccountBootstrapState.notStarted,
        AccountBootstrapState.complete,
      ),
      isFalse,
    );
  });

  test('3c. a same-state transition is always valid (idempotent retry)', () {
    for (final state in AccountBootstrapState.values) {
      expect(isValidBootstrapTransition(state, state), isTrue);
    }
  });

  test(
      '3d. a transition to associationRequired is valid from any '
      'non-associationRequired state', () {
    for (final state in AccountBootstrapState.values) {
      if (state == AccountBootstrapState.associationRequired) continue;
      expect(
        isValidBootstrapTransition(
            state, AccountBootstrapState.associationRequired),
        isTrue,
        reason: '$state -> associationRequired should be valid',
      );
    }
  });

  test(
      '3e. bootstrap restarts fresh (notStarted) once associationRequired '
      'is resolved, but no other reverse transition is valid', () {
    expect(
      isValidBootstrapTransition(
        AccountBootstrapState.associationRequired,
        AccountBootstrapState.notStarted,
      ),
      isTrue,
    );
    expect(
      isValidBootstrapTransition(
        AccountBootstrapState.complete,
        AccountBootstrapState.notStarted,
      ),
      isFalse,
    );
    expect(
      isValidBootstrapTransition(
        AccountBootstrapState.complete,
        AccountBootstrapState.remoteBaselinePending,
      ),
      isFalse,
    );
  });

  // ---------------------------------------------------------------------
  // 4/5. bootstrap state is account-scoped; account A and B never mix.
  // ---------------------------------------------------------------------
  test(
      '4/5. two accounts\' bootstrap states are stored independently in '
      'the sync persistence envelope and never mix', () {
    final stateA = AccountSyncState(
      dataEpoch: epoch,
      bootstrapState: AccountBootstrapState.complete,
    );
    final otherEpoch = DataEpoch.parse('dddddddd-4444-4444-8444-444444444444');
    final stateB = AccountSyncState(
      dataEpoch: otherEpoch,
      bootstrapState: AccountBootstrapState.remoteBaselinePending,
    );

    final envelope = SyncPersistenceEnvelope()
        .withAccount(fingerprintA, stateA)
        .withAccount(fingerprintB, stateB);

    final decoded =
        SyncPersistenceEnvelope.decodeString(envelope.encodeString());
    expect(decoded.accounts[fingerprintA]!.bootstrapState,
        AccountBootstrapState.complete);
    expect(
      decoded.accounts[fingerprintB]!.bootstrapState,
      AccountBootstrapState.remoteBaselinePending,
    );
    // Neither bucket's own dataEpoch or bootstrapState leaked into the
    // other's.
    expect(decoded.accounts[fingerprintA]!.dataEpoch, epoch);
    expect(decoded.accounts[fingerprintB]!.dataEpoch, otherEpoch);
  });

  // ---------------------------------------------------------------------
  // 6. state remains tied to the exact dataEpoch.
  // ---------------------------------------------------------------------
  test(
      '6. bootstrapState has no independent epoch field of its own -- it '
      'is structurally co-located with, and never survives independently '
      'of, its own bucket\'s exact dataEpoch', () {
    final state = AccountSyncState(
      dataEpoch: epoch,
      bootstrapState: AccountBootstrapState.localReconciliationPending,
    );

    // copyWith structurally cannot change dataEpoch (already proven for
    // every other field in account_sync_state_test.dart) -- confirm it
    // holds when only bootstrapState changes too.
    final afterBootstrapChange = state.copyWith(
      bootstrapState: AccountBootstrapState.complete,
    );
    expect(afterBootstrapChange.dataEpoch, epoch);
    expect(afterBootstrapChange.bootstrapState, AccountBootstrapState.complete);

    // A genuine epoch reset requires constructing a brand-new bucket --
    // there is no API that changes dataEpoch while preserving
    // bootstrapState, proving the two are never independently addressable.
    final freshEpoch = DataEpoch.parse('11111111-9999-4999-8999-999999999999');
    final freshBucket = AccountSyncState(dataEpoch: freshEpoch);
    expect(freshBucket.bootstrapState, AccountBootstrapState.notStarted);
  });

  // ---------------------------------------------------------------------
  // 7. no fabricated epoch.
  // ---------------------------------------------------------------------
  test(
      '7. constructing or decoding a bucket never fabricates a dataEpoch '
      'merely because a bootstrapState was supplied', () {
    // Compile-time guarantee: dataEpoch remains a required parameter
    // regardless of bootstrapState.
    expect(
      () => AccountSyncState(
        dataEpoch: epoch,
        bootstrapState: AccountBootstrapState.remoteBaselinePending,
      ),
      returnsNormally,
    );

    // A raw payload with a bootstrapState but no dataEpoch still fails
    // closed -- bootstrapState never substitutes for a missing epoch.
    final decoded = AccountSyncState.tryDecode({
      'bootstrapState': 'remoteBaselinePending',
      'recordSystemFields': <Object?, Object?>{},
      'outbox': <Object?>[],
    });
    expect(decoded, isNull);
  });

  // ---------------------------------------------------------------------
  // 8. associationRequired remains explicit.
  // ---------------------------------------------------------------------
  test(
      '8. associationRequired is a real, constructible, round-trippable '
      'state, never set as a side effect of any other operation in this '
      'file', () {
    final state = AccountSyncState(
      dataEpoch: epoch,
      bootstrapState: AccountBootstrapState.associationRequired,
    );
    expect(state.bootstrapState, AccountBootstrapState.associationRequired);
    final decoded = AccountSyncState.tryDecode(state.encode());
    expect(decoded!.bootstrapState, AccountBootstrapState.associationRequired);

    // Every other construction in this entire file (which never passes
    // bootstrapState: associationRequired explicitly) never produces it.
    final ordinary = AccountSyncState(dataEpoch: epoch);
    expect(ordinary.bootstrapState,
        isNot(AccountBootstrapState.associationRequired));
  });

  // ---------------------------------------------------------------------
  // 9. summaries never expose fingerprint/epoch values.
  // ---------------------------------------------------------------------
  test(
      '9. AccountSyncState carries no fingerprint field at all (fingerprint '
      'is only ever a map key one layer up), and its encoded shape exposes '
      'only the exact documented keys -- never a raw account identifier', () {
    final state = AccountSyncState(
      dataEpoch: epoch,
      serverChangeToken: validToken,
      bootstrapState: AccountBootstrapState.complete,
    );
    final encoded = state.encode();
    const allowedKeys = {
      'dataEpoch',
      'serverChangeToken',
      'recordSystemFields',
      'outbox',
      'bootstrapState',
    };
    expect(allowedKeys.containsAll(encoded.keys), isTrue);
    expect(encoded['bootstrapState'], 'complete');
    // The bootstrap state's own wire value is exactly its bare enum name --
    // never a structure that could carry additional identifying data.
    expect(encoded['bootstrapState'], isA<String>());
  });
}
