import 'package:uuid/uuid.dart';

import '../models/favorite_item.dart';
import '../models/kept_migration_journal.dart';
import '../models/kept_migration_recovery_artifact.dart';
import '../models/kept_migration_snapshot.dart';
import '../models/kept_record.dart';
import '../models/kept_state_envelope.dart';
import '../persistence/kept_migration_artifact_store.dart';
import '../persistence/kept_migration_journal_store.dart';
import '../persistence/kept_state_store.dart';
import '../persistence/legacy_favorites_store.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/stored_favorite_entry_codec.dart';
import '../utils/favorite_date_codec.dart';

/// Thrown by [KeptMigrationCoordinator.migrateIfNeeded] on any failure.
/// Never carries wisdom text, reflection text, or raw legacy values —
/// only a stage code, a safe human-readable message, and an optional
/// diagnostic cause.
class KeptMigrationException implements Exception {
  const KeptMigrationException(this.stage, this.message, [this.cause]);

  final String stage;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    if (cause == null) return 'KeptMigrationException[$stage]: $message';
    return 'KeptMigrationException[$stage]: $message ($cause)';
  }
}

/// Outcome of one [KeptMigrationCoordinator.migrateIfNeeded] call.
enum KeptMigrationStatus {
  /// No legacy data and no protected envelope existed; nothing to do.
  noLegacyData,

  /// No legacy data, but a protected envelope already existed.
  alreadyProtected,

  /// Migration ran to completion (or completed a pending retry) on this
  /// call.
  migrated,

  /// A previously completed migration was confirmed complete again; no
  /// work was needed.
  alreadyComplete,
}

/// Small, content-free summary of a [KeptMigrationCoordinator.migrateIfNeeded]
/// call. Never exposes wisdom text, reflection text, or raw legacy values.
class KeptMigrationResult {
  const KeptMigrationResult({
    required this.status,
    required this.migratedCount,
    required this.corruptCount,
    required this.legacyCleanupCompleted,
  });

  final KeptMigrationStatus status;
  final int migratedCount;
  final int corruptCount;
  final bool legacyCleanupCompleted;
}

class _RebuiltMigration {
  const _RebuiltMigration({
    required this.usableRecords,
    required this.recoveryEntries,
  });

  final List<KeptRecord> usableRecords;
  final List<KeptMigrationRecoveryEntry> recoveryEntries;
}

/// Coordinates the one-time, crash-safe migration of Build 25's legacy
/// `favorites` SharedPreferences StringList into the Phase 3B protected
/// Kept-state envelope.
///
/// The entire operation — reading the journal, reading legacy data,
/// writing snapshots/recovery artifacts, replacing the protected envelope,
/// and legacy cleanup — runs inside one [PersistenceOperationCoordinator]
/// critical section on [resourceKey], so concurrent [migrateIfNeeded] calls
/// are strictly serialized. No private helper here re-enters that
/// coordinator.
final class KeptMigrationCoordinator {
  KeptMigrationCoordinator({
    required LegacyFavoritesStore legacyFavoritesStore,
    required KeptMigrationJournalStore journalStore,
    required KeptMigrationArtifactStore artifactStore,
    required KeptStateStore keptStateStore,
    PersistenceOperationCoordinator? operationCoordinator,
    String Function()? migrationIdFactory,
    DateTime Function()? clock,
    String Function(String name)? uuidV5Factory,
  })  : _legacyFavoritesStore = legacyFavoritesStore,
        _journalStore = journalStore,
        _artifactStore = artifactStore,
        _keptStateStore = keptStateStore,
        _coordinator =
            operationCoordinator ?? PersistenceOperationCoordinator(),
        _migrationIdFactory = migrationIdFactory ?? (() => const Uuid().v4()),
        _clock = clock ?? DateTime.now,
        _uuidV5Factory = uuidV5Factory ??
            ((name) => const Uuid().v5(Namespace.url.value, name));

  static const String resourceKey = 'kept_storage_migration_v3';

  final LegacyFavoritesStore _legacyFavoritesStore;
  final KeptMigrationJournalStore _journalStore;
  final KeptMigrationArtifactStore _artifactStore;
  final KeptStateStore _keptStateStore;
  final PersistenceOperationCoordinator _coordinator;
  final String Function() _migrationIdFactory;
  final DateTime Function() _clock;
  final String Function(String name) _uuidV5Factory;

  Future<KeptMigrationResult> migrateIfNeeded() {
    return _coordinator.runExclusive<KeptMigrationResult>(
      resourceKey: resourceKey,
      operation: _migrateIfNeeded,
    );
  }

  Future<KeptMigrationResult> _migrateIfNeeded() async {
    final journal = await _wrap('journal-read', () => _journalStore.load());
    if (journal == null) {
      return _handleNotStarted();
    }
    switch (journal.state) {
      case KeptMigrationState.writing:
        return _handleWriting(journal);
      case KeptMigrationState.verified:
        return _handleVerified(journal);
      case KeptMigrationState.complete:
        return _handleComplete(journal);
    }
  }

  // ---------------------------------------------------------------------
  // A. No journal / not started.
  // ---------------------------------------------------------------------

  Future<KeptMigrationResult> _handleNotStarted() async {
    final legacyExists = await _wrap(
      'read-legacy-exists',
      () => _legacyFavoritesStore.containsLegacyData(),
    );
    final existingEnvelope =
        await _wrap('read-protected-envelope', () => _keptStateStore.load());

    if (!legacyExists && existingEnvelope == null) {
      return const KeptMigrationResult(
        status: KeptMigrationStatus.noLegacyData,
        migratedCount: 0,
        corruptCount: 0,
        legacyCleanupCompleted: false,
      );
    }

    if (!legacyExists && existingEnvelope != null) {
      return const KeptMigrationResult(
        status: KeptMigrationStatus.alreadyProtected,
        migratedCount: 0,
        corruptCount: 0,
        legacyCleanupCompleted: true,
      );
    }

    if (legacyExists && existingEnvelope != null) {
      throw const KeptMigrationException(
        'unexpected-existing-protected-state',
        'Legacy favorites data and a protected envelope both exist '
            'unexpectedly.',
      );
    }

    // legacyExists && existingEnvelope == null.
    final migrationId = _migrationIdFactory();
    final now = _clock();
    final journal = KeptMigrationJournal(
      state: KeptMigrationState.writing,
      migrationId: migrationId,
      startedAt: now,
      updatedAt: now,
    );
    await _wrap('journal-write', () => _journalStore.save(journal));
    return _handleWriting(journal);
  }

  // ---------------------------------------------------------------------
  // B. Writing.
  // ---------------------------------------------------------------------

  Future<KeptMigrationResult> _handleWriting(
      KeptMigrationJournal journal) async {
    var currentJournal = journal;
    KeptMigrationSnapshot snapshot;

    if (currentJournal.snapshotFileName != null) {
      final loaded = await _wrap(
        'snapshot-load',
        () => _artifactStore.loadSnapshot(currentJournal.snapshotFileName!),
      );
      if (loaded == null) {
        throw const KeptMigrationException(
          'snapshot-missing',
          'The migration journal references a snapshot that could not be '
              'found.',
        );
      }
      if (loaded.migrationId != currentJournal.migrationId) {
        throw const KeptMigrationException(
          'snapshot-mismatch',
          'The migration snapshot does not match the current migration.',
        );
      }
      snapshot = loaded;
    } else {
      final rawEntries = await _wrap(
        'legacy-read',
        () => _legacyFavoritesStore.readRawEntries(),
      );
      if (rawEntries == null) {
        throw const KeptMigrationException(
          'legacy-key-missing',
          'The legacy favorites key disappeared during migration.',
        );
      }

      final entries = <KeptMigrationSnapshotEntry>[
        for (var i = 0; i < rawEntries.length; i += 1)
          KeptMigrationSnapshotEntry(index: i, rawValue: rawEntries[i]),
      ];
      final builtSnapshot = KeptMigrationSnapshot(
        migrationId: currentJournal.migrationId,
        capturedAt: _clock(),
        legacyKey: 'favorites',
        entries: entries,
      );
      final fileName = _snapshotFileName(currentJournal.migrationId);
      await _wrap(
        'snapshot-write',
        () => _artifactStore.writeSnapshot(fileName, builtSnapshot),
      );
      snapshot = builtSnapshot;

      currentJournal = currentJournal.copyWith(
        legacyEntryCount: entries.length,
        snapshotFileName: fileName,
        updatedAt: _clock(),
      );
      await _wrap('journal-write', () => _journalStore.save(currentJournal));
    }

    final rebuilt = _rebuildFromSnapshot(snapshot);

    String? recoveryFileName;
    if (rebuilt.recoveryEntries.isNotEmpty) {
      final artifact = KeptMigrationRecoveryArtifact(
        migrationId: currentJournal.migrationId,
        createdAt: _clock(),
        legacyEntryCount: snapshot.entries.length,
        usableEntryCount: rebuilt.usableRecords.length,
        corruptEntries: rebuilt.recoveryEntries,
      );
      recoveryFileName = _recoveryFileName(currentJournal.migrationId);
      await _wrap(
        'recovery-write',
        () => _artifactStore.writeRecoveryArtifact(recoveryFileName!, artifact),
      );
    }

    final duplicateEntries = rebuilt.recoveryEntries
        .where((e) => e.stage == KeptMigrationFailureStage.duplicateIdentity)
        .toList();
    if (duplicateEntries.isNotEmpty) {
      // The recovery artifact (including these conflicts) has already been
      // safely written above. Remain in writing, keep the legacy key, and
      // block — the required active-record identity cannot safely
      // preserve both conflicting records.
      throw const KeptMigrationException(
        'duplicate-identity-conflict',
        'Migration found conflicting Kept identities and cannot proceed '
            'safely.',
      );
    }

    if (rebuilt.recoveryEntries.isNotEmpty) {
      currentJournal = currentJournal.copyWith(
        usableEntryCount: rebuilt.usableRecords.length,
        corruptEntryCount: rebuilt.recoveryEntries.length,
        recoveryFileName: recoveryFileName,
        updatedAt: _clock(),
      );
      await _wrap('journal-write', () => _journalStore.save(currentJournal));
    }

    final expectedEnvelope =
        KeptStateEnvelope(activeRecords: rebuilt.usableRecords);

    final existingEnvelope =
        await _wrap('envelope-read', () => _keptStateStore.load());
    if (existingEnvelope == null) {
      await _wrap(
        'envelope-replace',
        () => _keptStateStore.replace(expectedEnvelope),
      );
    } else if (existingEnvelope == expectedEnvelope) {
      // Retry after a crash between replace() and journal update: continue.
    } else {
      throw const KeptMigrationException(
        'unexpected-envelope-mismatch',
        'An unexpected existing protected envelope does not match the '
            'migrated data.',
      );
    }

    final reloaded =
        await _wrap('envelope-reload', () => _keptStateStore.load());
    if (reloaded == null) {
      throw const KeptMigrationException(
        'envelope-readback-missing',
        'The protected envelope could not be read back after migration.',
      );
    }
    _verifyFieldByField(reloaded, expectedEnvelope);

    if (rebuilt.recoveryEntries.isNotEmpty) {
      final storedArtifact = await _wrap(
        'recovery-verify',
        () => _artifactStore.loadRecoveryArtifact(recoveryFileName!),
      );
      if (storedArtifact == null) {
        throw const KeptMigrationException(
          'recovery-artifact-missing',
          'The recovery artifact could not be found for verification.',
        );
      }
      if (storedArtifact.corruptEntries.length !=
          rebuilt.recoveryEntries.length) {
        throw const KeptMigrationException(
          'recovery-artifact-mismatch',
          'The recovery artifact does not match the expected corrupt '
              'entries.',
        );
      }
    }

    final verifiedJournal = currentJournal.copyWith(
      state: KeptMigrationState.verified,
      legacyEntryCount: snapshot.entries.length,
      usableEntryCount: rebuilt.usableRecords.length,
      corruptEntryCount: rebuilt.recoveryEntries.length,
      recoveryFileName: recoveryFileName,
      updatedAt: _clock(),
    );
    await _wrap('journal-write', () => _journalStore.save(verifiedJournal));

    return _handleVerified(verifiedJournal);
  }

  // ---------------------------------------------------------------------
  // C. Verified.
  // ---------------------------------------------------------------------

  Future<KeptMigrationResult> _handleVerified(
      KeptMigrationJournal journal) async {
    if (journal.snapshotFileName == null) {
      throw const KeptMigrationException(
        'verified-missing-snapshot-name',
        'A verified migration journal is missing its snapshot file name.',
      );
    }
    final snapshot = await _wrap(
      'verified-snapshot-load',
      () => _artifactStore.loadSnapshot(journal.snapshotFileName!),
    );
    if (snapshot == null) {
      throw const KeptMigrationException(
        'verified-snapshot-missing',
        'The migration snapshot referenced by a verified journal could '
            'not be found.',
      );
    }
    if (snapshot.migrationId != journal.migrationId) {
      throw const KeptMigrationException(
        'verified-snapshot-mismatch',
        'The migration snapshot does not match the verified journal.',
      );
    }

    final rebuilt = _rebuildFromSnapshot(snapshot);
    final expectedEnvelope =
        KeptStateEnvelope(activeRecords: rebuilt.usableRecords);

    if (rebuilt.recoveryEntries.isNotEmpty) {
      if (journal.recoveryFileName == null) {
        throw const KeptMigrationException(
          'verified-missing-recovery-name',
          'A verified migration journal with corrupt entries is missing '
              'its recovery file name.',
        );
      }
      final artifact = await _wrap(
        'verified-recovery-load',
        () => _artifactStore.loadRecoveryArtifact(journal.recoveryFileName!),
      );
      if (artifact == null) {
        throw const KeptMigrationException(
          'verified-recovery-missing',
          'The recovery artifact referenced by a verified journal could '
              'not be found.',
        );
      }
      _verifyRecoveryArtifactMatches(
        stage: 'verified',
        artifact: artifact,
        journal: journal,
        snapshot: snapshot,
        rebuilt: rebuilt,
      );
    } else if (journal.recoveryFileName != null) {
      throw const KeptMigrationException(
        'verified-unexpected-recovery-name',
        'A verified journal unexpectedly references a recovery artifact.',
      );
    }

    final protectedEnvelope =
        await _wrap('verified-envelope-load', () => _keptStateStore.load());
    if (protectedEnvelope == null) {
      throw const KeptMigrationException(
        'verified-envelope-missing',
        'The protected envelope is missing during verified-state cleanup.',
      );
    }
    _verifyFieldByField(protectedEnvelope, expectedEnvelope);

    if (journal.legacyEntryCount != snapshot.entries.length ||
        journal.usableEntryCount != rebuilt.usableRecords.length ||
        journal.corruptEntryCount != rebuilt.recoveryEntries.length) {
      throw const KeptMigrationException(
        'verified-count-mismatch',
        'The verified journal counts do not match the reconstructed '
            'migration data.',
      );
    }

    // Only now — after every re-verification above — may legacy cleanup
    // proceed.
    final legacyStillPresent = await _wrap(
      'verified-legacy-check',
      () => _legacyFavoritesStore.containsLegacyData(),
    );
    if (legacyStillPresent) {
      await _wrap(
          'cleanup-failed', () => _legacyFavoritesStore.removeAndVerify());
    }

    final completeJournal = journal.copyWith(
      state: KeptMigrationState.complete,
      updatedAt: _clock(),
    );
    await _wrap('journal-write', () => _journalStore.save(completeJournal));

    return KeptMigrationResult(
      status: KeptMigrationStatus.migrated,
      migratedCount: rebuilt.usableRecords.length,
      corruptCount: rebuilt.recoveryEntries.length,
      legacyCleanupCompleted: true,
    );
  }

  // ---------------------------------------------------------------------
  // D. Complete.
  // ---------------------------------------------------------------------

  /// A `complete` journal is not merely a cached "yes, this happened"
  /// flag — every call fully re-derives and re-verifies the migration from
  /// the frozen snapshot and compares it against the live protected
  /// envelope (and recovery artifact, when one is expected) before ever
  /// reporting success. Nothing is rewritten here: the envelope, snapshot,
  /// recovery artifact, and journal are all read-only in this path.
  Future<KeptMigrationResult> _handleComplete(
      KeptMigrationJournal journal) async {
    // 1. Legacy reappearance must be checked before anything else, and
    // blocks immediately — never merged, never removed.
    final legacyStillPresent = await _wrap(
      'complete-legacy-check',
      () => _legacyFavoritesStore.containsLegacyData(),
    );
    if (legacyStillPresent) {
      throw const KeptMigrationException(
        'legacy-data-reappeared',
        'Legacy favorites data reappeared after migration completed.',
      );
    }

    final snapshotFileName = journal.snapshotFileName;
    if (snapshotFileName == null) {
      throw const KeptMigrationException(
        'complete-missing-snapshot-name',
        'A completed migration journal is missing its snapshot file name.',
      );
    }

    // 2. Require and load the referenced snapshot.
    final snapshot = await _wrap(
      'complete-snapshot-load',
      () => _artifactStore.loadSnapshot(snapshotFileName),
    );
    if (snapshot == null) {
      throw const KeptMigrationException(
        'complete-snapshot-missing',
        'The migration snapshot referenced by a completed journal could '
            'not be found.',
      );
    }

    // 3. Verify snapshot/journal identity and counts.
    if (snapshot.migrationId != journal.migrationId) {
      throw const KeptMigrationException(
        'complete-snapshot-mismatch',
        'The migration snapshot does not match the completed journal.',
      );
    }

    // 4-5. Re-run decoding/conversion from the frozen snapshot and
    // reconstruct the exact expected envelope.
    final rebuilt = _rebuildFromSnapshot(snapshot);
    final expectedEnvelope =
        KeptStateEnvelope(activeRecords: rebuilt.usableRecords);

    if (journal.legacyEntryCount != snapshot.entries.length ||
        journal.usableEntryCount != rebuilt.usableRecords.length ||
        journal.corruptEntryCount != rebuilt.recoveryEntries.length) {
      throw const KeptMigrationException(
        'complete-count-mismatch',
        'The completed journal counts do not match the reconstructed '
            'migration data.',
      );
    }

    // 6. Reload the protected authoritative envelope.
    final protectedEnvelope = await _wrap(
      'complete-envelope-load',
      () => _keptStateStore.load(),
    );
    if (protectedEnvelope == null) {
      throw const KeptMigrationException(
        'complete-envelope-missing',
        'The protected envelope is missing for a completed migration.',
      );
    }

    // 7. Verify exact record count, order, and every KeptRecord field —
    // KeptRecord's own operator== already compares every named field.
    _verifyFieldByField(protectedEnvelope, expectedEnvelope);

    // 8-9. Recovery artifact presence must exactly correlate with corrupt
    // count, and its contents must match the reconstructed corruption
    // results exactly (migrationId, counts, indices, stages, reason codes,
    // and raw values).
    if (rebuilt.recoveryEntries.isNotEmpty) {
      final recoveryFileName = journal.recoveryFileName;
      if (recoveryFileName == null) {
        throw const KeptMigrationException(
          'complete-missing-recovery-name',
          'A completed journal with corrupt entries is missing its '
              'recovery file name.',
        );
      }
      final artifact = await _wrap(
        'complete-recovery-load',
        () => _artifactStore.loadRecoveryArtifact(recoveryFileName),
      );
      if (artifact == null) {
        throw const KeptMigrationException(
          'complete-recovery-missing',
          'The recovery artifact referenced by a completed journal '
              'could not be found.',
        );
      }
      _verifyRecoveryArtifactMatches(
        stage: 'complete',
        artifact: artifact,
        journal: journal,
        snapshot: snapshot,
        rebuilt: rebuilt,
      );
    } else if (journal.recoveryFileName != null) {
      throw const KeptMigrationException(
        'complete-unexpected-recovery-name',
        'A completed journal unexpectedly references a recovery artifact.',
      );
    }

    // 10. Only after every verification above succeeds.
    return KeptMigrationResult(
      status: KeptMigrationStatus.alreadyComplete,
      migratedCount: rebuilt.usableRecords.length,
      corruptCount: rebuilt.recoveryEntries.length,
      legacyCleanupCompleted: true,
    );
  }

  /// Shared by [_handleVerified] and [_handleComplete]: verifies a loaded
  /// recovery artifact matches the journal's own migrationId and the
  /// freshly reconstructed corruption results exactly — not merely by
  /// count, but migrationId, per-entry index, stage, reasonCode, and raw
  /// value.
  void _verifyRecoveryArtifactMatches({
    required String stage,
    required KeptMigrationRecoveryArtifact artifact,
    required KeptMigrationJournal journal,
    required KeptMigrationSnapshot snapshot,
    required _RebuiltMigration rebuilt,
  }) {
    if (artifact.migrationId != journal.migrationId) {
      throw KeptMigrationException(
        '$stage-recovery-migration-id-mismatch',
        'The recovery artifact does not match the migration journal.',
      );
    }
    if (artifact.legacyEntryCount != snapshot.entries.length ||
        artifact.usableEntryCount != rebuilt.usableRecords.length) {
      throw KeptMigrationException(
        '$stage-recovery-count-mismatch',
        'The recovery artifact counts do not match the reconstructed '
            'migration data.',
      );
    }
    if (artifact.corruptEntries.length != rebuilt.recoveryEntries.length) {
      throw KeptMigrationException(
        '$stage-recovery-mismatch',
        'The recovery artifact does not match the expected corrupt '
            'entries.',
      );
    }
    for (var i = 0; i < rebuilt.recoveryEntries.length; i += 1) {
      if (artifact.corruptEntries[i] != rebuilt.recoveryEntries[i]) {
        throw KeptMigrationException(
          '$stage-recovery-mismatch',
          'The recovery artifact does not match the expected corrupt '
              'entries.',
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Shared helpers. None of these re-enter _coordinator.
  // ---------------------------------------------------------------------

  /// Independently decodes and converts every snapshot entry, deterministic
  /// given the same [snapshot] — used both when first migrating and when
  /// re-verifying from `verified`/`complete` states.
  _RebuiltMigration _rebuildFromSnapshot(KeptMigrationSnapshot snapshot) {
    final corruptEntries = <KeptMigrationRecoveryEntry>[];
    final idToIndices = <String, List<int>>{};
    final revealIdToIndices = <String, List<int>>{};
    final recordByIndex = <int, KeptRecord>{};

    for (final entry in snapshot.entries) {
      final decoded = _decodeFavoriteItem(entry.rawValue, entry.index);
      if (decoded == null) {
        corruptEntries.add(
          KeptMigrationRecoveryEntry(
            index: entry.index,
            rawValue: entry.rawValue,
            stage: KeptMigrationFailureStage.decode,
            reasonCode: 'favorite_decode_failed',
          ),
        );
        continue;
      }

      final KeptRecord record;
      try {
        record = _convertToKeptRecord(decoded);
      } catch (_) {
        corruptEntries.add(
          KeptMigrationRecoveryEntry(
            index: entry.index,
            rawValue: entry.rawValue,
            stage: KeptMigrationFailureStage.convert,
            reasonCode: 'kept_record_validation_failed',
          ),
        );
        continue;
      }

      recordByIndex[entry.index] = record;
      idToIndices.putIfAbsent(record.id, () => []).add(entry.index);
      revealIdToIndices.putIfAbsent(record.revealId, () => []).add(entry.index);
    }

    final duplicateReasonByIndex = <int, String>{};
    for (final indices in idToIndices.values) {
      if (indices.length > 1) {
        for (final i in indices) {
          duplicateReasonByIndex[i] = 'duplicate_record_id';
        }
      }
    }
    for (final indices in revealIdToIndices.values) {
      if (indices.length > 1) {
        for (final i in indices) {
          duplicateReasonByIndex.putIfAbsent(i, () => 'duplicate_reveal_id');
        }
      }
    }

    final duplicateEntries = <KeptMigrationRecoveryEntry>[
      for (final e in duplicateReasonByIndex.entries)
        KeptMigrationRecoveryEntry(
          index: e.key,
          rawValue: snapshot.entries[e.key].rawValue,
          stage: KeptMigrationFailureStage.duplicateIdentity,
          reasonCode: e.value,
        ),
    ];

    final usableRecords = <KeptRecord>[
      for (final entry in snapshot.entries)
        if (recordByIndex.containsKey(entry.index) &&
            !duplicateReasonByIndex.containsKey(entry.index))
          recordByIndex[entry.index]!,
    ];

    final allRecoveryEntries = <KeptMigrationRecoveryEntry>[
      ...corruptEntries,
      ...duplicateEntries,
    ]..sort((a, b) => a.index.compareTo(b.index));

    return _RebuiltMigration(
      usableRecords: usableRecords,
      recoveryEntries: allRecoveryEntries,
    );
  }

  /// Decodes one raw legacy entry using the exact same shared
  /// [StoredFavoriteEntryCodec] `SavedReflectionsService` itself uses —
  /// never a forked/reimplemented decoder, and never a migration-invented
  /// fallback identity. Entries missing an explicit id (current-schema
  /// entries with no `id` key, and every legacy pipe-format entry, which
  /// never carries one) get the exact same Build 25 fallback id
  /// (`legacy-v1-<index>-<stable hash of the raw entry>`), so the same
  /// entry always gets the same fallback id on every retry, and migration
  /// never diverges from what Build 25 itself would have assigned.
  FavoriteItem? _decodeFavoriteItem(String rawValue, int index) {
    return StoredFavoriteEntryCodec.decode(rawValue, index: index)?.item;
  }

  /// Deterministically converts a decoded [FavoriteItem] into a
  /// [KeptRecord]. May throw (date parsing, calendar-day contradiction, or
  /// [KeptRecord]'s own field validation) — callers treat that as a
  /// `convert`-stage corrupt entry.
  ///
  /// Phase 3D-D real-device hotfix: the previous version of this method
  /// unconditionally anchored `revealedAt`/`keptAt` at the display date's
  /// noon anchor and set `updatedAt` to `reflectedAt` only when it was
  /// *after* that anchor — silently leaving `keptAt` after a genuinely
  /// earlier same-day `reflectedAt` in every other case. Separately, a bare
  /// `DateTime.parse(item.reflectedAt!).toUtc()` reinterpreted Build 25's
  /// always-offset-free `reflectedAt` string through whichever timezone
  /// happened to be current on the migrating device, and never truncated
  /// the result to millisecond precision. That last part is what the
  /// confirmed real-device failure traces back to: a genuine
  /// sub-millisecond-precision `reflectedAt` (routine for any
  /// `DateTime.now()`-sourced value) survived into the in-memory migrated
  /// `KeptRecord`, but `KeptRecord.encode()` only serializes
  /// `millisecondsSinceEpoch` — so the protected store's own mandatory
  /// post-write read-back verification
  /// (`ProtectedFileKeptStateStore._replace`'s temp-file/final-file
  /// comparison) found the freshly-decoded record did not equal the
  /// in-memory one, threw `KeptStateStoreException('replace-verify-temp',
  /// ...)`, and the migration failed before ever placing the envelope file
  /// — exactly matching the reported evidence (the protected directory
  /// existed, its temp file had already been deleted by the store's own
  /// best-effort cleanup, no `east_kept_state_v3.json` existed, and the
  /// legacy `favorites` key was therefore never removed). See
  /// `test/kept_migration_coordinator_test.dart`'s
  /// "Phase 3D-D real-device migration hotfix" group for the exact
  /// reproduction.
  KeptRecord _convertToKeptRecord(FavoriteItem item) {
    // FavoriteItem.date is an opaque display string. The real production
    // writer (HomeScreen.toggleFavorite -> formattedToday()) produces an
    // English "MMMM d, yyyy" display value (e.g. "August 1, 2026"), which
    // bare DateTime.parse cannot read; FavoriteDateCodec handles both that
    // shape and existing ISO-8601 fixtures/data.
    final displayAnchor = FavoriteDateCodec.parseFavoriteDateToUtc(item.date);

    DateTime? reflectedAt;
    var reflectedOnDisplayDay = false;
    if (item.reflection != null && item.reflectedAt != null) {
      // Preserves the legacy value's own wall-clock/no-offset meaning
      // (never reinterpreted through the migrating device's current
      // timezone) and truncates to millisecond precision — see
      // FavoriteDateCodec.parseLegacyReflectedAtToUtc's doc comment.
      reflectedAt =
          FavoriteDateCodec.parseLegacyReflectedAtToUtc(item.reflectedAt!);

      reflectedOnDisplayDay = reflectedAt.year == displayAnchor.year &&
          reflectedAt.month == displayAnchor.month &&
          reflectedAt.day == displayAnchor.day;

      final reflectedCalendarDay =
          DateTime.utc(reflectedAt.year, reflectedAt.month, reflectedAt.day);
      final displayCalendarDay = DateTime.utc(
          displayAnchor.year, displayAnchor.month, displayAnchor.day);
      if (reflectedCalendarDay.isBefore(displayCalendarDay)) {
        // A genuine contradiction: the legacy reflectedAt's own calendar
        // day is *before* the legacy display date, i.e. the record claims
        // to have been reflected on before it was ever kept. Never
        // silently reinterpreted — a reflectedAt on the *same* day (common,
        // handled below) or on any *later* day (equally common — nothing
        // requires a Reflection to be added the same day it was kept) is
        // perfectly valid and never reaches this branch.
        // _rebuildFromSnapshot's existing per-entry try/catch classifies
        // this exactly like any other unresolvable legacy inconsistency —
        // an ordinary `convert`-stage corrupt entry, preserved byte-exact
        // in the recovery artifact.
        throw const FormatException(
          "Legacy reflectedAt's calendar day precedes the display date.",
        );
      }
    }

    // revealedAt/keptAt: the display date's noon anchor by default (the
    // deliberately day-boundary-safe placeholder — see
    // FavoriteDateCodec.parseFavoriteDateToUtc). A Reflection added on a
    // *later* calendar day is always safely after that anchor already, so
    // no adjustment is needed there. But a Kept wisdom can never be
    // reflected on before it was kept: when a genuine reflectedAt on the
    // *same* calendar day is earlier than the noon placeholder, keeping
    // keptAt at noon would put it after reflectedAt. Anchoring both
    // historical fields to the real, more precise reflectedAt instead is
    // strictly more truthful than the noon placeholder and keeps
    // revealedAt == keptAt <= reflectedAt in every case.
    var revealedAt = displayAnchor;
    var keptAt = displayAnchor;
    if (reflectedOnDisplayDay && reflectedAt!.isBefore(displayAnchor)) {
      revealedAt = reflectedAt;
      keptAt = reflectedAt;
    }

    // updatedAt tracks the real last known mutation — reflectedAt itself
    // when a Reflection exists, otherwise keptAt — and is never the
    // migration's own execution time (ADR-007, Legacy date mapping). This
    // can never be before keptAt: either no reflectedAt exists (equal to
    // keptAt), or keptAt has already been guaranteed <= reflectedAt above.
    final updatedAt = reflectedAt ?? keptAt;

    final revealId = _uuidV5Factory(
      'com.dogukan.dailywisdom/build25/reveal/${item.id}',
    );
    final mutationId = _uuidV5Factory(
      'com.dogukan.dailywisdom/build25/mutation/${item.id}',
    );

    return KeptRecord(
      id: item.id,
      revealId: revealId,
      wisdomText: item.text,
      revealedAt: revealedAt,
      keptAt: keptAt,
      reflectionText: item.reflection,
      reflectedAt: reflectedAt,
      updatedAt: updatedAt,
      mutationId: mutationId,
    );
  }

  /// Every named field [KeptRecord.operator==] itself compares (id,
  /// revealId, wisdomText, revealedAt, keptAt, reflectionText, reflectedAt,
  /// updatedAt, mutationId) — reusing that equality is the field-by-field
  /// verification, not a separate reimplementation of it.
  void _verifyFieldByField(
    KeptStateEnvelope actual,
    KeptStateEnvelope expected,
  ) {
    if (actual.activeRecords.length != expected.activeRecords.length) {
      throw const KeptMigrationException(
        'field-verify-count',
        'Migrated record count does not match the expected migration.',
      );
    }
    for (var i = 0; i < expected.activeRecords.length; i += 1) {
      if (actual.activeRecords[i] != expected.activeRecords[i]) {
        throw const KeptMigrationException(
          'field-verify-mismatch',
          'A migrated record does not match field-by-field.',
        );
      }
    }
  }

  String _snapshotFileName(String migrationId) =>
      'east_kept_migration_snapshot_v1-$migrationId.json';

  String _recoveryFileName(String migrationId) =>
      'east_kept_migration_recovery_v1-$migrationId.json';

  Future<T> _wrap<T>(String stage, Future<T> Function() action) async {
    try {
      return await action();
    } on KeptMigrationException {
      rethrow;
    } catch (error) {
      throw KeptMigrationException(
        stage,
        'Migration failed at stage: $stage.',
        error,
      );
    }
  }
}
