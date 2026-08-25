import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'file_protection_bridge.dart';
import 'persistence_operation_coordinator.dart';
import 'protected_file_recovery.dart';
import 'protected_file_rollback.dart';

abstract interface class JournalOwnerStore {
  Future<String?> loadName();

  Future<void> writeName(String? name);
}

/// Atomic, NSFileProtectionComplete-backed storage for the Journal owner
/// name. It is intentionally device-local and entirely separate from
/// CloudKit, analytics, and the Kept/sync envelopes.
final class ProtectedJournalOwnerStore implements JournalOwnerStore {
  ProtectedJournalOwnerStore({
    Future<Directory> Function()? rootDirectoryProvider,
    FileProtectionBridge? fileProtectionBridge,
    PersistenceOperationCoordinator? operationCoordinator,
    String Function()? tokenFactory,
  })  : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationSupportDirectory,
        _fileProtectionBridge =
            fileProtectionBridge ?? const MethodChannelFileProtectionBridge(),
        _coordinator =
            operationCoordinator ?? PersistenceOperationCoordinator(),
        _tokenFactory = tokenFactory ?? (() => const Uuid().v4());

  static const String resourceKey = 'protected_journal_owner_file';
  static const String _directoryName = 'east_journal_owner';
  static const String _fileName = 'east_journal_owner_v1.json';

  final Future<Directory> Function() _rootDirectoryProvider;
  final FileProtectionBridge _fileProtectionBridge;
  final PersistenceOperationCoordinator _coordinator;
  final String Function() _tokenFactory;

  @override
  Future<String?> loadName() {
    return _coordinator.runExclusive<String?>(
      resourceKey: resourceKey,
      operation: () async {
        final directory = await _resolveDirectory();
        final finalFile = File('${directory.path}/$_fileName');
        if (!await finalFile.exists()) {
          final recovered = await recoverProtectedBackup<_JournalOwnerValue>(
            directoryPath: directory.path,
            backupFilePrefix: '.$_fileName.backup-',
            finalFile: finalFile,
            fileDescription: 'Journal owner',
            recoveryPathForToken: (token) =>
                '${directory.path}/.$_fileName.recovery-$token',
            tokenFactory: _tokenFactory,
            decode: _JournalOwnerValue.decode,
            fileProtectionBridge: _fileProtectionBridge,
          );
          return recovered?.name;
        }

        final value = _JournalOwnerValue.decode(await finalFile.readAsString());
        await _fileProtectionBridge.protectAndVerifyComplete(finalFile.path);
        return value.name;
      },
    );
  }

  @override
  Future<void> writeName(String? name) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final directory = await _resolveDirectory();
        final finalFile = File('${directory.path}/$_fileName');
        if (name == null) {
          await _clearValue(directory: directory, finalFile: finalFile);
          return;
        }
        await _replace(directory: directory, finalFile: finalFile, name: name);
      },
    );
  }

  Future<Directory> _resolveDirectory() async {
    final root = await _rootDirectoryProvider();
    final directory = Directory('${root.path}/$_directoryName');
    await directory.create(recursive: true);
    await _fileProtectionBridge.protectAndVerifyComplete(directory.path);
    return directory;
  }

  Future<void> _replace({
    required Directory directory,
    required File finalFile,
    required String name,
  }) async {
    final next = _JournalOwnerValue(name);
    final token = _tokenFactory();
    final tempFile = File('${directory.path}/.$_fileName.tmp-$token');
    final backupFile = File('${directory.path}/.$_fileName.backup-$token');
    final recoveryFile = File('${directory.path}/.$_fileName.recovery-$token');
    _JournalOwnerValue? prior;
    var backupCreated = false;
    var finalReplaced = false;

    try {
      await _writeAndVerify(tempFile, next);

      if (await finalFile.exists()) {
        try {
          prior = _JournalOwnerValue.decode(await finalFile.readAsString());
          await _fileProtectionBridge.protectAndVerifyComplete(finalFile.path);
          if (prior == next) {
            await tempFile.delete();
            return;
          }
          await finalFile.rename(backupFile.path);
          backupCreated = true;
          await _fileProtectionBridge.protectAndVerifyComplete(backupFile.path);
        } catch (_) {
          // Preserve malformed prior bytes for forensic recovery, but never
          // let an unusable value prevent the user from saving a new one.
          if (await finalFile.exists()) {
            await finalFile.rename(
              '${directory.path}/.$_fileName.corrupt-$token',
            );
          }
          prior = null;
          backupCreated = false;
        }
      }

      await tempFile.rename(finalFile.path);
      finalReplaced = true;
      await _fileProtectionBridge.protectAndVerifyComplete(finalFile.path);
      final installed =
          _JournalOwnerValue.decode(await finalFile.readAsString());
      if (installed != next) {
        throw const JournalOwnerStoreException(
          'verify-final',
          'The installed Journal owner value did not verify.',
        );
      }
      if (backupCreated && await backupFile.exists()) {
        await backupFile.delete();
      }
      await _deleteTransactionArtifacts(directory);
    } catch (error) {
      await _deleteBestEffort(tempFile);
      if (backupCreated && prior != null && await backupFile.exists()) {
        await restoreProtectedBackup<_JournalOwnerValue>(
          backupFile: backupFile,
          finalFile: finalFile,
          recoveryFile: recoveryFile,
          expectedValue: prior,
          decode: _JournalOwnerValue.decode,
          fileProtectionBridge: _fileProtectionBridge,
        );
      } else if (finalReplaced) {
        await _deleteBestEffort(finalFile);
      }
      if (error is JournalOwnerStoreException) rethrow;
      throw JournalOwnerStoreException(
        'replace',
        'Could not replace the protected Journal owner value.',
        error,
      );
    }
  }

  Future<void> _writeAndVerify(
    File file,
    _JournalOwnerValue value,
  ) async {
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.writeString(value.encode());
      await handle.flush();
    } finally {
      await handle.close();
    }
    await _fileProtectionBridge.protectAndVerifyComplete(file.path);
    if (_JournalOwnerValue.decode(await file.readAsString()) != value) {
      throw const JournalOwnerStoreException(
        'verify-temp',
        'The temporary Journal owner value did not verify.',
      );
    }
  }

  Future<void> _deleteTransactionArtifacts(Directory directory) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('.$_fileName.tmp-') ||
            name.startsWith('.$_fileName.backup-') ||
            name.startsWith('.$_fileName.recovery-')) {
          await _deleteBestEffort(entity);
        }
      }
    } catch (_) {
      // Redundant transaction artifacts never invalidate a verified final.
    }
  }

  /// Removes every recoverable copy before deleting the authoritative value.
  /// If an old backup cannot be removed, the final file is deliberately kept
  /// so a later read can never resurrect a value the user already cleared.
  Future<void> _clearValue({
    required Directory directory,
    required File finalFile,
  }) async {
    try {
      final artifacts = <File>[];
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('.$_fileName.tmp-') ||
            name.startsWith('.$_fileName.backup-') ||
            name.startsWith('.$_fileName.recovery-')) {
          artifacts.add(entity);
        }
      }

      for (final artifact in artifacts) {
        if (await artifact.exists()) await artifact.delete();
      }
      if (await finalFile.exists()) await finalFile.delete();

      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('.$_fileName.backup-') ||
            name.startsWith('.$_fileName.recovery-')) {
          throw const JournalOwnerStoreException(
            'clear-verify',
            'A recoverable Journal owner copy remained after clear.',
          );
        }
      }
    } catch (error) {
      if (error is JournalOwnerStoreException) rethrow;
      throw JournalOwnerStoreException(
        'clear',
        'Could not clear every protected Journal owner copy.',
        error,
      );
    }
  }

  Future<void> _deleteBestEffort(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Preserve the original operation failure.
    }
  }
}

final class _JournalOwnerValue {
  const _JournalOwnerValue(this.name);

  static const int schemaVersion = 1;
  final String name;

  String encode() => jsonEncode(<String, Object?>{
        'schemaVersion': schemaVersion,
        'name': name,
      });

  static _JournalOwnerValue decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded['schemaVersion'] != schemaVersion ||
        decoded['name'] is! String) {
      throw const FormatException('Invalid Journal owner envelope.');
    }
    final name = (decoded['name'] as String).trim();
    if (name.isEmpty) {
      throw const FormatException('Journal owner name cannot be blank.');
    }
    return _JournalOwnerValue(name);
  }

  @override
  bool operator ==(Object other) =>
      other is _JournalOwnerValue && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

class JournalOwnerStoreException implements Exception {
  const JournalOwnerStoreException(this.stage, this.message, [this.cause]);

  final String stage;
  final String message;
  final Object? cause;

  @override
  String toString() => 'JournalOwnerStoreException[$stage]: $message';
}
