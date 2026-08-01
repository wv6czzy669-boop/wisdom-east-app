import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_migration_recovery_artifact.dart';
import 'package:wisdom_app/models/kept_migration_snapshot.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';
import 'package:wisdom_app/persistence/protected_kept_migration_artifact_store.dart';

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
  const migrationId = '123e4567-e89b-4d3a-a456-426614174000';
  final capturedAt = DateTime.utc(2026, 8, 1, 9, 0);

  late Directory tempRoot;

  setUp(() {
    tempRoot =
        Directory.systemTemp.createTempSync('kept_migration_artifact_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  String dirPath() => '${tempRoot.path}/east_kept_state';

  ProtectedKeptMigrationArtifactStore buildStore({
    FileProtectionBridge? bridge,
    String Function()? tokenFactory,
  }) {
    var counter = 0;
    return ProtectedKeptMigrationArtifactStore(
      rootDirectoryProvider: () async => tempRoot,
      fileProtectionBridge: bridge ?? _FakeFileProtectionBridge(),
      tokenFactory: tokenFactory ?? (() => 'token-${counter++}'),
    );
  }

  KeptMigrationSnapshot buildSnapshot({String rawValue = 'first|||text'}) {
    return KeptMigrationSnapshot(
      migrationId: migrationId,
      capturedAt: capturedAt,
      legacyKey: 'favorites',
      entries: [KeptMigrationSnapshotEntry(index: 0, rawValue: rawValue)],
    );
  }

  KeptMigrationRecoveryArtifact buildRecoveryArtifact() {
    return KeptMigrationRecoveryArtifact(
      migrationId: migrationId,
      createdAt: capturedAt,
      legacyEntryCount: 1,
      usableEntryCount: 0,
      corruptEntries: const [
        KeptMigrationRecoveryEntry(
          index: 0,
          rawValue: 'garbage',
          stage: KeptMigrationFailureStage.decode,
          reasonCode: 'favorite_decode_failed',
        ),
      ],
    );
  }

  test('23. snapshot write/load round-trips', () async {
    final store = buildStore();
    final snapshot = buildSnapshot();
    const fileName = 'snap.json';

    await store.writeSnapshot(fileName, snapshot);
    final loaded = await store.loadSnapshot(fileName);

    expect(loaded, snapshot);
  });

  test('24. recovery artifact write/load round-trips', () async {
    final store = buildStore();
    final artifact = buildRecoveryArtifact();
    const fileName = 'recovery.json';

    await store.writeRecoveryArtifact(fileName, artifact);
    final loaded = await store.loadRecoveryArtifact(fileName);

    expect(loaded, artifact);
  });

  test('25. the protected directory is created and protected', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);

    await store.writeSnapshot('snap.json', buildSnapshot());

    expect(Directory(dirPath()).existsSync(), isTrue);
    expect(bridge.protectedPaths, contains(dirPath()));
  });

  test('26. both the temporary and final files are protected', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    const fileName = 'snap.json';

    await store.writeSnapshot(fileName, buildSnapshot());

    expect(
      bridge.protectedPaths,
      contains('${dirPath()}/.$fileName.tmp-fixed'),
    );
    expect(bridge.protectedPaths, contains('${dirPath()}/$fileName'));
  });

  test('27. writing an existing, identical artifact is idempotent', () async {
    final store = buildStore();
    final snapshot = buildSnapshot();
    const fileName = 'snap.json';

    await store.writeSnapshot(fileName, snapshot);
    await expectLater(store.writeSnapshot(fileName, snapshot), completes);

    final loaded = await store.loadSnapshot(fileName);
    expect(loaded, snapshot);
  });

  test(
      '28. an existing mismatched artifact is rejected without being '
      'overwritten', () async {
    final store = buildStore();
    const fileName = 'snap.json';
    final original = buildSnapshot();
    final different = buildSnapshot(rawValue: 'different|||text');

    await store.writeSnapshot(fileName, original);

    await expectLater(
      store.writeSnapshot(fileName, different),
      throwsA(isA<KeptMigrationArtifactStoreException>()),
    );

    final loaded = await store.loadSnapshot(fileName);
    expect(loaded, original);
  });

  test('29. a temp-file read-back mismatch is rejected', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'fixed');
    const fileName = 'snap.json';
    final tempPath = '${dirPath()}/.$fileName.tmp-fixed';

    bridge.onProtect = (path) async {
      if (path == tempPath) {
        File(tempPath).writeAsStringSync('{"tampered":true}');
      }
    };

    await expectLater(
      store.writeSnapshot(fileName, buildSnapshot()),
      throwsA(isA<KeptMigrationArtifactStoreException>()),
    );
    expect(File('${dirPath()}/$fileName').existsSync(), isFalse);
  });

  test('30. no artifact file is ever written outside east_kept_state',
      () async {
    final store = buildStore();
    await store.writeSnapshot('snap.json', buildSnapshot());
    await store.writeRecoveryArtifact('recovery.json', buildRecoveryArtifact());

    final allFiles =
        tempRoot.listSync(recursive: true).whereType<File>().toList();
    expect(allFiles, isNotEmpty);
    for (final file in allFiles) {
      expect(
        file.path.startsWith('${dirPath()}/'),
        isTrue,
        reason: '${file.path} was written outside east_kept_state',
      );
    }
  });

  test('31. concurrent artifact writes are serialized', () async {
    final bridge = _FakeFileProtectionBridge();
    var counter = 0;
    final store = buildStore(
      bridge: bridge,
      tokenFactory: () => 'token-${counter++}',
    );
    final events = <String>[];
    final aEnteredGate = Completer<void>();
    final releaseA = Completer<void>();
    final tempPathA = '${dirPath()}/.snap-a.json.tmp-token-0';
    final tempPathB = '${dirPath()}/.snap-b.json.tmp-token-1';

    bridge.onProtect = (path) async {
      if (path == tempPathA) {
        events.add('A-temp-protect-start');
        if (!aEnteredGate.isCompleted) aEnteredGate.complete();
        await releaseA.future;
        events.add('A-temp-protect-end');
      } else if (path == tempPathB) {
        events.add('B-temp-protect');
      }
    };

    final futureA = store.writeSnapshot('snap-a.json', buildSnapshot());
    await aEnteredGate.future;
    expect(events, ['A-temp-protect-start']);

    final futureB = store.writeSnapshot(
      'snap-b.json',
      buildSnapshot(rawValue: 'other'),
    );
    expect(events, ['A-temp-protect-start']);

    releaseA.complete();
    await futureA;
    await futureB;

    expect(events, [
      'A-temp-protect-start',
      'A-temp-protect-end',
      'B-temp-protect',
    ]);
  });

  test('32. a corrupt existing artifact throws rather than returning null',
      () async {
    final store = buildStore();
    Directory(dirPath()).createSync(recursive: true);
    File('${dirPath()}/snap.json').writeAsStringSync('not valid json');

    expect(
      () => store.loadSnapshot('snap.json'),
      throwsA(isA<KeptMigrationArtifactStoreException>()),
    );
  });
}
