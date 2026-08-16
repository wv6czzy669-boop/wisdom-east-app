import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/services/analytics_event.dart';
import 'package:wisdom_app/services/analytics_service.dart';
import 'package:wisdom_app/services/data_export_service.dart';
import 'package:wisdom_app/services/journal_owner_service.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';
import 'package:wisdom_app/sync_integration/kept_sync_integration_coordinator.dart';

import '../persistence_test_helpers.dart';
import '../sync_integration/in_memory_sync_test_doubles.dart';

class _FakeAnalyticsTransport implements AnalyticsTransport {
  final List<AnalyticsEvent> tracked = [];

  @override
  void track(AnalyticsEvent event) {
    tracked.add(event);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  KeptRecord record({
    required String id,
    required String revealId,
    required String wisdomText,
    required DateTime keptAt,
    String? reflectionText,
    DateTime? reflectedAt,
  }) {
    return KeptRecord(
      id: id,
      revealId: revealId,
      wisdomText: wisdomText,
      revealedAt: keptAt,
      keptAt: keptAt,
      reflectionText: reflectionText,
      reflectedAt: reflectedAt,
      updatedAt: reflectedAt ?? keptAt,
      mutationId: revealId,
    );
  }

  test('a successful export shares both a JSON and a TXT file, built from '
      'the real active Kept/Reflection content', () async {
    final graph = KeptRepositoryTestGraph();
    graph.seed([
      record(
        id: '1',
        revealId: 'a5f3c111-1111-4111-8111-000000000001',
        wisdomText: 'A kept wisdom',
        keptAt: DateTime.utc(2026, 1, 1),
        reflectionText: 'A private reflection',
        reflectedAt: DateTime.utc(2026, 1, 2),
      ),
    ]);

    ShareParams? captured;
    final service = DataExportService(
      savedReflectionsServiceProvider: () => graph.service,
      journalOwnerService: JournalOwnerService(),
      clock: () => DateTime.utc(2026, 8, 16),
      shareLauncher: (params) async {
        captured = params;
        return const ShareResult('', ShareResultStatus.success);
      },
    );

    final succeeded = await service.exportAndShare();

    expect(succeeded, isTrue);
    expect(captured, isNotNull);
    expect(captured!.files, hasLength(2));
    expect(captured!.fileNameOverrides, [
      'EAST-Data-2026-08-16.json',
      'EAST-Data-2026-08-16.txt',
    ]);

    final jsonBytes = await captured!.files!.first.readAsBytes();
    final decoded =
        jsonDecode(utf8.decode(jsonBytes)) as Map<String, Object?>;
    final kept = decoded['kept'] as List<Object?>;
    expect(kept, hasLength(1));
    final reflections = decoded['reflections'] as List<Object?>;
    expect(reflections, hasLength(1));

    final txtBytes = await captured!.files!.last.readAsBytes();
    final txt = utf8.decode(txtBytes);
    expect(txt, contains('A kept wisdom'));
    expect(txt, contains('A private reflection'));
  });

  test('the optional Journal owner name is included when present', () async {
    final graph = KeptRepositoryTestGraph();
    final ownerService = JournalOwnerService();
    await ownerService.saveName('Doğukan Işık');

    ShareParams? captured;
    final service = DataExportService(
      savedReflectionsServiceProvider: () => graph.service,
      journalOwnerService: ownerService,
      clock: () => DateTime.utc(2026, 8, 16),
      shareLauncher: (params) async {
        captured = params;
        return const ShareResult('', ShareResultStatus.success);
      },
    );

    await service.exportAndShare();

    final jsonBytes = await captured!.files!.first.readAsBytes();
    final decoded =
        jsonDecode(utf8.decode(jsonBytes)) as Map<String, Object?>;
    expect(decoded['journalOwnerName'], 'Doğukan Işık');
  });

  test('export does not mutate Kept, Reflections, or sync state', () async {
    final graph = KeptRepositoryTestGraph();
    graph.seed([
      record(
        id: '1',
        revealId: 'a5f3c111-1111-4111-8111-000000000001',
        wisdomText: 'A kept wisdom',
        keptAt: DateTime.utc(2026, 1, 1),
        reflectionText: 'A private reflection',
        reflectedAt: DateTime.utc(2026, 1, 2),
      ),
    ]);
    final envelopeBefore = graph.store.envelope;

    final service = DataExportService(
      savedReflectionsServiceProvider: () => graph.service,
      journalOwnerService: JournalOwnerService(),
      clock: () => DateTime.utc(2026, 8, 16),
      shareLauncher: (params) async =>
          const ShareResult('', ShareResultStatus.success),
    );

    await service.exportAndShare();

    // Same envelope, byte-for-byte: `load()` never writes.
    expect(graph.store.envelope, envelopeBefore);
    expect(await graph.intentStore.loadIntents(), isEmpty);
  });

  test('export emits no analytics event of any kind', () async {
    final graph = KeptRepositoryTestGraph();
    graph.seed([
      record(
        id: '1',
        revealId: 'a5f3c111-1111-4111-8111-000000000001',
        wisdomText: 'A kept wisdom',
        keptAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    final transport = _FakeAnalyticsTransport();
    final analyticsAwareService = SavedReflectionsService(
      keptRepository: graph.repository,
      syncCoordinator: KeptSyncIntegrationCoordinator(
        keptRepository: graph.repository,
        intentStore: InMemoryLocalSyncIntentStore(),
        syncPersistenceStore: InMemorySyncPersistenceStore(),
      ),
      analyticsService: AnalyticsService(transport: transport),
    );

    final service = DataExportService(
      savedReflectionsServiceProvider: () => analyticsAwareService,
      journalOwnerService: JournalOwnerService(),
      shareLauncher: (params) async =>
          const ShareResult('', ShareResultStatus.success),
    );

    await service.exportAndShare();

    expect(transport.tracked, isEmpty);
  });

  test('a share/generation failure returns false and leaves Kept/'
      'Reflection state untouched -- the app remains usable', () async {
    final graph = KeptRepositoryTestGraph();
    graph.seed([
      record(
        id: '1',
        revealId: 'a5f3c111-1111-4111-8111-000000000001',
        wisdomText: 'A kept wisdom',
        keptAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    final envelopeBefore = graph.store.envelope;

    final service = DataExportService(
      savedReflectionsServiceProvider: () => graph.service,
      journalOwnerService: JournalOwnerService(),
      shareLauncher: (params) async => throw StateError('share failed'),
    );

    final succeeded = await service.exportAndShare();

    expect(succeeded, isFalse);
    expect(graph.store.envelope, envelopeBefore);
  });

  test('neither the builder nor the service *codes against* CloudKit/'
      'sync-internal types -- structural proof by source inspection (doc-'
      'comment prose describing this guarantee is expected and excluded) '
      'that no network/iCloud read is required to export', () {
    for (final path in [
      'lib/services/data_export_service.dart',
      'lib/services/data_export_builder.dart',
    ]) {
      final codeOnly = File(path)
          .readAsLinesSync()
          .where((line) => !line.trim().startsWith('//'))
          .join('\n');
      const forbidden = [
        'CKRecord',
        'cloud_kit',
        'KeptRepository',
        'dataEpoch',
        'SyncPersistenceStore',
      ];
      for (final term in forbidden) {
        expect(
          codeOnly.contains(term),
          isFalse,
          reason: '$path must never reference "$term" outside a comment',
        );
      }
    }
  });
}
