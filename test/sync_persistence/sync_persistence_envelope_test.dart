// Build 26 Phase 4D-1 (correction round): SyncPersistenceEnvelope -- the
// top-level, multi-account, versioned local sync-state envelope. Synthetic
// content only.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_envelope.dart';

void main() {
  const fingerprintA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fingerprintB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  final epoch = DataEpoch.parse('bbbbbbbb-2222-4222-8222-222222222222');

  test('empty() encodes and decodes to an equivalent empty envelope', () {
    final envelope = SyncPersistenceEnvelope.empty();
    final decoded = SyncPersistenceEnvelope.decodeString(
      envelope.encodeString(),
    );
    expect(decoded, envelope);
    expect(decoded.accounts, isEmpty);
    expect(decoded.quarantinedAccounts, isEmpty);
  });

  test('withAccount scopes state so two fingerprints never mix', () {
    final envelope = SyncPersistenceEnvelope.empty()
        .withAccount(
          fingerprintA,
          AccountSyncState(dataEpoch: epoch, serverChangeToken: 'QQQQ'),
        )
        .withAccount(
          fingerprintB,
          AccountSyncState(dataEpoch: epoch, serverChangeToken: 'Qkkk'),
        );

    expect(envelope.accounts[fingerprintA]!.serverChangeToken, 'QQQQ');
    expect(envelope.accounts[fingerprintB]!.serverChangeToken, 'Qkkk');
    expect(envelope.accounts[fingerprintA],
        isNot(envelope.accounts[fingerprintB]));
  });

  test(
      'an unresolved/unknown fingerprint never surfaces another account\'s '
      'state', () {
    final envelope = SyncPersistenceEnvelope.empty().withAccount(
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: 'QQQQ'),
    );

    const unknownFingerprint =
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    expect(envelope.accounts[unknownFingerprint], isNull);
  });

  test(
      'withAccountQuarantined moves state out of accounts without deleting '
      'it', () {
    final envelope = SyncPersistenceEnvelope.empty().withAccount(
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: 'QQQQ'),
    );

    final quarantined = envelope.withAccountQuarantined(fingerprintA);
    expect(quarantined.accounts[fingerprintA], isNull);
    expect(quarantined.quarantinedAccounts[fingerprintA]!.serverChangeToken,
        'QQQQ');
    expect(quarantined.quarantinedAccounts[fingerprintA]!.dataEpoch, epoch);
  });

  test('withAccountCleared removes state entirely, active or quarantined', () {
    final envelope = SyncPersistenceEnvelope.empty()
        .withAccount(
          fingerprintA,
          AccountSyncState(dataEpoch: epoch, serverChangeToken: 'QQQQ'),
        )
        .withAccountQuarantined(fingerprintA);

    final cleared = envelope.withAccountCleared(fingerprintA);
    expect(cleared.accounts[fingerprintA], isNull);
    expect(cleared.quarantinedAccounts[fingerprintA], isNull);
  });

  test('decode rejects an unrecognized top-level key', () {
    expect(
      () => SyncPersistenceEnvelope.decode({
        'schemaVersion': 1,
        'accounts': <String, dynamic>{},
        'somethingUnexpected': true,
      }),
      throwsFormatException,
    );
  });

  test('decode rejects an unsupported schema version', () {
    expect(
      () => SyncPersistenceEnvelope.decode({
        'schemaVersion': 2,
        'accounts': <String, dynamic>{},
      }),
      throwsFormatException,
    );
  });

  test('decode rejects a malformed (non-fingerprint-shaped) account key', () {
    expect(
      () => SyncPersistenceEnvelope.decode({
        'schemaVersion': 1,
        'accounts': {
          'not-a-valid-fingerprint': AccountSyncState.empty(epoch).encode(),
        },
      }),
      throwsFormatException,
    );
  });

  test('decode rejects an account entry with no dataEpoch', () {
    expect(
      () => SyncPersistenceEnvelope.decode({
        'schemaVersion': 1,
        'accounts': {
          fingerprintA: {
            'recordSystemFields': <String, dynamic>{},
            'outbox': <dynamic>[],
          },
        },
      }),
      throwsFormatException,
    );
  });

  test(
      'decode rejects a fingerprint present in both accounts and '
      'quarantinedAccounts', () {
    final encodedState = AccountSyncState.empty(epoch).encode();
    expect(
      () => SyncPersistenceEnvelope.decode({
        'schemaVersion': 1,
        'accounts': {fingerprintA: encodedState},
        'quarantinedAccounts': {fingerprintA: encodedState},
      }),
      throwsFormatException,
    );
  });

  test('encodeString/decodeString round-trips through real JSON text', () {
    final envelope = SyncPersistenceEnvelope.empty().withAccount(
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: 'QQQQ'),
    );

    final jsonText = envelope.encodeString();
    final decoded = SyncPersistenceEnvelope.decodeString(jsonText);
    expect(decoded, envelope);
    expect(decoded.accounts[fingerprintA]!.dataEpoch, epoch);
  });
}
