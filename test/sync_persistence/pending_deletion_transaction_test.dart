// Build 26 Phase 5 (slice 1): PendingDeletionTransaction -- the durable
// "Remove from iCloud" deletion transaction shape and stage machine.
// Synthetic content only.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync_persistence/pending_deletion_transaction.dart';

void main() {
  const fingerprintA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final originalEpoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
  final replacementEpoch =
      DataEpoch.parse('22222222-2222-4222-8222-222222222222');

  // Build 26 Phase 5 (slice 1, Mac-validation correction): `originalDataEpoch`
  // must distinguish "the caller omitted this parameter" (use the helper's
  // own convenient non-null default, `originalEpoch`) from "the caller
  // explicitly passed `originalDataEpoch: null`" (a deliberately null
  // original epoch -- the locked semantic for "no prior local
  // AccountSyncState bucket existed when deletion began"). A plain
  // `DataEpoch? originalDataEpoch` parameter defaulting to `null` cannot
  // represent that distinction: both cases arrive as `null` at the call
  // site, so `originalDataEpoch ?? originalEpoch` silently replaced an
  // explicit null with the non-null default -- a test-fixture bug, not a
  // production one (`PendingDeletionTransaction` itself, and every real
  // `tryDecode`/`ProtectedSyncPersistenceStore` path, already preserve a
  // genuine null correctly). A sentinel default resolves the ambiguity.
  const notSpecified = Object();

  PendingDeletionTransaction transaction({
    Object? originalDataEpoch = notSpecified,
    DeletionTransactionStage stage = DeletionTransactionStage.prepared,
  }) {
    final resolvedOriginalDataEpoch = identical(originalDataEpoch, notSpecified)
        ? originalEpoch
        : originalDataEpoch as DataEpoch?;
    return PendingDeletionTransaction(
      accountFingerprint: fingerprintA,
      originalDataEpoch: resolvedOriginalDataEpoch,
      replacementDataEpoch: replacementEpoch,
      stage: stage,
    );
  }

  group('structural invariants', () {
    test(
        'rejects a fingerprint that does not look like an opaque account '
        'fingerprint', () {
      expect(
        () => PendingDeletionTransaction(
          accountFingerprint: 'not-a-real-fingerprint',
          originalDataEpoch: originalEpoch,
          replacementDataEpoch: replacementEpoch,
          stage: DeletionTransactionStage.prepared,
        ),
        throwsA(isA<PendingDeletionTransactionFormatException>()),
      );
    });

    test(
        'rejects a replacementDataEpoch equal to originalDataEpoch -- a '
        'deletion transaction always establishes a genuinely fresh epoch', () {
      expect(
        () => PendingDeletionTransaction(
          accountFingerprint: fingerprintA,
          originalDataEpoch: originalEpoch,
          replacementDataEpoch: originalEpoch,
          stage: DeletionTransactionStage.prepared,
        ),
        throwsA(isA<PendingDeletionTransactionFormatException>()),
      );
    });

    test('accepts a null originalDataEpoch (no bucket existed yet)', () {
      final t = transaction(originalDataEpoch: null);
      expect(t.originalDataEpoch, isNull);
      expect(t.replacementDataEpoch, replacementEpoch);
    });
  });

  group('encode/decode round-trip', () {
    test('round-trips exactly with a non-null originalDataEpoch', () {
      final t = transaction();
      final decoded = PendingDeletionTransaction.tryDecode(t.encode());
      expect(decoded, t);
    });

    test('round-trips exactly with a null originalDataEpoch', () {
      final t = transaction(originalDataEpoch: null);
      final decoded = PendingDeletionTransaction.tryDecode(t.encode());
      expect(decoded, t);
      expect(decoded!.originalDataEpoch, isNull);
    });

    test('round-trips every DeletionTransactionStage value', () {
      for (final stage in DeletionTransactionStage.values) {
        final t = transaction(stage: stage);
        final decoded = PendingDeletionTransaction.tryDecode(t.encode());
        expect(decoded, t, reason: 'Failed to round-trip stage $stage');
      }
    });

    test('tryDecode fails closed on an unrecognized key', () {
      final raw = transaction().encode();
      raw['unexpectedKey'] = 'value';
      expect(PendingDeletionTransaction.tryDecode(raw), isNull);
    });

    test('tryDecode fails closed on a missing accountFingerprint', () {
      final raw = transaction().encode();
      raw.remove('accountFingerprint');
      expect(PendingDeletionTransaction.tryDecode(raw), isNull);
    });

    test('tryDecode fails closed on a malformed accountFingerprint', () {
      final raw = transaction().encode();
      raw['accountFingerprint'] = 'short';
      expect(PendingDeletionTransaction.tryDecode(raw), isNull);
    });

    test('tryDecode fails closed on an invalid originalDataEpoch', () {
      final raw = transaction().encode();
      raw['originalDataEpoch'] = 'not-a-uuid';
      expect(PendingDeletionTransaction.tryDecode(raw), isNull);
    });

    test('tryDecode fails closed on a missing replacementDataEpoch', () {
      final raw = transaction().encode();
      raw.remove('replacementDataEpoch');
      expect(PendingDeletionTransaction.tryDecode(raw), isNull);
    });

    test('tryDecode fails closed on an unrecognized stage value', () {
      final raw = transaction().encode();
      raw['stage'] = 'notARealStage';
      expect(PendingDeletionTransaction.tryDecode(raw), isNull);
    });

    test(
        'tryDecode never throws even for a completely malformed map (fails '
        'closed, returns null)', () {
      expect(
        () => PendingDeletionTransaction.tryDecode(<Object?, Object?>{
          'accountFingerprint': 12345,
          'replacementDataEpoch': null,
          'stage': null,
        }),
        returnsNormally,
      );
      expect(
        PendingDeletionTransaction.tryDecode(<Object?, Object?>{
          'accountFingerprint': 12345,
          'replacementDataEpoch': null,
          'stage': null,
        }),
        isNull,
      );
    });
  });

  group('copyWithStage', () {
    test('changes only the stage; accountFingerprint/epochs are unchanged', () {
      final t = transaction();
      final advanced =
          t.copyWithStage(DeletionTransactionStage.epochBarrierPending);
      expect(advanced.accountFingerprint, t.accountFingerprint);
      expect(advanced.originalDataEpoch, t.originalDataEpoch);
      expect(advanced.replacementDataEpoch, t.replacementDataEpoch);
      expect(advanced.stage, DeletionTransactionStage.epochBarrierPending);
      expect(t.stage, DeletionTransactionStage.prepared,
          reason: 'copyWithStage must not mutate the original instance');
    });
  });

  group('isValidDeletionTransactionTransition', () {
    test('the exact locked forward chain is valid', () {
      expect(
        isValidDeletionTransactionTransition(
          DeletionTransactionStage.prepared,
          DeletionTransactionStage.epochBarrierPending,
        ),
        isTrue,
      );
      expect(
        isValidDeletionTransactionTransition(
          DeletionTransactionStage.epochBarrierPending,
          DeletionTransactionStage.cloudPurgePending,
        ),
        isTrue,
      );
      expect(
        isValidDeletionTransactionTransition(
          DeletionTransactionStage.cloudPurgePending,
          DeletionTransactionStage.verificationPending,
        ),
        isTrue,
      );
      expect(
        isValidDeletionTransactionTransition(
          DeletionTransactionStage.verificationPending,
          DeletionTransactionStage.localFinalizePending,
        ),
        isTrue,
      );
    });

    test(
        'every stage is a valid no-op transition to itself (idempotent '
        'retry)', () {
      for (final stage in DeletionTransactionStage.values) {
        expect(isValidDeletionTransactionTransition(stage, stage), isTrue);
      }
    });

    test('skipping a stage is never valid', () {
      expect(
        isValidDeletionTransactionTransition(
          DeletionTransactionStage.prepared,
          DeletionTransactionStage.cloudPurgePending,
        ),
        isFalse,
      );
      expect(
        isValidDeletionTransactionTransition(
          DeletionTransactionStage.prepared,
          DeletionTransactionStage.localFinalizePending,
        ),
        isFalse,
      );
    });

    test('moving backward is never valid', () {
      expect(
        isValidDeletionTransactionTransition(
          DeletionTransactionStage.cloudPurgePending,
          DeletionTransactionStage.epochBarrierPending,
        ),
        isFalse,
      );
      expect(
        isValidDeletionTransactionTransition(
          DeletionTransactionStage.localFinalizePending,
          DeletionTransactionStage.prepared,
        ),
        isFalse,
      );
    });
  });

  group('privacy', () {
    test(
        'toLogSafeSummary/toString never expose accountFingerprint or an '
        'epoch value', () {
      final t = transaction();
      final summary = t.toLogSafeSummary();
      expect(summary.keys, {'stage'});
      expect(summary['stage'], 'prepared');

      final rendered = t.toString();
      expect(rendered, isNot(contains(fingerprintA)));
      expect(rendered, isNot(contains(originalEpoch.value)));
      expect(rendered, isNot(contains(replacementEpoch.value)));
    });
  });
}
