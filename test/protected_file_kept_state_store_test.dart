import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';
import 'package:wisdom_app/persistence/protected_file_kept_state_store.dart';

/// Fake [FileProtectionBridge] used throughout this file. Records every
/// path it was asked to protect (in call order), can be told to fail for a
/// given path a fixed number of times, and can run an arbitrary async hook
/// per call — used to inspect on-disk state mid-operation, corrupt a file
/// to simulate an inequality, or gate on a [Completer] for concurrency
/// tests. No real MethodChannel is involved anywhere in this file.
class _FakeFileProtectionBridge implements FileProtectionBridge {
  final List<String> protectedPaths = [];
  final Map<String, int> _remainingFailures = {};
  Future<void> Function(String path)? onProtect;

  void failNextTimeFor(String path, {int times = 1}) {
    _remainingFailures[path] = (_remainingFailures[path] ?? 0) + times;
  }

  @override
  Future<void> protectAndVerifyComplete(String path) async {
    protectedPaths.add(path);
    if (onProtect != null) {
      await onProtect!(path);
    }
    final remaining = _remainingFailures[path];
    if (remaining != null && remaining > 0) {
      _remainingFailures[path] = remaining - 1;
      throw const FileProtectionException('Simulated protection failure.');
    }
  }
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('kept_state_store_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  String dirPath() => '${tempRoot.path}/east_kept_state';
  String finalPath() => '${dirPath()}/east_kept_state_v3.json';
  String tempPathFor(String token) =>
      '${dirPath()}/.east_kept_state_v3.tmp-$token.json';
  String recoveryTempPathFor(String token) =>
      '${dirPath()}/.east_kept_state_v3.recover-$token.json';
  String backupPathFor(String token) =>
      '${dirPath()}/.east_kept_state_v3.backup-$token.json';

  ProtectedFileKeptStateStore buildStore({
    FileProtectionBridge? bridge,
    String Function()? tokenFactory,
    DateTime Function()? clock,
  }) {
    var counter = 0;
    return ProtectedFileKeptStateStore(
      rootDirectoryProvider: () async => tempRoot,
      fileProtectionBridge: bridge ?? _FakeFileProtectionBridge(),
      tokenFactory: tokenFactory ?? (() => 'token-${counter++}'),
      clock: clock ?? (() => DateTime.utc(2026, 8, 1, 12, 0)),
    );
  }

  KeptRecord buildRecord({
    String id = 'kept-1',
    String revealId = '123e4567-e89b-42d3-a456-426614174000',
    String wisdomText = 'What is meant for you does not panic.',
  }) {
    final revealedAt = DateTime.utc(2026, 6, 18, 9, 30);
    final keptAt = DateTime.utc(2026, 6, 18, 9, 31);
    return KeptRecord(
      id: id,
      revealId: revealId,
      wisdomText: wisdomText,
      revealedAt: revealedAt,
      keptAt: keptAt,
      updatedAt: keptAt,
      mutationId: 'a1b2c3d4-0000-4000-8000-000000000001',
    );
  }

  KeptStateEnvelope buildEnvelope({List<KeptRecord>? records}) {
    return KeptStateEnvelope(activeRecords: records ?? [buildRecord()]);
  }

  test('1. load returns null when no final file and no backup exist', () async {
    final store = buildStore();

    final result = await store.load();

    expect(result, isNull);
  });

  test('2. the protected directory is created and protected', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);

    await store.load();

    expect(Directory(dirPath()).existsSync(), isTrue);
    expect(bridge.protectedPaths, contains(dirPath()));
  });

  test('3. replace-then-load round-trips the exact envelope', () async {
    final store = buildStore();
    final envelope = buildEnvelope();

    await store.replace(envelope);
    final loaded = await store.load();

    expect(loaded, envelope);
  });

  test('4. replace performs whole-envelope replacement, not append', () async {
    var counter = 0;
    final store = buildStore(tokenFactory: () => 'token-${counter++}');
    final first = buildEnvelope(records: [buildRecord(id: 'kept-1')]);
    final second = buildEnvelope(records: [buildRecord(id: 'kept-2')]);

    await store.replace(first);
    await store.replace(second);
    final loaded = await store.load();

    expect(loaded!.activeRecords.length, 1);
    expect(loaded.activeRecords.single.id, 'kept-2');
  });

  test('5. active-record order is preserved through replace and load',
      () async {
    final store = buildStore();
    final envelope = buildEnvelope(records: [
      buildRecord(id: 'kept-1'),
      buildRecord(
        id: 'kept-2',
        revealId: '223e4567-e89b-42d3-a456-426614174001',
      ),
      buildRecord(
        id: 'kept-3',
        revealId: '323e4567-e89b-42d3-a456-426614174002',
      ),
    ]);

    await store.replace(envelope);
    final loaded = await store.load();

    expect(loaded!.activeRecords.map((r) => r.id).toList(),
        ['kept-1', 'kept-2', 'kept-3']);
  });

  test(
      '6. the temp file is flushed and readable, with content matching the '
      'intended envelope, before the atomic rename happens', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    final envelope = buildEnvelope();
    final expectedTempPath = tempPathFor('fixed');

    bridge.onProtect = (path) async {
      if (path == expectedTempPath) {
        final content = File(expectedTempPath).readAsStringSync();
        expect(KeptStateEnvelope.decodeString(content), envelope);
        expect(File(finalPath()).existsSync(), isFalse);
      }
    };

    await store.replace(envelope);
  });

  test('7. the temp file is protected before the atomic rename', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    final envelope = buildEnvelope();

    await store.replace(envelope);

    final tempIndex = bridge.protectedPaths.indexOf(tempPathFor('fixed'));
    final finalIndex = bridge.protectedPaths.indexOf(finalPath());
    expect(tempIndex, greaterThanOrEqualTo(0));
    expect(finalIndex, greaterThan(tempIndex));
  });

  test('8. the final file is protected and verified after replacement',
      () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);
    final envelope = buildEnvelope();

    await store.replace(envelope);

    expect(bridge.protectedPaths, contains(finalPath()));
  });

  test(
      '9. a failure before the rename (temp verification mismatch) leaves '
      'the existing valid final readable and unchanged', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    final original = buildEnvelope(records: [buildRecord(id: 'kept-original')]);
    await store.replace(original);

    final replacement =
        buildEnvelope(records: [buildRecord(id: 'kept-replacement')]);
    bridge.onProtect = (path) async {
      if (path == tempPathFor('fixed')) {
        // Corrupt the just-written, just-protected temp file so the
        // subsequent reopen/decode/compare step detects a mismatch.
        File(tempPathFor('fixed')).writeAsStringSync('{"tampered":true}');
      }
    };

    await expectLater(
      store.replace(replacement),
      throwsA(isA<KeptStateStoreException>()),
    );

    bridge.onProtect = null;
    final loaded = await store.load();
    expect(loaded, original);
  });

  test(
      '10. failed temp-file protection leaves the previous final file\'s '
      'bytes byte-for-byte unchanged', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    final original = buildEnvelope(records: [buildRecord(id: 'kept-original')]);
    await store.replace(original);
    final originalBytes = File(finalPath()).readAsStringSync();

    bridge.failNextTimeFor(tempPathFor('fixed'));
    final replacement =
        buildEnvelope(records: [buildRecord(id: 'kept-replacement')]);

    await expectLater(
      store.replace(replacement),
      throwsA(isA<KeptStateStoreException>()),
    );

    expect(File(finalPath()).readAsStringSync(), originalBytes);
  });

  test(
      '11. failed backup-file protection leaves the previous final file '
      'unchanged', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    final original = buildEnvelope(records: [buildRecord(id: 'kept-original')]);
    await store.replace(original);

    bridge.failNextTimeFor(backupPathFor('fixed'));
    final replacement =
        buildEnvelope(records: [buildRecord(id: 'kept-replacement')]);

    await expectLater(
      store.replace(replacement),
      throwsA(isA<KeptStateStoreException>()),
    );

    final loaded = await store.load();
    expect(loaded, original);
  });

  test(
      '12. a final-protection failure after rename restores the previous '
      'final', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    final original = buildEnvelope(records: [buildRecord(id: 'kept-original')]);
    await store.replace(original);

    // Fail only the first post-rename protect call on the final path; the
    // rollback's own re-protect of the restored final must still succeed.
    bridge.failNextTimeFor(finalPath());
    final replacement =
        buildEnvelope(records: [buildRecord(id: 'kept-replacement')]);

    await expectLater(
      store.replace(replacement),
      throwsA(isA<KeptStateStoreException>()),
    );

    final loaded = await store.load();
    expect(loaded, original);
  });

  test(
      '13. a final read-back corruption/mismatch after rename restores the '
      'previous final', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    final original = buildEnvelope(records: [buildRecord(id: 'kept-original')]);
    await store.replace(original);

    final replacement =
        buildEnvelope(records: [buildRecord(id: 'kept-replacement')]);
    var alreadyCorrupted = false;
    bridge.onProtect = (path) async {
      if (path == finalPath() && !alreadyCorrupted) {
        // Corrupt the final file immediately after it is protected but
        // before the post-rename reopen/decode/compare check runs. Guarded
        // so that the rollback's own later re-protect of the restored
        // final is not corrupted a second time.
        alreadyCorrupted = true;
        File(finalPath()).writeAsStringSync('{"tampered":true}');
      }
    };

    await expectLater(
      store.replace(replacement),
      throwsA(isA<KeptStateStoreException>()),
    );

    bridge.onProtect = null;
    final loaded = await store.load();
    expect(loaded, original);
  });

  test(
      '14. a first-write failure after rename (no previous final) leaves no '
      'authoritative file behind', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');

    bridge.failNextTimeFor(finalPath());
    final envelope = buildEnvelope();

    await expectLater(
      store.replace(envelope),
      throwsA(isA<KeptStateStoreException>()),
    );

    expect(File(finalPath()).existsSync(), isFalse);
    final loaded = await store.load();
    expect(loaded, isNull);
  });

  test(
      '15. when rollback itself also fails, the prior state is still '
      'recoverable on the next load (never silently lost)', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    final original = buildEnvelope(records: [buildRecord(id: 'kept-original')]);
    await store.replace(original);

    // The post-rename final-protect fails (triggering rollback), and the
    // rollback's own re-protect of the restored final also fails. Even so,
    // by that point the prior envelope's bytes have already been safely
    // restored to the authoritative path by the atomic rename-back — only
    // the redundant post-restore verification failed.
    bridge.failNextTimeFor(finalPath(), times: 2);
    final replacement =
        buildEnvelope(records: [buildRecord(id: 'kept-replacement')]);

    await expectLater(
      store.replace(replacement),
      throwsA(isA<KeptStateStoreException>()),
    );

    final recovered = await store.load();
    expect(recovered, isNotNull);
    expect(recovered, original);
  });

  test('16. load restores the newest valid backup when the final is absent',
      () async {
    final store = buildStore();
    Directory(dirPath()).createSync(recursive: true);
    final envelope = buildEnvelope(records: [buildRecord(id: 'kept-backup')]);
    final backupFile = File(backupPathFor('only-backup'))
      ..writeAsStringSync(envelope.encodeString());
    backupFile.setLastModifiedSync(DateTime.utc(2026, 7, 1));

    final loaded = await store.load();

    expect(loaded, envelope);
    expect(File(finalPath()).existsSync(), isTrue);
  });

  test('17. load ignores invalid backups and uses the newest valid one',
      () async {
    final store = buildStore();
    Directory(dirPath()).createSync(recursive: true);

    final invalidNewest = File(backupPathFor('invalid'))
      ..writeAsStringSync('{not valid json');
    invalidNewest.setLastModifiedSync(DateTime.utc(2026, 7, 3));

    final validMiddle = buildEnvelope(records: [buildRecord(id: 'kept-b')]);
    final validMiddleFile = File(backupPathFor('valid-middle'))
      ..writeAsStringSync(validMiddle.encodeString());
    validMiddleFile.setLastModifiedSync(DateTime.utc(2026, 7, 2));

    final validOldest = buildEnvelope(records: [buildRecord(id: 'kept-c')]);
    final validOldestFile = File(backupPathFor('valid-oldest'))
      ..writeAsStringSync(validOldest.encodeString());
    validOldestFile.setLastModifiedSync(DateTime.utc(2026, 7, 1));

    final loaded = await store.load();

    expect(loaded, validMiddle);
  });

  test(
      '18. a corrupt authoritative final is preserved byte-for-byte as a '
      'corrupt artifact, and load throws', () async {
    final store = buildStore();
    Directory(dirPath()).createSync(recursive: true);
    const corruptContent = '{not valid json at all';
    File(finalPath()).writeAsStringSync(corruptContent);

    await expectLater(
      store.load(),
      throwsA(isA<KeptStateStoreException>()),
    );

    final corruptFiles = Directory(dirPath())
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('east_kept_state_v3.corrupt-'))
        .toList();
    expect(corruptFiles, hasLength(1));
    expect(corruptFiles.single.readAsStringSync(), corruptContent);
  });

  test('19. the corrupt-preservation artifact itself is protected and verified',
      () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);
    Directory(dirPath()).createSync(recursive: true);
    File(finalPath()).writeAsStringSync('{not valid json');

    await expectLater(
      store.load(),
      throwsA(isA<KeptStateStoreException>()),
    );

    final corruptPath = bridge.protectedPaths
        .where((p) => p.contains('east_kept_state_v3.corrupt-'))
        .toList();
    expect(corruptPath, hasLength(1));
  });

  test('20. the original corrupt final is never deleted or overwritten',
      () async {
    final store = buildStore();
    Directory(dirPath()).createSync(recursive: true);
    const corruptContent = '{not valid json';
    File(finalPath()).writeAsStringSync(corruptContent);

    await expectLater(
      store.load(),
      throwsA(isA<KeptStateStoreException>()),
    );

    expect(File(finalPath()).existsSync(), isTrue);
    expect(File(finalPath()).readAsStringSync(), corruptContent);
  });

  test(
      '21. a successful load cleans up stale temp and backup files '
      'best-effort', () async {
    final store = buildStore();
    final envelope = buildEnvelope();
    await store.replace(envelope);
    File('${dirPath()}/.east_kept_state_v3.tmp-stale.json')
        .writeAsStringSync('stale temp');
    File('${dirPath()}/.east_kept_state_v3.backup-stale.json')
        .writeAsStringSync('stale backup');

    await store.load();

    expect(
      File('${dirPath()}/.east_kept_state_v3.tmp-stale.json').existsSync(),
      isFalse,
    );
    expect(
      File('${dirPath()}/.east_kept_state_v3.backup-stale.json').existsSync(),
      isFalse,
    );
  });

  test('22. a cleanup failure does not fail an otherwise-successful load',
      () async {
    final store = buildStore();
    final envelope = buildEnvelope();
    await store.replace(envelope);
    // A directory at a stale-temp-file-shaped path cannot be deleted via
    // File.delete(); this simulates a best-effort cleanup failure.
    Directory('${dirPath()}/.east_kept_state_v3.tmp-undeletable.json')
        .createSync();

    final loaded = await store.load();

    expect(loaded, envelope);
  });

  test('23. concurrent replace calls do not interleave', () async {
    final bridge = _FakeFileProtectionBridge();
    var counter = 0;
    final store = buildStore(
      bridge: bridge,
      tokenFactory: () => 'token-${counter++}',
    );
    final events = <String>[];
    // Completed by the fake bridge itself, exactly when A has genuinely
    // reached its blocking point — not inferred from an arbitrary delay.
    // Real dart:io file I/O (directory creation, file open/write/flush/
    // close) can take more than one event-loop turn to get there, which is
    // why a single `await Future.delayed(Duration.zero)` here previously
    // raced and occasionally observed `events` still empty.
    final aEnteredGate = Completer<void>();
    final releaseA = Completer<void>();

    bridge.onProtect = (path) async {
      if (path == tempPathFor('token-0')) {
        events.add('A-temp-protect-start');
        if (!aEnteredGate.isCompleted) aEnteredGate.complete();
        await releaseA.future;
        events.add('A-temp-protect-end');
      } else if (path == tempPathFor('token-1')) {
        events.add('B-temp-protect');
      }
    };

    final envelopeA = buildEnvelope(records: [buildRecord(id: 'kept-a')]);
    final envelopeB = buildEnvelope(records: [buildRecord(id: 'kept-b')]);

    // 1. Start replace A without awaiting its completion.
    final futureA = store.replace(envelopeA);

    // 2. Wait for the explicit signal that A has actually entered its
    // protected critical section (recorded 'A-temp-protect-start' and is
    // now blocked on releaseA) before asserting or proceeding.
    await aEnteredGate.future;

    // 3. Only now assert A reached the expected gate.
    expect(events, ['A-temp-protect-start']);

    // 4. Start replace B while A remains blocked.
    final futureB = store.replace(envelopeB);

    // 5. Prove B has not entered the protected file-mutation pipeline
    // before A is released. This is a structural guarantee of
    // PersistenceOperationCoordinator.runExclusive, not a timing race:
    // runExclusive captures A's still-pending operation future as B's
    // predecessor synchronously, inside the store.replace(envelopeB) call
    // above — B's own operation() (and therefore its tokenFactory call and
    // its temp-file protect call) cannot run until that predecessor
    // resolves, which has not happened yet.
    expect(events, ['A-temp-protect-start']);

    // 6. Release A.
    releaseA.complete();

    // 7. Await both operations.
    await futureA;
    await futureB;

    // 8. The complete, ordered event log proves no interleaving: B's
    // temp-protect call only ever happens after A's fully completes.
    expect(events, [
      'A-temp-protect-start',
      'A-temp-protect-end',
      'B-temp-protect',
    ]);
    final loaded = await store.load();
    expect(loaded, envelopeB);
  });

  test('24. load cannot observe a half-completed replace', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    final gate = Completer<void>();

    bridge.onProtect = (path) async {
      if (path == tempPathFor('fixed')) {
        await gate.future;
      }
    };

    final envelope = buildEnvelope(records: [buildRecord(id: 'kept-new')]);
    final replaceFuture = store.replace(envelope);
    await Future<void>.delayed(Duration.zero);

    // load() is queued behind the in-flight replace() on the same
    // coordinator resource key, so it must not resolve before the gate
    // opens and the replace completes.
    var loadCompleted = false;
    final loadFuture = store.load().then((result) {
      loadCompleted = true;
      return result;
    });

    await Future<void>.delayed(Duration.zero);
    expect(loadCompleted, isFalse);

    gate.complete();
    await replaceFuture;
    final loaded = await loadFuture;

    expect(loadCompleted, isTrue);
    expect(loaded, envelope);
  });

  test('25. replace rejects a temp-file read-back inequality', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    final envelope = buildEnvelope();

    bridge.onProtect = (path) async {
      if (path == tempPathFor('fixed')) {
        File(tempPathFor('fixed')).writeAsStringSync('{"tampered":true}');
      }
    };

    await expectLater(
      store.replace(envelope),
      throwsA(isA<KeptStateStoreException>()),
    );
  });

  test('26. a malformed stored envelope throws rather than returning null',
      () async {
    final store = buildStore();
    Directory(dirPath()).createSync(recursive: true);
    File(finalPath()).writeAsStringSync('{"schemaVersion": 999}');

    Object? caught;
    KeptStateEnvelope? result;
    try {
      result = await store.load();
    } catch (error) {
      caught = error;
    }

    expect(caught, isA<KeptStateStoreException>());
    expect(result, isNull); // never assigned; load() threw instead.
  });

  test('27. a protection failure on the directory prevents read and write',
      () async {
    final bridge = _FakeFileProtectionBridge();
    bridge.failNextTimeFor(dirPath(), times: 2);
    final store = buildStore(bridge: bridge);

    await expectLater(
      store.load(),
      throwsA(isA<KeptStateStoreException>()),
    );
    await expectLater(
      store.replace(buildEnvelope()),
      throwsA(isA<KeptStateStoreException>()),
    );
    expect(File(finalPath()).existsSync(), isFalse);
  });

  test('28. the store uses the injected root directory provider', () async {
    final customRoot =
        Directory.systemTemp.createTempSync('kept_state_custom_root_');
    addTearDown(() => customRoot.deleteSync(recursive: true));

    final store = ProtectedFileKeptStateStore(
      rootDirectoryProvider: () async => customRoot,
      fileProtectionBridge: _FakeFileProtectionBridge(),
      tokenFactory: () => 'fixed',
      clock: () => DateTime.utc(2026, 8, 1),
    );

    await store.replace(buildEnvelope());

    expect(
      File('${customRoot.path}/east_kept_state/east_kept_state_v3.json')
          .existsSync(),
      isTrue,
    );
  });

  test('29. deterministic injected token names are honored', () async {
    final bridge = _FakeFileProtectionBridge();
    final store =
        buildStore(bridge: bridge, tokenFactory: () => 'deterministic-token');

    await store.replace(buildEnvelope());

    expect(
      bridge.protectedPaths,
      contains(tempPathFor('deterministic-token')),
    );
  });

  test('30. no file is ever written outside the east_kept_state directory',
      () async {
    final store = buildStore();
    await store.replace(buildEnvelope());
    await store.load();

    final allFiles =
        tempRoot.listSync(recursive: true).whereType<File>().toList();
    for (final file in allFiles) {
      expect(file.path.startsWith('${dirPath()}/'), isTrue,
          reason: '${file.path} was written outside east_kept_state');
    }
  });

  test(
      '31. load-time final protection failures are typed and keep their '
      'cause out of diagnostic rendering', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);
    final envelope = buildEnvelope();
    await store.replace(envelope);
    bridge.failNextTimeFor(finalPath());

    Object? caught;
    try {
      await store.load();
    } catch (error) {
      caught = error;
    }

    expect(caught, isA<KeptStateStoreException>());
    final typed = caught! as KeptStateStoreException;
    expect(typed.stage, 'load-protect');
    expect(typed.cause, isA<FileProtectionException>());
    expect(typed.toString(), isNot(contains(tempRoot.path)));
    expect(typed.toString(), isNot(contains('Simulated protection failure')));
    expect(await File(finalPath()).readAsString(), envelope.encodeString());
  });

  test(
      '32. recovery-temp protection failure preserves the selected backup '
      'byte-for-byte and leaves no authoritative final', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'recover');
    Directory(dirPath()).createSync(recursive: true);
    final envelope = buildEnvelope(
      records: [buildRecord(id: 'kept-recovery-source')],
    );
    final backupPath = backupPathFor('source');
    final backupBytes = envelope.encodeString();
    await File(backupPath).writeAsString(backupBytes);
    bridge.failNextTimeFor(recoveryTempPathFor('recover'));

    await expectLater(
      store.load(),
      throwsA(
        isA<KeptStateStoreException>().having(
          (error) => error.stage,
          'stage',
          'load-recover-protect-temp',
        ),
      ),
    );

    expect(await File(backupPath).readAsString(), backupBytes);
    expect(await File(finalPath()).exists(), isFalse);
    expect(await File(recoveryTempPathFor('recover')).exists(), isFalse);

    final recovered = await store.load();
    expect(recovered, envelope);
  });

  test(
      '33. recovered-final protection failure preserves the selected backup '
      'and a later healthy load can still recover it', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'recover');
    Directory(dirPath()).createSync(recursive: true);
    final envelope = buildEnvelope(
      records: [buildRecord(id: 'kept-final-protect-source')],
    );
    final backupPath = backupPathFor('source');
    final backupBytes = envelope.encodeString();
    await File(backupPath).writeAsString(backupBytes);
    bridge.failNextTimeFor(finalPath());

    await expectLater(
      store.load(),
      throwsA(
        isA<KeptStateStoreException>().having(
          (error) => error.stage,
          'stage',
          'load-recover-protect-final',
        ),
      ),
    );

    expect(await File(backupPath).readAsString(), backupBytes);
    expect(await File(finalPath()).exists(), isFalse);
    expect(await store.load(), envelope);
  });

  test(
      '34. existing but wholly corrupt backups fail closed instead of '
      'looking like a never-written store', () async {
    final store = buildStore();
    Directory(dirPath()).createSync(recursive: true);
    await File(backupPathFor('bad-a')).writeAsString('{bad');
    await File(backupPathFor('bad-b')).writeAsString('{also-bad');

    await expectLater(
      store.load(),
      throwsA(
        isA<KeptStateStoreException>().having(
          (error) => error.stage,
          'stage',
          'load-recover-exhausted',
        ),
      ),
    );
  });

  test('35. successful ordinary load removes stale recovery-temp files',
      () async {
    final store = buildStore();
    final envelope = buildEnvelope();
    await store.replace(envelope);
    await File(recoveryTempPathFor('stale')).writeAsString('stale');

    expect(await store.load(), envelope);
    expect(await File(recoveryTempPathFor('stale')).exists(), isFalse);
  });
}
