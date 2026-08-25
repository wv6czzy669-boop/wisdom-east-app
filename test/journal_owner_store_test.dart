import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';
import 'package:wisdom_app/persistence/journal_owner_store.dart';

void main() {
  late Directory root;
  late _RecordingProtectionBridge protection;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('east-owner-store-');
    protection = _RecordingProtectionBridge();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  ProtectedJournalOwnerStore buildStore() => ProtectedJournalOwnerStore(
        rootDirectoryProvider: () async => root,
        fileProtectionBridge: protection,
        tokenFactory: () => 'fixed-token',
      );

  test('round-trips Unicode name outside SharedPreferences', () async {
    final store = buildStore();

    await store.writeName('Doğukan Işık 🌿');

    expect(await store.loadName(), 'Doğukan Işık 🌿');
    final finalFile = File(
      '${root.path}/east_journal_owner/east_journal_owner_v1.json',
    );
    expect(await finalFile.exists(), isTrue);
    expect(protection.paths, contains(finalFile.path));
  });

  test('clear removes the authoritative protected value', () async {
    final store = buildStore();
    await store.writeName('Owner');

    await store.writeName(null);

    expect(await store.loadName(), isNull);
  });

  test('clear removes stale recoverable backups before the final value',
      () async {
    final store = buildStore();
    await store.writeName('Owner');
    final directory = Directory('${root.path}/east_journal_owner');
    final backup = File(
      '${directory.path}/.east_journal_owner_v1.json.backup-stale',
    );
    await backup.writeAsString(
      '{"schemaVersion":1,"name":"Stale owner"}',
    );

    await store.writeName(null);

    expect(await backup.exists(), isFalse);
    expect(await buildStore().loadName(), isNull);
  });

  test('a failed temporary protection never destroys the prior value',
      () async {
    final store = buildStore();
    await store.writeName('Prior');
    protection.failTemporaryFiles = true;

    await expectLater(store.writeName('Next'), throwsA(isA<Exception>()));

    protection.failTemporaryFiles = false;
    expect(await store.loadName(), 'Prior');
  });

  test('malformed stored data fails closed without exposing its contents',
      () async {
    final directory = Directory('${root.path}/east_journal_owner');
    await directory.create(recursive: true);
    final file = File('${directory.path}/east_journal_owner_v1.json');
    await file.writeAsString('{"name":"private but malformed"}');

    await expectLater(buildStore().loadName(), throwsA(isA<FormatException>()));
  });
}

final class _RecordingProtectionBridge implements FileProtectionBridge {
  final List<String> paths = [];
  bool failTemporaryFiles = false;

  @override
  Future<void> protectAndVerifyComplete(String path) async {
    paths.add(path);
    if (failTemporaryFiles && path.contains('.tmp-')) {
      throw const FileProtectionException('injected temporary failure');
    }
  }
}
