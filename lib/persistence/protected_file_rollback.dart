import 'dart:io';

import 'file_protection_bridge.dart';

typedef ProtectedValueDecoder<T> = T Function(String encoded);

/// Restores one already-verified backup without consuming it prematurely.
///
/// The backup remains at its original path until a separate recovery file
/// has been written, protected, decoded, atomically installed, protected
/// again, and compared with [expectedValue]. This is shared by every EAST.
/// protected JSON store so their rollback guarantees cannot drift apart.
Future<void> restoreProtectedBackup<T>({
  required File backupFile,
  required File finalFile,
  required File recoveryFile,
  required T expectedValue,
  required ProtectedValueDecoder<T> decode,
  required FileProtectionBridge fileProtectionBridge,
}) async {
  var installedFinal = false;
  try {
    final backupBytes = await backupFile.readAsString();

    final recoveryHandle = await recoveryFile.open(mode: FileMode.write);
    try {
      await recoveryHandle.writeString(backupBytes);
      await recoveryHandle.flush();
    } finally {
      await recoveryHandle.close();
    }

    await fileProtectionBridge.protectAndVerifyComplete(recoveryFile.path);
    final recoveredCandidate = decode(await recoveryFile.readAsString());
    if (recoveredCandidate != expectedValue) {
      throw const ProtectedFileRollbackException(
        'verify-recovery',
        'The rollback recovery file did not match the prior value.',
      );
    }

    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await recoveryFile.rename(finalFile.path);
    installedFinal = true;

    await fileProtectionBridge.protectAndVerifyComplete(finalFile.path);
    final restoredValue = decode(await finalFile.readAsString());
    if (restoredValue != expectedValue) {
      throw const ProtectedFileRollbackException(
        'verify-final',
        'The restored authoritative file did not match the prior value.',
      );
    }

    // Only a fully verified final makes the original backup redundant.
    await _deleteBestEffort(backupFile);
  } catch (error) {
    await _deleteBestEffort(recoveryFile);
    // Once the recovery file has been renamed, a later protection/readback
    // failure means the authoritative path is not trusted. Remove that
    // candidate so the next ordinary load can see and restore the preserved
    // backup instead of repeatedly preferring a failed final file.
    if (installedFinal) {
      await _deleteBestEffort(finalFile);
    }
    if (error is ProtectedFileRollbackException) rethrow;
    throw ProtectedFileRollbackException(
      'restore',
      'Could not restore the prior protected value.',
      error,
    );
  }
}

Future<void> _deleteBestEffort(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // The original operation remains the meaningful failure. A cleanup
    // artifact is harmless and can be removed by the next ordinary load.
  }
}

/// Internal infrastructure failure. The cause stays available to callers
/// programmatically but is deliberately omitted from [toString] so paths or
/// encoded user data from nested filesystem errors cannot reach diagnostics.
class ProtectedFileRollbackException implements Exception {
  const ProtectedFileRollbackException(this.stage, this.message, [this.cause]);

  final String stage;
  final String message;
  final Object? cause;

  @override
  String toString() => 'ProtectedFileRollbackException[$stage]: $message';
}
