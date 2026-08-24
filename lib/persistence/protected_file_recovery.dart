import 'dart:io';

import 'file_protection_bridge.dart';

typedef ProtectedRecoveryDecoder<T> = T Function(String encoded);

/// Recovers the newest decodable protected backup without ever moving or
/// mutating that source until the restored authoritative file is verified.
///
/// Returns `null` only when no backup file exists. If candidates exist but
/// none are usable, the operation fails closed with `load-recover-exhausted`.
/// Every protected JSON store uses this one algorithm so recovery ordering,
/// stages, and backup-preservation guarantees cannot drift by domain.
Future<T?> recoverProtectedBackup<T>({
  required String directoryPath,
  required String backupFilePrefix,
  required File finalFile,
  required String fileDescription,
  required String Function(String token) recoveryPathForToken,
  required String Function() tokenFactory,
  required ProtectedRecoveryDecoder<T> decode,
  required FileProtectionBridge fileProtectionBridge,
}) async {
  final List<File> backups;
  try {
    backups = await _listFilesWithPrefix(directoryPath, backupFilePrefix);
  } catch (error) {
    throw ProtectedFileRecoveryException(
      'load-recover-list',
      'Could not list candidate backup files while recovering the '
          'authoritative $fileDescription file.',
      error,
    );
  }
  if (backups.isEmpty) return null;

  final withModifiedTime = <MapEntry<File, DateTime>>[];
  for (final file in backups) {
    try {
      withModifiedTime.add(MapEntry(file, (await file.stat()).modified));
    } catch (_) {
      // An unreadable candidate remains evidence that durable state existed,
      // but cannot be selected as a recovery source.
    }
  }
  withModifiedTime.sort((a, b) => b.value.compareTo(a.value));

  for (final entry in withModifiedTime) {
    final backupFile = entry.key;
    final String backupBytes;
    final T expectedValue;
    try {
      backupBytes = await backupFile.readAsString();
      expectedValue = decode(backupBytes);
    } catch (_) {
      continue;
    }

    final File recoveryFile;
    try {
      recoveryFile = File(recoveryPathForToken(tokenFactory()));
    } catch (error) {
      throw ProtectedFileRecoveryException(
        'load-recover-write-temp',
        'Could not create the recovery temporary file while restoring '
            'from backup.',
        error,
      );
    }

    try {
      final handle = await recoveryFile.open(mode: FileMode.write);
      try {
        await handle.writeString(backupBytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
    } catch (error) {
      await _deleteBestEffort(recoveryFile);
      throw ProtectedFileRecoveryException(
        'load-recover-write-temp',
        'Could not write the recovery temporary file while restoring '
            'from backup.',
        error,
      );
    }

    try {
      await fileProtectionBridge.protectAndVerifyComplete(recoveryFile.path);
    } catch (error) {
      await _deleteBestEffort(recoveryFile);
      throw ProtectedFileRecoveryException(
        'load-recover-protect-temp',
        'Could not protect the recovery temporary file while restoring '
            'from backup.',
        error,
      );
    }

    try {
      if (decode(await recoveryFile.readAsString()) != expectedValue) {
        throw const ProtectedFileRecoveryException(
          'load-recover-verify-temp',
          'Recovery temporary file did not match the selected backup '
              'envelope.',
        );
      }
    } catch (error) {
      await _deleteBestEffort(recoveryFile);
      if (error is ProtectedFileRecoveryException) rethrow;
      throw ProtectedFileRecoveryException(
        'load-recover-verify-temp',
        'Could not verify the recovery temporary file while restoring '
            'from backup.',
        error,
      );
    }

    try {
      await recoveryFile.rename(finalFile.path);
    } catch (error) {
      await _deleteBestEffort(recoveryFile);
      throw ProtectedFileRecoveryException(
        'load-recover-rename',
        'Could not restore a valid backup to the authoritative path.',
        error,
      );
    }

    try {
      await fileProtectionBridge.protectAndVerifyComplete(finalFile.path);
    } catch (error) {
      await _deleteBestEffort(finalFile);
      throw ProtectedFileRecoveryException(
        'load-recover-protect-final',
        'Could not verify protection of the restored authoritative '
            '$fileDescription file after recovering it from backup.',
        error,
      );
    }

    try {
      if (decode(await finalFile.readAsString()) != expectedValue) {
        throw ProtectedFileRecoveryException(
          'load-recover-verify-final',
          'Restored authoritative $fileDescription file did not match the '
              'selected backup envelope.',
        );
      }
    } catch (error) {
      await _deleteBestEffort(finalFile);
      if (error is ProtectedFileRecoveryException) rethrow;
      throw ProtectedFileRecoveryException(
        'load-recover-verify-final',
        'Could not verify the restored authoritative $fileDescription file '
            'after recovering it from backup.',
        error,
      );
    }

    await _deleteBestEffort(backupFile);
    return expectedValue;
  }

  throw ProtectedFileRecoveryException(
    'load-recover-exhausted',
    'The authoritative $fileDescription file is missing, and every '
        'candidate backup failed to read or decode.',
  );
}

Future<List<File>> _listFilesWithPrefix(
  String directoryPath,
  String prefix,
) async {
  final entries = await Directory(directoryPath).list().toList();
  return entries
      .whereType<File>()
      .where((file) => file.uri.pathSegments.last.startsWith(prefix))
      .toList();
}

Future<void> _deleteBestEffort(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {
    // A redundant artifact is safer than invalidating a recovered value.
  }
}

class ProtectedFileRecoveryException implements Exception {
  const ProtectedFileRecoveryException(this.stage, this.message, [this.cause]);

  final String stage;
  final String message;
  final Object? cause;

  @override
  String toString() => 'ProtectedFileRecoveryException[$stage]: $message';
}
