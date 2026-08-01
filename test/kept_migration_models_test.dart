import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_migration_journal.dart';
import 'package:wisdom_app/models/kept_migration_recovery_artifact.dart';
import 'package:wisdom_app/models/kept_migration_snapshot.dart';

void main() {
  const migrationId = '123e4567-e89b-4d3a-a456-426614174000';
  final startedAt = DateTime.utc(2026, 8, 1, 9, 0);
  final updatedAt = DateTime.utc(2026, 8, 1, 9, 5);

  group('KeptMigrationJournal', () {
    test('1a. a writing journal with partial metadata round-trips', () {
      final journal = KeptMigrationJournal(
        state: KeptMigrationState.writing,
        migrationId: migrationId,
        startedAt: startedAt,
        updatedAt: updatedAt,
      );

      final decoded = KeptMigrationJournal.decodeString(journal.encodeString());

      expect(decoded, journal);
      expect(decoded.state, KeptMigrationState.writing);
    });

    test('1b. a verified journal with full metadata round-trips', () {
      final journal = KeptMigrationJournal(
        state: KeptMigrationState.verified,
        migrationId: migrationId,
        startedAt: startedAt,
        updatedAt: updatedAt,
        legacyEntryCount: 3,
        usableEntryCount: 2,
        corruptEntryCount: 1,
        snapshotFileName: 'east_kept_migration_snapshot_v1-$migrationId.json',
        recoveryFileName: 'east_kept_migration_recovery_v1-$migrationId.json',
      );

      final decoded = KeptMigrationJournal.decodeString(journal.encodeString());

      expect(decoded, journal);
    });

    test('1c. a complete journal preserving verified metadata round-trips', () {
      final journal = KeptMigrationJournal(
        state: KeptMigrationState.complete,
        migrationId: migrationId,
        startedAt: startedAt,
        updatedAt: updatedAt,
        legacyEntryCount: 3,
        usableEntryCount: 3,
        corruptEntryCount: 0,
        snapshotFileName: 'east_kept_migration_snapshot_v1-$migrationId.json',
      );

      final decoded = KeptMigrationJournal.decodeString(journal.encodeString());

      expect(decoded, journal);
      expect(decoded.recoveryFileName, isNull);
    });

    test('2. a malformed journal is rejected on decode', () {
      final journal = KeptMigrationJournal(
        state: KeptMigrationState.writing,
        migrationId: migrationId,
        startedAt: startedAt,
        updatedAt: updatedAt,
      );
      final map = journal.encode();
      map['state'] = 'not-a-real-state';

      expect(() => KeptMigrationJournal.decode(map), throwsFormatException);

      final missingSchema = journal.encode()..remove('schemaVersion');
      expect(
        () => KeptMigrationJournal.decode(missingSchema),
        throwsFormatException,
      );

      final wrongSchema = journal.encode()..['schemaVersion'] = 99;
      expect(
        () => KeptMigrationJournal.decode(wrongSchema),
        throwsFormatException,
      );

      final badMigrationId = journal.encode()..['migrationId'] = 'not-a-uuid';
      expect(
        () => KeptMigrationJournal.decode(badMigrationId),
        throwsFormatException,
      );
    });

    test('3. a verified journal missing required metadata is rejected', () {
      expect(
        () => KeptMigrationJournal(
          state: KeptMigrationState.verified,
          migrationId: migrationId,
          startedAt: startedAt,
          updatedAt: updatedAt,
          legacyEntryCount: 3,
          usableEntryCount: 3,
          // corruptEntryCount and snapshotFileName missing.
        ),
        throwsFormatException,
      );

      expect(
        () => KeptMigrationJournal(
          state: KeptMigrationState.verified,
          migrationId: migrationId,
          startedAt: startedAt,
          updatedAt: updatedAt,
          legacyEntryCount: 3,
          usableEntryCount: 3,
          corruptEntryCount: 0,
          // snapshotFileName still missing.
        ),
        throwsFormatException,
      );
    });

    test('4. journal count invariants are enforced', () {
      // Negative counts rejected.
      expect(
        () => KeptMigrationJournal(
          state: KeptMigrationState.writing,
          migrationId: migrationId,
          startedAt: startedAt,
          updatedAt: updatedAt,
          legacyEntryCount: -1,
        ),
        throwsFormatException,
      );

      // usable + corrupt must equal legacy when all three present.
      expect(
        () => KeptMigrationJournal(
          state: KeptMigrationState.verified,
          migrationId: migrationId,
          startedAt: startedAt,
          updatedAt: updatedAt,
          legacyEntryCount: 3,
          usableEntryCount: 1,
          corruptEntryCount: 1,
          snapshotFileName: 'snap.json',
        ),
        throwsFormatException,
      );

      // recoveryFileName must be present iff corruptEntryCount > 0.
      expect(
        () => KeptMigrationJournal(
          state: KeptMigrationState.verified,
          migrationId: migrationId,
          startedAt: startedAt,
          updatedAt: updatedAt,
          legacyEntryCount: 3,
          usableEntryCount: 2,
          corruptEntryCount: 1,
          snapshotFileName: 'snap.json',
          // recoveryFileName missing despite corruptEntryCount > 0.
        ),
        throwsFormatException,
      );
      expect(
        () => KeptMigrationJournal(
          state: KeptMigrationState.verified,
          migrationId: migrationId,
          startedAt: startedAt,
          updatedAt: updatedAt,
          legacyEntryCount: 3,
          usableEntryCount: 3,
          corruptEntryCount: 0,
          snapshotFileName: 'snap.json',
          recoveryFileName: 'recovery.json',
        ),
        throwsFormatException,
      );
    });

    test(
        'a writing journal may genuinely omit every optional field — the '
        'sum/correlation invariants only apply once the relevant fields '
        'are actually present', () {
      expect(
        () => KeptMigrationJournal(
          state: KeptMigrationState.writing,
          migrationId: migrationId,
          startedAt: startedAt,
          updatedAt: updatedAt,
        ),
        returnsNormally,
      );
      expect(
        () => KeptMigrationJournal(
          state: KeptMigrationState.writing,
          migrationId: migrationId,
          startedAt: startedAt,
          updatedAt: updatedAt,
          legacyEntryCount: 3,
          snapshotFileName: 'snap.json',
          // usableEntryCount/corruptEntryCount genuinely not yet known.
        ),
        returnsNormally,
      );
    });

    test(
        'writing still rejects a self-contradictory recoveryFileName/'
        'corruptEntryCount combination even though other fields are '
        'partial', () {
      expect(
        () => KeptMigrationJournal(
          state: KeptMigrationState.writing,
          migrationId: migrationId,
          startedAt: startedAt,
          updatedAt: updatedAt,
          corruptEntryCount: 0,
          recoveryFileName: 'recovery.json',
        ),
        throwsFormatException,
      );
      expect(
        () => KeptMigrationJournal(
          state: KeptMigrationState.writing,
          migrationId: migrationId,
          startedAt: startedAt,
          updatedAt: updatedAt,
          corruptEntryCount: 2,
          // recoveryFileName missing despite corruptEntryCount > 0.
        ),
        throwsFormatException,
      );
    });

    test(
        'verified/complete never accept omitted counts or a missing '
        'snapshotFileName — the partial-metadata allowance is writing-only',
        () {
      for (final state in [
        KeptMigrationState.verified,
        KeptMigrationState.complete,
      ]) {
        expect(
          () => KeptMigrationJournal(
            state: state,
            migrationId: migrationId,
            startedAt: startedAt,
            updatedAt: updatedAt,
          ),
          throwsFormatException,
          reason: '$state must require full metadata',
        );
      }
    });

    test('timestamps normalize to UTC without changing the instant', () {
      final localStarted = DateTime(2026, 8, 1, 12, 0);
      final journal = KeptMigrationJournal(
        state: KeptMigrationState.writing,
        migrationId: migrationId,
        startedAt: localStarted,
        updatedAt: localStarted,
      );

      expect(journal.startedAt.isUtc, isTrue);
      expect(
        journal.startedAt.millisecondsSinceEpoch,
        localStarted.millisecondsSinceEpoch,
      );
    });

    test('copyWith updates only requested fields', () {
      final journal = KeptMigrationJournal(
        state: KeptMigrationState.writing,
        migrationId: migrationId,
        startedAt: startedAt,
        updatedAt: updatedAt,
      );

      final updated = journal.copyWith(
        legacyEntryCount: 5,
        snapshotFileName: 'snap.json',
      );

      expect(updated.migrationId, journal.migrationId);
      expect(updated.startedAt, journal.startedAt);
      expect(updated.legacyEntryCount, 5);
      expect(updated.snapshotFileName, 'snap.json');
      expect(journal.legacyEntryCount, isNull);
    });

    test('unknown additive JSON keys are ignored on decode', () {
      final journal = KeptMigrationJournal(
        state: KeptMigrationState.writing,
        migrationId: migrationId,
        startedAt: startedAt,
        updatedAt: updatedAt,
      );
      final map = journal.encode()..['futureField'] = 'reserved';

      expect(() => KeptMigrationJournal.decode(map), returnsNormally);
      expect(KeptMigrationJournal.decode(map), journal);
    });
  });

  group('KeptMigrationSnapshot', () {
    final capturedAt = DateTime.utc(2026, 8, 1, 9, 0);

    test('5. snapshot round-trips preserving exact raw values and order', () {
      final snapshot = KeptMigrationSnapshot(
        migrationId: migrationId,
        capturedAt: capturedAt,
        legacyKey: 'favorites',
        entries: const [
          KeptMigrationSnapshotEntry(index: 0, rawValue: 'first|||text one'),
          KeptMigrationSnapshotEntry(index: 1, rawValue: '{"id":"a"}'),
          KeptMigrationSnapshotEntry(index: 2, rawValue: ''),
        ],
      );

      final decoded =
          KeptMigrationSnapshot.decodeString(snapshot.encodeString());

      expect(decoded, snapshot);
      expect(
        decoded.entries.map((e) => e.rawValue).toList(),
        ['first|||text one', '{"id":"a"}', ''],
      );
    });

    test('6. noncontiguous snapshot indices are rejected', () {
      expect(
        () => KeptMigrationSnapshot(
          migrationId: migrationId,
          capturedAt: capturedAt,
          legacyKey: 'favorites',
          entries: const [
            KeptMigrationSnapshotEntry(index: 0, rawValue: 'a'),
            KeptMigrationSnapshotEntry(index: 2, rawValue: 'b'),
          ],
        ),
        throwsFormatException,
      );

      expect(
        () => KeptMigrationSnapshot(
          migrationId: migrationId,
          capturedAt: capturedAt,
          legacyKey: 'favorites',
          entries: const [
            KeptMigrationSnapshotEntry(index: 1, rawValue: 'a'),
          ],
        ),
        throwsFormatException,
      );
    });

    test('rejects a legacyKey other than favorites', () {
      expect(
        () => KeptMigrationSnapshot(
          migrationId: migrationId,
          capturedAt: capturedAt,
          legacyKey: 'something_else',
        ),
        throwsFormatException,
      );
    });

    test('10a. the entries list is immutable', () {
      final snapshot = KeptMigrationSnapshot(
        migrationId: migrationId,
        capturedAt: capturedAt,
        legacyKey: 'favorites',
        entries: const [KeptMigrationSnapshotEntry(index: 0, rawValue: 'a')],
      );

      expect(
        () => snapshot.entries.add(
          const KeptMigrationSnapshotEntry(index: 1, rawValue: 'b'),
        ),
        throwsUnsupportedError,
      );
    });

    test('9a. unknown additive snapshot keys are ignored', () {
      final snapshot = KeptMigrationSnapshot(
        migrationId: migrationId,
        capturedAt: capturedAt,
        legacyKey: 'favorites',
        entries: const [KeptMigrationSnapshotEntry(index: 0, rawValue: 'a')],
      );
      final map = snapshot.encode()..['futureField'] = 'reserved';

      expect(() => KeptMigrationSnapshot.decode(map), returnsNormally);
      expect(KeptMigrationSnapshot.decode(map), snapshot);
    });

    test('value equality is based on contents, not identity', () {
      final a = KeptMigrationSnapshot(
        migrationId: migrationId,
        capturedAt: capturedAt,
        legacyKey: 'favorites',
        entries: const [KeptMigrationSnapshotEntry(index: 0, rawValue: 'a')],
      );
      final b = KeptMigrationSnapshot(
        migrationId: migrationId,
        capturedAt: capturedAt,
        legacyKey: 'favorites',
        entries: const [KeptMigrationSnapshotEntry(index: 0, rawValue: 'a')],
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('KeptMigrationRecoveryArtifact', () {
    final createdAt = DateTime.utc(2026, 8, 1, 9, 10);

    test('7. recovery artifact round-trips', () {
      final artifact = KeptMigrationRecoveryArtifact(
        migrationId: migrationId,
        createdAt: createdAt,
        legacyEntryCount: 3,
        usableEntryCount: 1,
        corruptEntries: const [
          KeptMigrationRecoveryEntry(
            index: 0,
            rawValue: 'garbage',
            stage: KeptMigrationFailureStage.decode,
            reasonCode: 'favorite_decode_failed',
          ),
          KeptMigrationRecoveryEntry(
            index: 2,
            rawValue: '{"id":"x","date":"not-a-date","text":"t"}',
            stage: KeptMigrationFailureStage.convert,
            reasonCode: 'kept_record_validation_failed',
          ),
        ],
      );

      final decoded =
          KeptMigrationRecoveryArtifact.decodeString(artifact.encodeString());

      expect(decoded, artifact);
      expect(decoded.corruptEntries[0].stage, KeptMigrationFailureStage.decode);
      expect(
        decoded.corruptEntries[1].stage,
        KeptMigrationFailureStage.convert,
      );
    });

    test('8. recovery artifact count invariants are enforced', () {
      // usable + corrupt must equal legacy count.
      expect(
        () => KeptMigrationRecoveryArtifact(
          migrationId: migrationId,
          createdAt: createdAt,
          legacyEntryCount: 3,
          usableEntryCount: 1,
          corruptEntries: const [
            KeptMigrationRecoveryEntry(
              index: 0,
              rawValue: 'a',
              stage: KeptMigrationFailureStage.decode,
              reasonCode: 'favorite_decode_failed',
            ),
          ],
        ),
        throwsFormatException,
      );

      // Negative counts rejected.
      expect(
        () => KeptMigrationRecoveryArtifact(
          migrationId: migrationId,
          createdAt: createdAt,
          legacyEntryCount: -1,
          usableEntryCount: 0,
        ),
        throwsFormatException,
      );

      // Duplicate entry index rejected.
      expect(
        () => KeptMigrationRecoveryArtifact(
          migrationId: migrationId,
          createdAt: createdAt,
          legacyEntryCount: 2,
          usableEntryCount: 0,
          corruptEntries: const [
            KeptMigrationRecoveryEntry(
              index: 0,
              rawValue: 'a',
              stage: KeptMigrationFailureStage.decode,
              reasonCode: 'favorite_decode_failed',
            ),
            KeptMigrationRecoveryEntry(
              index: 0,
              rawValue: 'b',
              stage: KeptMigrationFailureStage.decode,
              reasonCode: 'favorite_decode_failed',
            ),
          ],
        ),
        throwsFormatException,
      );

      // Blank reasonCode rejected.
      expect(
        () => KeptMigrationRecoveryArtifact(
          migrationId: migrationId,
          createdAt: createdAt,
          legacyEntryCount: 1,
          usableEntryCount: 0,
          corruptEntries: const [
            KeptMigrationRecoveryEntry(
              index: 0,
              rawValue: 'a',
              stage: KeptMigrationFailureStage.decode,
              reasonCode: '  ',
            ),
          ],
        ),
        throwsFormatException,
      );
    });

    test('9b. unknown additive recovery-artifact keys are ignored', () {
      final artifact = KeptMigrationRecoveryArtifact(
        migrationId: migrationId,
        createdAt: createdAt,
        legacyEntryCount: 1,
        usableEntryCount: 0,
        corruptEntries: const [
          KeptMigrationRecoveryEntry(
            index: 0,
            rawValue: 'a',
            stage: KeptMigrationFailureStage.decode,
            reasonCode: 'favorite_decode_failed',
          ),
        ],
      );
      final map = artifact.encode()..['futureField'] = 'reserved';

      expect(() => KeptMigrationRecoveryArtifact.decode(map), returnsNormally);
      expect(KeptMigrationRecoveryArtifact.decode(map), artifact);
    });

    test('10b. the corruptEntries list is immutable and equality is by value',
        () {
      final artifact = KeptMigrationRecoveryArtifact(
        migrationId: migrationId,
        createdAt: createdAt,
        legacyEntryCount: 1,
        usableEntryCount: 0,
        corruptEntries: const [
          KeptMigrationRecoveryEntry(
            index: 0,
            rawValue: 'a',
            stage: KeptMigrationFailureStage.decode,
            reasonCode: 'favorite_decode_failed',
          ),
        ],
      );

      expect(
        () => artifact.corruptEntries.add(
          const KeptMigrationRecoveryEntry(
            index: 1,
            rawValue: 'b',
            stage: KeptMigrationFailureStage.decode,
            reasonCode: 'favorite_decode_failed',
          ),
        ),
        throwsUnsupportedError,
      );

      final same = KeptMigrationRecoveryArtifact(
        migrationId: migrationId,
        createdAt: createdAt,
        legacyEntryCount: 1,
        usableEntryCount: 0,
        corruptEntries: const [
          KeptMigrationRecoveryEntry(
            index: 0,
            rawValue: 'a',
            stage: KeptMigrationFailureStage.decode,
            reasonCode: 'favorite_decode_failed',
          ),
        ],
      );
      expect(artifact, same);
      expect(artifact.hashCode, same.hashCode);
    });
  });
}
