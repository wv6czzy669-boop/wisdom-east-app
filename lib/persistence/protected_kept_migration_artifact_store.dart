import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/kept_migration_recovery_artifact.dart';
import '../models/kept_migration_snapshot.dart';
import 'file_protection_bridge.dart';
import 'kept_migration_artifact_store.dart';
import 'persistence_operation_coordinator.dart';

/// Thrown by [ProtectedKeptMigrationArtifactStore] on any failure to write,
/// read, protect, or verify a migration artifact.
class KeptMigrationArtifactStoreException implements Exception {
  const KeptMigrationArtifactStoreException(
    this.stage,
    this.message, [
    this.cause,
  ]);

  final String stage;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    if (cause == null) {
      return 'KeptMigrationArtifactStoreException[$stage]: $message';
    }
    return 'KeptMigrationArtifactStoreException[$stage]: $message ($cause)';
  }
}

/// Protected, write-once file store for migration snapshots and recovery
/// artifacts, sharing the same protected `east_kept_state` Application
/// Support directory Phase 3B's [ProtectedFileKeptStateStore] uses.
///
/// Both artifact kinds are immutable once written: if a final artifact
/// file already exists, it is loaded and compared by value against the
/// intended content — an exact match is treated as an idempotent success,
/// a mismatch is a blocking error, and the existing file is never
/// overwritten. Neither kind is ever deleted by this store.
final class ProtectedKeptMigrationArtifactStore
    implements KeptMigrationArtifactStore {
  ProtectedKeptMigrationArtifactStore({
    Future<Directory> Function()? rootDirectoryProvider,
    FileProtectionBridge? fileProtectionBridge,
    String Function()? tokenFactory,
    PersistenceOperationCoordinator? operationCoordinator,
  })  : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationSupportDirectory,
        _fileProtectionBridge =
            fileProtectionBridge ?? const MethodChannelFileProtectionBridge(),
        _tokenFactory = tokenFactory ?? (() => const Uuid().v4()),
        _coordinator =
            operationCoordinator ?? PersistenceOperationCoordinator();

  static const String resourceKey = 'kept_migration_artifact_file';
  static const String _directoryName = 'east_kept_state';

  final Future<Directory> Function() _rootDirectoryProvider;
  final FileProtectionBridge _fileProtectionBridge;
  final String Function() _tokenFactory;
  final PersistenceOperationCoordinator _coordinator;

  @override
  Future<KeptMigrationSnapshot?> loadSnapshot(String fileName) {
    return _coordinator.runExclusive<KeptMigrationSnapshot?>(
      resourceKey: resourceKey,
      operation: () => _loadArtifact<KeptMigrationSnapshot>(
        fileName: fileName,
        decode: KeptMigrationSnapshot.decodeString,
      ),
    );
  }

  @override
  Future<void> writeSnapshot(
    String fileName,
    KeptMigrationSnapshot snapshot,
  ) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () => _writeArtifact<KeptMigrationSnapshot>(
        fileName: fileName,
        artifact: snapshot,
        encode: (value) => value.encodeString(),
        decode: KeptMigrationSnapshot.decodeString,
      ),
    );
  }

  @override
  Future<KeptMigrationRecoveryArtifact?> loadRecoveryArtifact(
    String fileName,
  ) {
    return _coordinator.runExclusive<KeptMigrationRecoveryArtifact?>(
      resourceKey: resourceKey,
      operation: () => _loadArtifact<KeptMigrationRecoveryArtifact>(
        fileName: fileName,
        decode: KeptMigrationRecoveryArtifact.decodeString,
      ),
    );
  }

  @override
  Future<void> writeRecoveryArtifact(
    String fileName,
    KeptMigrationRecoveryArtifact artifact,
  ) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () => _writeArtifact<KeptMigrationRecoveryArtifact>(
        fileName: fileName,
        artifact: artifact,
        encode: (value) => value.encodeString(),
        decode: KeptMigrationRecoveryArtifact.decodeString,
      ),
    );
  }

  Future<T?> _loadArtifact<T>({
    required String fileName,
    required T Function(String) decode,
  }) async {
    final dirPath = await _resolveAndProtectDirectory();
    final finalPath = '$dirPath/$fileName';
    final finalFile = File(finalPath);

    if (!await finalFile.exists()) return null;

    final String raw;
    try {
      raw = await finalFile.readAsString();
    } catch (error) {
      throw KeptMigrationArtifactStoreException(
        'load-read',
        'Could not read the stored artifact.',
        error,
      );
    }

    final T decoded;
    try {
      decoded = decode(raw);
    } catch (error) {
      throw KeptMigrationArtifactStoreException(
        'load-decode',
        'The stored artifact is corrupt.',
        error,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(finalPath);
    } catch (error) {
      throw KeptMigrationArtifactStoreException(
        'load-protect',
        'Could not protect the stored artifact.',
        error,
      );
    }

    return decoded;
  }

  Future<void> _writeArtifact<T>({
    required String fileName,
    required T artifact,
    required String Function(T) encode,
    required T Function(String) decode,
  }) async {
    final dirPath = await _resolveAndProtectDirectory();
    final finalPath = '$dirPath/$fileName';
    final finalFile = File(finalPath);

    if (await finalFile.exists()) {
      final String existingRaw;
      try {
        existingRaw = await finalFile.readAsString();
      } catch (error) {
        throw KeptMigrationArtifactStoreException(
          'write-existing-read',
          'Could not read an existing artifact file.',
          error,
        );
      }

      final T existing;
      try {
        existing = decode(existingRaw);
      } catch (error) {
        throw KeptMigrationArtifactStoreException(
          'write-existing-decode',
          'An existing artifact file is corrupt.',
          error,
        );
      }

      if (existing != artifact) {
        throw const KeptMigrationArtifactStoreException(
          'write-existing-mismatch',
          'An existing artifact does not match the intended content; '
              'refusing to overwrite.',
        );
      }

      // Already present and identical: idempotent success. Still
      // protect+verify, since a retry should never leave this unprotected.
      try {
        await _fileProtectionBridge.protectAndVerifyComplete(finalPath);
      } catch (error) {
        throw KeptMigrationArtifactStoreException(
          'write-existing-protect',
          'Could not protect an existing artifact file.',
          error,
        );
      }
      return;
    }

    final encoded = encode(artifact);
    final token = _tokenFactory();
    final tempPath = '$dirPath/.$fileName.tmp-$token';
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
      throw KeptMigrationArtifactStoreException(
        'write-temp',
        'Could not write the temporary artifact file.',
        error,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(tempPath);
    } catch (error) {
      await _deleteBestEffort(tempFile);
      throw KeptMigrationArtifactStoreException(
        'write-protect-temp',
        'Could not protect the temporary artifact file.',
        error,
      );
    }

    try {
      final rawTemp = await tempFile.readAsString();
      final decodedTemp = decode(rawTemp);
      if (decodedTemp != artifact) {
        throw const KeptMigrationArtifactStoreException(
          'write-verify-temp',
          'Temporary artifact file did not match the intended content.',
        );
      }
    } catch (error) {
      await _deleteBestEffort(tempFile);
      if (error is KeptMigrationArtifactStoreException) rethrow;
      throw KeptMigrationArtifactStoreException(
        'write-verify-temp',
        'Could not verify the temporary artifact file.',
        error,
      );
    }

    try {
      await tempFile.rename(finalPath);
    } catch (error) {
      await _deleteBestEffort(tempFile);
      throw KeptMigrationArtifactStoreException(
        'write-rename',
        'Could not place the artifact file at its final path.',
        error,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(finalPath);
      final rawFinal = await finalFile.readAsString();
      final decodedFinal = decode(rawFinal);
      if (decodedFinal != artifact) {
        throw const KeptMigrationArtifactStoreException(
          'write-verify-final',
          'Final artifact file did not match the intended content after '
              'writing.',
        );
      }
    } catch (error) {
      // This artifact is brand-new (there was no pre-existing final file),
      // so on failure we remove the just-written final rather than leave
      // an unverified file claiming to be authoritative.
      await _deleteBestEffort(finalFile);
      if (error is KeptMigrationArtifactStoreException) rethrow;
      throw KeptMigrationArtifactStoreException(
        'write-verify-final',
        'Could not verify the final artifact file after writing.',
        error,
      );
    }
  }

  Future<String> _resolveAndProtectDirectory() async {
    final Directory root;
    try {
      root = await _rootDirectoryProvider();
    } catch (error) {
      throw KeptMigrationArtifactStoreException(
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
      throw KeptMigrationArtifactStoreException(
        'directory-create',
        'Could not create the protected migration artifact directory.',
        error,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(dirPath);
    } catch (error) {
      throw KeptMigrationArtifactStoreException(
        'directory-protect',
        'Could not protect the migration artifact directory.',
        error,
      );
    }

    return dirPath;
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
