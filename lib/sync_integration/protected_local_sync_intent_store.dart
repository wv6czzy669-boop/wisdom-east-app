/// Build 26 Phase 4E-1: protected, atomic, file-backed [LocalSyncIntentStore]
/// implementation.
///
/// Mirrors `lib/persistence/protected_file_kept_state_store.dart` and
/// `lib/sync_persistence/protected_sync_persistence_store.dart` step for
/// step: a temporary file is written, protected, and read back to verify it
/// byte-for-byte; any existing final file is backed up and verified; the
/// temporary file is then atomically renamed into place; the final file is
/// protected and read back to verify it; and on any failure after the
/// rename, the backed-up prior final file is restored and re-verified
/// before the original failure is surfaced. A first-ever write that fails
/// before its rename step leaves no final file behind at all. Uses a
/// dedicated directory (`east_sync_integration_state`) and file
/// (`east_sync_intents_v1.json`), entirely separate from both
/// `east_kept_state` and `east_sync_state`.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../persistence/file_protection_bridge.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/protected_file_recovery.dart';
import '../persistence/protected_file_rollback.dart';
import '../utils/kept_diagnostics.dart';
import 'local_sync_intent.dart';
import 'local_sync_intent_envelope.dart';
import 'local_sync_intent_store.dart';

/// Bundles an original failure with a subsequent rollback failure, for
/// diagnostic purposes only -- never inspected structurally by callers.
class _CombinedFailure {
  const _CombinedFailure(this.original, this.rollback);

  final Object original;
  final Object rollback;

  @override
  String toString() =>
      'original failure: $original; rollback failure: $rollback';
}

final class ProtectedLocalSyncIntentStore implements LocalSyncIntentStore {
  ProtectedLocalSyncIntentStore({
    Future<Directory> Function()? rootDirectoryProvider,
    FileProtectionBridge? fileProtectionBridge,
    String Function()? tokenFactory,
    DateTime Function()? clock,
    PersistenceOperationCoordinator? operationCoordinator,
  })  : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationSupportDirectory,
        _fileProtectionBridge =
            fileProtectionBridge ?? const MethodChannelFileProtectionBridge(),
        _tokenFactory = tokenFactory ?? (() => const Uuid().v4()),
        _clock = clock ?? DateTime.now,
        _coordinator =
            operationCoordinator ?? PersistenceOperationCoordinator();

  static const String resourceKey = 'protected_sync_integration_state_file';
  static const String _directoryName = 'east_sync_integration_state';
  static const String _baseName = 'east_sync_intents_v1';

  final Future<Directory> Function() _rootDirectoryProvider;
  final FileProtectionBridge _fileProtectionBridge;
  final String Function() _tokenFactory;
  final DateTime Function() _clock;
  final PersistenceOperationCoordinator _coordinator;

  // -----------------------------------------------------------------------
  // Public LocalSyncIntentStore API -- every method runs fully inside the
  // coordinator's exclusive slot for [resourceKey], so a load can never
  // observe a half-completed replace and two mutations can never interleave.
  // -----------------------------------------------------------------------

  @override
  Future<List<LocalSyncIntent>> loadIntents() {
    return _coordinator.runExclusive<List<LocalSyncIntent>>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        return List.unmodifiable(envelope.intents);
      },
    );
  }

  @override
  Future<void> enqueueIntent(LocalSyncIntent intent) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        final recordName = intent.recordName;

        for (final existing in envelope.intents) {
          if (existing.intentId == intent.intentId) {
            if (existing.kind == intent.kind &&
                existing.payload == intent.payload) {
              keptDiagnostic(
                'sync-integration-intent-store: enqueue-idempotent-noop',
              );
              return;
            }
            throw const ConflictingLocalSyncIntentIdentityException();
          }
        }

        final existingIndex = envelope.intents
            .indexWhere((entry) => entry.recordName == recordName);
        final nextIntents = List<LocalSyncIntent>.of(envelope.intents);
        if (existingIndex == -1) {
          nextIntents.add(intent);
        } else {
          keptDiagnostic(
            'sync-integration-intent-store: enqueue-supersedes-pending-intent',
          );
          nextIntents[existingIndex] = intent;
        }

        await _replaceEnvelope(envelope.copyWith(intents: nextIntents));
      },
    );
  }

  @override
  Future<void> advanceIntentStage({
    required String intentId,
    required LocalSyncIntentStage expectedStage,
    required LocalSyncIntentStage nextStage,
  }) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        final index =
            envelope.intents.indexWhere((entry) => entry.intentId == intentId);
        if (index == -1) return;

        final existing = envelope.intents[index];
        if (existing.stage != expectedStage) {
          throw const LocalSyncIntentStageMismatchException();
        }
        if (existing.stage == nextStage) return;

        final nextIntents = List<LocalSyncIntent>.of(envelope.intents);
        nextIntents[index] = existing.copyWith(stage: nextStage);
        await _replaceEnvelope(envelope.copyWith(intents: nextIntents));
      },
    );
  }

  @override
  Future<void> removeIntent(String intentId) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        final nextIntents = envelope.intents
            .where((entry) => entry.intentId != intentId)
            .toList();
        if (nextIntents.length == envelope.intents.length) return;
        await _replaceEnvelope(envelope.copyWith(intents: nextIntents));
      },
    );
  }

  // -----------------------------------------------------------------------
  // Load -- mirrors ProtectedFileKeptStateStore._load exactly in shape.
  // -----------------------------------------------------------------------

  Future<LocalSyncIntentEnvelope> _loadEnvelope() async {
    final dirPath = await _resolveAndProtectDirectory();
    final finalPath = _finalPath(dirPath);
    final finalFile = File(finalPath);

    if (!await finalFile.exists()) {
      final recovered = await _recoverFromBackupIfFinalAbsent(dirPath);
      return recovered ?? LocalSyncIntentEnvelope.empty();
    }

    final String raw;
    try {
      raw = await finalFile.readAsString();
    } catch (error) {
      throw LocalSyncIntentStoreException(
        'load-read',
        'Could not read the authoritative sync-intent file.',
        error,
      );
    }

    final LocalSyncIntentEnvelope envelope;
    try {
      envelope = LocalSyncIntentEnvelope.decodeString(raw);
    } catch (decodeError) {
      try {
        await _preserveCorrupt(dirPath, raw);
      } catch (preserveError) {
        throw LocalSyncIntentStoreException(
          'load-decode',
          'The authoritative sync-intent file is corrupt, and preserving '
              'it also failed.',
          preserveError,
        );
      }
      throw LocalSyncIntentStoreException(
        'load-decode',
        'The authoritative sync-intent file is corrupt; it has been '
            'preserved separately.',
        decodeError,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(finalPath);
    } catch (error) {
      throw LocalSyncIntentStoreException(
        'load-protect',
        'Could not verify protection of the authoritative sync-intent file '
            'after reading it.',
        error,
      );
    }
    await _cleanupStaleTransactionFilesBestEffort(dirPath);

    return envelope;
  }

  Future<LocalSyncIntentEnvelope?> _recoverFromBackupIfFinalAbsent(
    String dirPath,
  ) async {
    try {
      final recovered = await recoverProtectedBackup<LocalSyncIntentEnvelope>(
        directoryPath: dirPath,
        backupFilePrefix: '.$_baseName.backup-',
        finalFile: File(_finalPath(dirPath)),
        fileDescription: 'sync-intent',
        recoveryPathForToken: (token) => _recoveryTempPath(dirPath, token),
        tokenFactory: _tokenFactory,
        decode: LocalSyncIntentEnvelope.decodeString,
        fileProtectionBridge: _fileProtectionBridge,
      );
      if (recovered != null) {
        await _cleanupStaleTransactionFilesBestEffort(dirPath);
      }
      return recovered;
    } on ProtectedFileRecoveryException catch (error) {
      throw LocalSyncIntentStoreException(
        error.stage,
        error.message,
        error.cause ?? error,
      );
    }
  }

  Future<void> _preserveCorrupt(String dirPath, String rawBytes) async {
    final token = _tokenFactory();
    final utcMs = _clock().toUtc().millisecondsSinceEpoch;
    final corruptPath = _corruptPath(dirPath, utcMs, token);

    final file = File(corruptPath);
    final raf = await file.open(mode: FileMode.write);
    try {
      await raf.writeString(rawBytes);
      await raf.flush();
    } finally {
      await raf.close();
    }

    await _fileProtectionBridge.protectAndVerifyComplete(corruptPath);
  }

  Future<void> _cleanupStaleTransactionFilesBestEffort(String dirPath) async {
    try {
      final tempFiles = await _listFilesWithPrefix(dirPath, '.$_baseName.tmp-');
      final recoveryTempFiles =
          await _listFilesWithPrefix(dirPath, '.$_baseName.recover-');
      final backupFiles =
          await _listFilesWithPrefix(dirPath, '.$_baseName.backup-');
      for (final file in [...tempFiles, ...recoveryTempFiles, ...backupFiles]) {
        await _deleteBestEffort(file);
      }
    } catch (_) {
      // Best-effort only.
    }
  }

  // -----------------------------------------------------------------------
  // Replace -- mirrors ProtectedFileKeptStateStore._replace exactly in
  // shape (temp write -> protect+verify temp -> backup existing final ->
  // atomic rename -> protect+verify final -> rollback on any post-rename
  // failure).
  // -----------------------------------------------------------------------

  Future<void> _replaceEnvelope(LocalSyncIntentEnvelope envelope) async {
    final dirPath = await _resolveAndProtectDirectory();
    final finalPath = _finalPath(dirPath);
    final finalFile = File(finalPath);

    final encoded = envelope.encodeString();
    final token = _tokenFactory();
    final tempPath = _tempPath(dirPath, token);
    final tempFile = File(tempPath);

    try {
      final raf = await tempFile.open(mode: FileMode.write);
      try {
        await raf.writeString(encoded);
        await raf.flush();
      } finally {
        await raf.close();
      }
    } catch (error) {
      await _deleteBestEffort(tempFile);
      throw LocalSyncIntentStoreException(
        'replace-write-temp',
        'Could not write the temporary sync-intent file.',
        error,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(tempPath);
    } catch (error) {
      await _deleteBestEffort(tempFile);
      throw LocalSyncIntentStoreException(
        'replace-protect-temp',
        'Could not protect the temporary sync-intent file.',
        error,
      );
    }

    try {
      final rawTemp = await tempFile.readAsString();
      final decodedTemp = LocalSyncIntentEnvelope.decodeString(rawTemp);
      if (decodedTemp != envelope) {
        throw const LocalSyncIntentStoreException(
          'replace-verify-temp',
          'Temporary sync-intent file did not match the intended envelope.',
        );
      }
    } catch (error) {
      await _deleteBestEffort(tempFile);
      if (error is LocalSyncIntentStoreException) rethrow;
      throw LocalSyncIntentStoreException(
        'replace-verify-temp',
        'Could not verify the temporary sync-intent file.',
        error,
      );
    }

    final hadExistingFinal = await finalFile.exists();
    String? backupPath;
    LocalSyncIntentEnvelope? previousEnvelope;

    if (hadExistingFinal) {
      backupPath = _backupPath(dirPath, token);
      final backupFile = File(backupPath);
      try {
        final existingBytes = await finalFile.readAsString();
        final raf = await backupFile.open(mode: FileMode.write);
        try {
          await raf.writeString(existingBytes);
          await raf.flush();
        } finally {
          await raf.close();
        }
        await _fileProtectionBridge.protectAndVerifyComplete(backupPath);
        final rawBackup = await backupFile.readAsString();
        previousEnvelope = LocalSyncIntentEnvelope.decodeString(rawBackup);
      } catch (error) {
        await _deleteBestEffort(tempFile);
        await _deleteBestEffort(File(backupPath));
        throw LocalSyncIntentStoreException(
          'replace-backup',
          'Could not create a verified backup of the existing sync-intent '
              'file.',
          error,
        );
      }
    }

    try {
      await tempFile.rename(finalPath);
    } catch (error) {
      await _deleteBestEffort(tempFile);
      if (backupPath != null) await _deleteBestEffort(File(backupPath));
      throw LocalSyncIntentStoreException(
        'replace-rename',
        'Could not atomically replace the authoritative sync-intent file.',
        error,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(finalPath);
      final rawFinal = await finalFile.readAsString();
      final decodedFinal = LocalSyncIntentEnvelope.decodeString(rawFinal);
      if (decodedFinal != envelope) {
        throw const LocalSyncIntentStoreException(
          'replace-verify-final',
          'Final sync-intent file did not match the intended envelope after '
              'replacement.',
        );
      }
    } catch (error) {
      await _rollbackAfterRename(
        finalFile: finalFile,
        backupPath: backupPath,
        previousEnvelope: previousEnvelope,
        originalError: error,
      );
    }

    if (backupPath != null) {
      await _deleteBestEffort(File(backupPath));
    }
  }

  Future<void> _rollbackAfterRename({
    required File finalFile,
    required String? backupPath,
    required LocalSyncIntentEnvelope? previousEnvelope,
    required Object originalError,
  }) async {
    if (backupPath == null) {
      await _deleteBestEffort(finalFile);
      throw LocalSyncIntentStoreException(
        'replace-post-rename',
        'Sync-intent replacement failed after rename; no prior state '
            'existed to restore.',
        originalError,
      );
    }

    final backupFile = File(backupPath);
    try {
      final expectedEnvelope = previousEnvelope;
      if (expectedEnvelope == null) {
        throw const LocalSyncIntentStoreException(
          'replace-rollback-verify',
          'The verified prior sync-intent envelope was unavailable.',
        );
      }
      await restoreProtectedBackup<LocalSyncIntentEnvelope>(
        backupFile: backupFile,
        finalFile: finalFile,
        recoveryFile: File(
          _recoveryTempPath(finalFile.parent.path, _tokenFactory()),
        ),
        expectedValue: expectedEnvelope,
        decode: LocalSyncIntentEnvelope.decodeString,
        fileProtectionBridge: _fileProtectionBridge,
      );
    } catch (rollbackError) {
      throw LocalSyncIntentStoreException(
        'replace-rollback',
        'Sync-intent replacement failed and rollback also failed; a backup '
            'may remain for later recovery.',
        _CombinedFailure(originalError, rollbackError),
      );
    }

    throw LocalSyncIntentStoreException(
      'replace-post-rename',
      'Sync-intent replacement failed after rename; the prior sync-intent '
          'file was restored.',
      originalError,
    );
  }

  // -----------------------------------------------------------------------
  // Shared path/file helpers -- none of these touch the coordinator; only
  // the public API methods above do.
  // -----------------------------------------------------------------------

  Future<String> _resolveAndProtectDirectory() async {
    final Directory root;
    try {
      root = await _rootDirectoryProvider();
    } catch (error) {
      throw LocalSyncIntentStoreException(
        'directory-resolve',
        'Could not resolve the application support directory.',
        error,
      );
    }

    final dirPath = '${root.path}/$_directoryName';
    final dir = Directory(dirPath);
    try {
      await dir.create(recursive: true);
    } catch (error) {
      throw LocalSyncIntentStoreException(
        'directory-create',
        'Could not create the protected sync-integration directory.',
        error,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(dirPath);
    } catch (error) {
      throw LocalSyncIntentStoreException(
        'directory-protect',
        'Could not protect the sync-integration directory.',
        error,
      );
    }

    return dirPath;
  }

  String _finalPath(String dirPath) => '$dirPath/$_baseName.json';

  String _tempPath(String dirPath, String token) =>
      '$dirPath/.$_baseName.tmp-$token.json';

  String _recoveryTempPath(String dirPath, String token) =>
      '$dirPath/.$_baseName.recover-$token.json';

  String _backupPath(String dirPath, String token) =>
      '$dirPath/.$_baseName.backup-$token.json';

  String _corruptPath(String dirPath, int utcMs, String token) =>
      '$dirPath/$_baseName.corrupt-$utcMs-$token.json';

  String _fileName(String path) => path.split('/').last;

  Future<List<File>> _listFilesWithPrefix(
    String dirPath,
    String prefix,
  ) async {
    final dir = Directory(dirPath);
    final entries = await dir.list().toList();
    return entries
        .whereType<File>()
        .where((file) => _fileName(file.path).startsWith(prefix))
        .toList();
  }

  Future<void> _deleteBestEffort(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort only.
    }
  }
}
