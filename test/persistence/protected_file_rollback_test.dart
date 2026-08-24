import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';
import 'package:wisdom_app/persistence/protected_file_rollback.dart';

class _FakeProtectionBridge implements FileProtectionBridge {
  final Map<String, int> _remainingFailures = {};
  Future<void> Function(String path)? onProtect;

  void failNextTimeFor(String path) {
    _remainingFailures[path] = (_remainingFailures[path] ?? 0) + 1;
  }

  @override
  Future<void> protectAndVerifyComplete(String path) async {
    await onProtect?.call(path);
    final remaining = _remainingFailures[path] ?? 0;
    if (remaining > 0) {
      _remainingFailures[path] = remaining - 1;
      throw FileProtectionException('failure at $path');
    }
  }
}

void main() {
  late Directory root;
  late File backup;
  late File finalFile;
  late File recovery;
  late _FakeProtectionBridge bridge;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('protected_rollback_test_');
    backup = File('${root.path}/backup.json');
    finalFile = File('${root.path}/final.json');
    recovery = File('${root.path}/recover.json');
    bridge = _FakeProtectionBridge();
    await backup.writeAsString('prior');
    await finalFile.writeAsString('untrusted-new');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  String decode(String value) => value;

  Future<void> restore() => restoreProtectedBackup<String>(
        backupFile: backup,
        finalFile: finalFile,
        recoveryFile: recovery,
        expectedValue: 'prior',
        decode: decode,
        fileProtectionBridge: bridge,
      );

  test('fully verified restore installs prior value and removes backup',
      () async {
    await restore();

    expect(await finalFile.readAsString(), 'prior');
    expect(await backup.exists(), isFalse);
    expect(await recovery.exists(), isFalse);
  });

  test('recovery protection failure leaves original backup untouched',
      () async {
    bridge.failNextTimeFor(recovery.path);

    await expectLater(
        restore(), throwsA(isA<ProtectedFileRollbackException>()));

    expect(await backup.readAsString(), 'prior');
    expect(await finalFile.readAsString(), 'untrusted-new');
    expect(await recovery.exists(), isFalse);
  });

  test('final protection failure leaves the original backup recoverable',
      () async {
    bridge.failNextTimeFor(finalFile.path);

    await expectLater(
        restore(), throwsA(isA<ProtectedFileRollbackException>()));

    expect(await backup.readAsString(), 'prior');
    expect(await finalFile.exists(), isFalse,
        reason: 'an unverified authoritative candidate must not shadow the '
            'preserved backup on the next load');

    await restore();
    expect(await finalFile.readAsString(), 'prior');
    expect(await backup.exists(), isFalse);
  });

  test('recovery inequality is rejected before authoritative replacement',
      () async {
    bridge.onProtect = (path) async {
      if (path == recovery.path) {
        await recovery.writeAsString('tampered');
      }
    };

    await expectLater(
      restore(),
      throwsA(
        isA<ProtectedFileRollbackException>().having(
          (error) => error.stage,
          'stage',
          'verify-recovery',
        ),
      ),
    );

    expect(await backup.readAsString(), 'prior');
    expect(await finalFile.readAsString(), 'untrusted-new');
  });

  test('exception rendering never includes nested filesystem paths', () {
    final error = ProtectedFileRollbackException(
      'restore',
      'Could not restore.',
      FileSystemException('private', '/private/user/path'),
    );

    expect(error.cause, isA<FileSystemException>());
    expect(error.toString(), isNot(contains('/private/user/path')));
    expect(error.toString(), isNot(contains('private')));
  });
}
