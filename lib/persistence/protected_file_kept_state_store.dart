import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/kept_state_envelope.dart';
import 'file_protection_bridge.dart';
import 'kept_state_store.dart';
import 'persistence_operation_coordinator.dart';

/// Thrown by [ProtectedFileKeptStateStore] on any failure to load or
/// replace the protected envelope.
///
/// Kept intentionally narrow to this store's own concerns — this is not a
/// broad, app-wide error hierarchy. [stage] identifies which step of the
/// load/replace algorithm failed (for example `'replace-verify-final'`),
/// which is safe diagnostic metadata; [message] and [toString] never
/// include envelope JSON, wisdom text, or reflection content.
class KeptStateStoreException implements Exception {
  const KeptStateStoreException(this.stage, this.message, [this.cause]);

  final String stage;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    if (cause == null) return 'KeptStateStoreException[$stage]: $message';
    return 'KeptStateStoreException[$stage]: $message ($cause)';
  }
}

/// Bundles an original failure with a subsequent rollback failure, for
/// diagnostic purposes only — never inspected structurally by callers.
class _CombinedFailure {
  const _CombinedFailure(this.original, this.rollback);

  final Object original;
  final Object rollback;

  @override
  String toString() =>
      'original failure: $original; rollback failure: $rollback';
}

/// Protected, atomic, file-backed [KeptStateStore] implementation.
///
/// Stores the complete authoritative [KeptStateEnvelope] as one JSON file,
/// `east_kept_state_v3.json`, inside an `east_kept_state` directory beneath
/// the platform's Application Support directory. Every write goes through
/// a temporary file, is protected and read back for verification, and is
/// only then atomically renamed into place — the previous valid file is
/// backed up first and restored if anything fails after the rename.
///
/// All [load]/[replace] operations on one instance are serialized through
/// [PersistenceOperationCoordinator] under one resource key, so a `load`
/// can never observe a half-completed `replace`, and concurrent `replace`
/// calls can never interleave.
final class ProtectedFileKeptStateStore implements KeptStateStore {
  ProtectedFileKeptStateStore({
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

  static const String resourceKey = 'protected_kept_state_file';
  static const String _directoryName = 'east_kept_state';
  static const String _baseName = 'east_kept_state_v3';

  final Future<Directory> Function() _rootDirectoryProvider;
  final FileProtectionBridge _fileProtectionBridge;
  final String Function() _tokenFactory;
  final DateTime Function() _clock;
  final PersistenceOperationCoordinator _coordinator;

  @override
  Future<KeptStateEnvelope?> load() {
    return _coordinator.runExclusive<KeptStateEnvelope?>(
      resourceKey: resourceKey,
      operation: _load,
    );
  }

  @override
  Future<void> replace(KeptStateEnvelope envelope) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () => _replace(envelope),
    );
  }

  // ---------------------------------------------------------------------
  // Load
  // ---------------------------------------------------------------------

  Future<KeptStateEnvelope?> _load() async {
    final dirPath = await _resolveAndProtectDirectory();
    final finalPath = _finalPath(dirPath);
    final finalFile = File(finalPath);

    if (!await finalFile.exists()) {
      return _recoverFromBackupIfFinalAbsent(dirPath);
    }

    final String raw;
    try {
      raw = await finalFile.readAsString();
    } catch (error) {
      throw KeptStateStoreException(
        'load-read',
        'Could not read the authoritative kept-state file.',
        error,
      );
    }

    final KeptStateEnvelope envelope;
    try {
      envelope = KeptStateEnvelope.decodeString(raw);
    } catch (decodeError) {
      try {
        await _preserveCorrupt(dirPath, raw);
      } catch (preserveError) {
        throw KeptStateStoreException(
          'load-decode',
          'The authoritative kept-state file is corrupt, and preserving '
              'it also failed.',
          preserveError,
        );
      }
      throw KeptStateStoreException(
        'load-decode',
        'The authoritative kept-state file is corrupt; it has been '
            'preserved separately.',
        decodeError,
      );
    }

    await _fileProtectionBridge.protectAndVerifyComplete(finalPath);
    await _cleanupStaleTransactionFilesBestEffort(dirPath);

    return envelope;
  }

  Future<KeptStateEnvelope?> _recoverFromBackupIfFinalAbsent(
    String dirPath,
  ) async {
    final backups = await _listFilesWithPrefix(dirPath, '.$_baseName.backup-');
    if (backups.isEmpty) return null;

    final withModifiedTime = <MapEntry<File, DateTime>>[];
    for (final file in backups) {
      try {
        final stat = await file.stat();
        withModifiedTime.add(MapEntry(file, stat.modified));
      } catch (_) {
        // Unreadable stat: treat as unusable, skip.
      }
    }
    withModifiedTime.sort((a, b) => b.value.compareTo(a.value));

    for (final entry in withModifiedTime) {
      final backupFile = entry.key;

      final String raw;
      try {
        raw = await backupFile.readAsString();
      } catch (_) {
        continue;
      }

      final KeptStateEnvelope envelope;
      try {
        envelope = KeptStateEnvelope.decodeString(raw);
      } catch (_) {
        continue;
      }

      final finalPath = _finalPath(dirPath);
      try {
        await backupFile.rename(finalPath);
      } catch (error) {
        throw KeptStateStoreException(
          'load-recover-rename',
          'Could not restore a valid backup to the authoritative path.',
          error,
        );
      }

      await _fileProtectionBridge.protectAndVerifyComplete(finalPath);
      await _cleanupStaleTransactionFilesBestEffort(dirPath);

      return envelope;
    }

    return null;
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
      final backupFiles =
          await _listFilesWithPrefix(dirPath, '.$_baseName.backup-');
      for (final file in [...tempFiles, ...backupFiles]) {
        await _deleteBestEffort(file);
      }
    } catch (_) {
      // Best-effort only — never let cleanup failure fail an otherwise
      // successful load.
    }
  }

  // ---------------------------------------------------------------------
  // Replace
  // ---------------------------------------------------------------------

  Future<void> _replace(KeptStateEnvelope envelope) async {
    final dirPath = await _resolveAndProtectDirectory();
    final finalPath = _finalPath(dirPath);
    final finalFile = File(finalPath);

    final encoded = envelope.encodeString();
    final token = _tokenFactory();
    final tempPath = _tempPath(dirPath, token);
    final tempFile = File(tempPath);

    // Steps 4-8: write, flush, close the temporary file.
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
      throw KeptStateStoreException(
        'replace-write-temp',
        'Could not write the temporary kept-state file.',
        error,
      );
    }

    // Step 9: protect and verify the temporary file.
    try {
      await _fileProtectionBridge.protectAndVerifyComplete(tempPath);
    } catch (error) {
      await _deleteBestEffort(tempFile);
      throw KeptStateStoreException(
        'replace-protect-temp',
        'Could not protect the temporary kept-state file.',
        error,
      );
    }

    // Steps 10-11: reopen, decode, and compare the temporary file by value.
    try {
      final rawTemp = await tempFile.readAsString();
      final decodedTemp = KeptStateEnvelope.decodeString(rawTemp);
      if (decodedTemp != envelope) {
        throw const KeptStateStoreException(
          'replace-verify-temp',
          'Temporary kept-state file did not match the intended envelope.',
        );
      }
    } catch (error) {
      await _deleteBestEffort(tempFile);
      if (error is KeptStateStoreException) rethrow;
      throw KeptStateStoreException(
        'replace-verify-temp',
        'Could not verify the temporary kept-state file.',
        error,
      );
    }

    // Step 12: back up an existing authoritative final, if one exists.
    final hadExistingFinal = await finalFile.exists();
    String? backupPath;
    KeptStateEnvelope? previousEnvelope;

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
        previousEnvelope = KeptStateEnvelope.decodeString(rawBackup);
      } catch (error) {
        await _deleteBestEffort(tempFile);
        await _deleteBestEffort(File(backupPath));
        throw KeptStateStoreException(
          'replace-backup',
          'Could not create a verified backup of the existing kept-state '
              'file.',
          error,
        );
      }
    }

    // Step 13: atomically rename the verified temp file into place.
    try {
      await tempFile.rename(finalPath);
    } catch (error) {
      await _deleteBestEffort(tempFile);
      if (backupPath != null) await _deleteBestEffort(File(backupPath));
      throw KeptStateStoreException(
        'replace-rename',
        'Could not atomically replace the authoritative kept-state file.',
        error,
      );
    }

    // Steps 14-16: protect/verify and reopen/decode/compare the final file.
    try {
      await _fileProtectionBridge.protectAndVerifyComplete(finalPath);
      final rawFinal = await finalFile.readAsString();
      final decodedFinal = KeptStateEnvelope.decodeString(rawFinal);
      if (decodedFinal != envelope) {
        throw const KeptStateStoreException(
          'replace-verify-final',
          'Final kept-state file did not match the intended envelope '
              'after replacement.',
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

    // Step 17: success — clean up the backup; nothing remains at tempPath
    // since it was renamed away.
    if (backupPath != null) {
      await _deleteBestEffort(File(backupPath));
    }
  }

  /// Always throws: either the original failure (after a successful
  /// rollback) or a [KeptStateStoreException] describing both the original
  /// failure and a rollback failure.
  Future<void> _rollbackAfterRename({
    required File finalFile,
    required String? backupPath,
    required KeptStateEnvelope? previousEnvelope,
    required Object originalError,
  }) async {
    if (backupPath == null) {
      // No prior authoritative file existed before this replace attempt —
      // there is nothing valid to restore. Remove the failed/new final so
      // no corrupt or unverified file is left claiming to be authoritative.
      await _deleteBestEffort(finalFile);
      throw KeptStateStoreException(
        'replace-post-rename',
        'Kept-state replacement failed after rename; no prior state '
            'existed to restore.',
        originalError,
      );
    }

    final backupFile = File(backupPath);
    try {
      await _deleteBestEffort(finalFile);
      await backupFile.rename(finalFile.path);
      await _fileProtectionBridge.protectAndVerifyComplete(finalFile.path);
      final rawRestored = await finalFile.readAsString();
      final restoredEnvelope = KeptStateEnvelope.decodeString(rawRestored);
      if (restoredEnvelope != previousEnvelope) {
        throw const KeptStateStoreException(
          'replace-rollback-verify',
          'Restored kept-state file did not match the prior envelope.',
        );
      }
    } catch (rollbackError) {
      throw KeptStateStoreException(
        'replace-rollback',
        'Kept-state replacement failed and rollback also failed; a backup '
            'may remain for later recovery.',
        _CombinedFailure(originalError, rollbackError),
      );
    }

    throw KeptStateStoreException(
      'replace-post-rename',
      'Kept-state replacement failed after rename; the prior kept-state '
          'file was restored.',
      originalError,
    );
  }

  // ---------------------------------------------------------------------
  // Shared path/file helpers. None of these touch the coordinator — only
  // the public load()/replace() entry points above do.
  // ---------------------------------------------------------------------

  Future<String> _resolveAndProtectDirectory() async {
    final Directory root;
    try {
      root = await _rootDirectoryProvider();
    } catch (error) {
      throw KeptStateStoreException(
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
      throw KeptStateStoreException(
        'directory-create',
        'Could not create the protected kept-state directory.',
        error,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(dirPath);
    } catch (error) {
      throw KeptStateStoreException(
        'directory-protect',
        'Could not protect the kept-state directory.',
        error,
      );
    }

    return dirPath;
  }

  String _finalPath(String dirPath) => '$dirPath/$_baseName.json';

  String _tempPath(String dirPath, String token) =>
      '$dirPath/.$_baseName.tmp-$token.json';

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
