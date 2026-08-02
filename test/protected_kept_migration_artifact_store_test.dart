import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_migration_recovery_artifact.dart';
import 'package:wisdom_app/models/kept_migration_snapshot.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';
import 'package:wisdom_app/persistence/protected_kept_migration_artifact_store.dart';
import 'package:wisdom_app/utils/kept_timestamp_canonicalizer.dart';

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

  // -------------------------------------------------------------------
  // Phase 3D-D real-device migration hotfix (round 2): a genuinely
  // sub-millisecond-precision capturedAt/createdAt — the common case for a
  // DateTime.now()-sourced clock on a real device — makes the store's own
  // mandatory write-then-read-back verification fail, because
  // KeptMigrationSnapshot.encode()/KeptMigrationRecoveryArtifact.encode()
  // only serialize millisecond precision (capturedAtMs/createdAtMs) while
  // their operator== compares via isAtSameMomentAs, exact to the
  // microsecond. This reproduces, against the real store (not a fake),
  // the exact confirmed real-device failure:
  //   EAST_KEPT_DIAGNOSTIC stage-failed: snapshot-write
  //   errorType=KeptMigrationArtifactStoreException
  //   message=Temporary artifact file did not match the intended content.
  //
  // These tests are independent of KeptMigrationCoordinator's own fix
  // (canonicalizing before construction) — they prove the model/store
  // wire-round-trip defect directly, and prove canonicalizing first is
  // the correct fix, without depending on the coordinator at all.
  // -------------------------------------------------------------------
  group('Phase 3D-D: microsecond-bearing artifact timestamps', () {
    // The exact shape of clock value recovered from the physical device's
    // failing run (see the coordinator's real snapshot-write failure).
    final microsecondBearingClock =
        DateTime.utc(2026, 8, 2, 9, 44, 43, 484, 133);

    test(
        '33. an uncanonicalized microsecond-bearing snapshot capturedAt '
        'fails the store\'s own write-verify-temp read-back check '
        '(proves the exact defect, independent of any coordinator fix)',
        () async {
      final store = buildStore();
      final snapshot = KeptMigrationSnapshot(
        migrationId: migrationId,
        capturedAt: microsecondBearingClock,
        legacyKey: 'favorites',
        entries: const [
          KeptMigrationSnapshotEntry(index: 0, rawValue: 'first|||text'),
        ],
      );

      await expectLater(
        store.writeSnapshot('snap.json', snapshot),
        throwsA(
          isA<KeptMigrationArtifactStoreException>().having(
            (e) => e.stage,
            'stage',
            'write-verify-temp',
          ),
        ),
      );
      // The exact-field proof: encode() truncated capturedAt to millisecond
      // precision, decode() reconstructed at millisecond precision, and
      // operator== (isAtSameMomentAs) compared that against the original
      // microsecond-bearing value and found them not the same moment.
      final encoded = snapshot.encodeString();
      final decoded = KeptMigrationSnapshot.decodeString(encoded);
      expect(decoded.capturedAt.isAtSameMomentAs(snapshot.capturedAt), isFalse);
      expect(decoded.capturedAt.microsecond, 0);
      expect(snapshot.capturedAt.microsecond, isNot(0));
      // Every other field survives the round trip unchanged — this is not
      // a general corruption, only the timestamp precision.
      expect(decoded.migrationId, snapshot.migrationId);
      expect(decoded.legacyKey, snapshot.legacyKey);
      expect(decoded.entries, snapshot.entries);
    });

    test(
        '34. canonicalizing capturedAt before construction makes the exact '
        'same snapshot write and round-trip successfully', () async {
      final store = buildStore();
      final snapshot = KeptMigrationSnapshot(
        migrationId: migrationId,
        capturedAt: canonicalizeKeptTimestamp(microsecondBearingClock),
        legacyKey: 'favorites',
        entries: const [
          KeptMigrationSnapshotEntry(index: 0, rawValue: 'first|||text'),
        ],
      );

      await store.writeSnapshot('snap.json', snapshot);
      final loaded = await store.loadSnapshot('snap.json');

      expect(loaded, snapshot);
    });

    test(
        '35. an uncanonicalized microsecond-bearing recovery artifact '
        'createdAt fails the same write-verify-temp check', () async {
      final store = buildStore();
      final artifact = KeptMigrationRecoveryArtifact(
        migrationId: migrationId,
        createdAt: microsecondBearingClock,
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

      await expectLater(
        store.writeRecoveryArtifact('recovery.json', artifact),
        throwsA(
          isA<KeptMigrationArtifactStoreException>().having(
            (e) => e.stage,
            'stage',
            'write-verify-temp',
          ),
        ),
      );
    });

    test(
        '36. canonicalizing createdAt before construction makes the exact '
        'same recovery artifact write and round-trip successfully', () async {
      final store = buildStore();
      final artifact = KeptMigrationRecoveryArtifact(
        migrationId: migrationId,
        createdAt: canonicalizeKeptTimestamp(microsecondBearingClock),
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

      await store.writeRecoveryArtifact('recovery.json', artifact);
      final loaded = await store.loadRecoveryArtifact('recovery.json');

      expect(loaded, artifact);
    });

    test(
        '37. no temp/final artifact file is left behind after a '
        'write-verify-temp failure (fail-closed, nothing partially '
        'written)', () async {
      final store = buildStore(tokenFactory: () => 'fixed');
      final snapshot = KeptMigrationSnapshot(
        migrationId: migrationId,
        capturedAt: microsecondBearingClock,
        legacyKey: 'favorites',
        entries: const [
          KeptMigrationSnapshotEntry(index: 0, rawValue: 'first|||text'),
        ],
      );

      await expectLater(
        store.writeSnapshot('snap.json', snapshot),
        throwsA(isA<KeptMigrationArtifactStoreException>()),
      );

      expect(
        File('${dirPath()}/.snap.json.tmp-fixed').existsSync(),
        isFalse,
      );
      expect(File('${dirPath()}/snap.json').existsSync(), isFalse);
    });
  });
}
