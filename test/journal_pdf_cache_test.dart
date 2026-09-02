import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';
import 'package:wisdom_app/services/journal_pdf_builder.dart';
import 'package:wisdom_app/services/journal_pdf_cache.dart';

final class _RecordingProtectionBridge implements FileProtectionBridge {
  final List<String> protectedPaths = <String>[];

  @override
  Future<void> protectAndVerifyComplete(String path) async {
    if (!await FileSystemEntity.isDirectory(path) &&
        !await FileSystemEntity.isFile(path)) {
      throw FileProtectionException('Missing cache path: $path');
    }
    protectedPaths.add(path);
  }
}

FavoriteItem _item({
  String id = 'kept-1',
  String text = 'A quiet truth.',
  String? reflection = 'It stayed with me.',
}) {
  return FavoriteItem(
    id: id,
    revealId: '11111111-1111-4111-8111-111111111111',
    wisdomId: 'wisdom_001',
    text: text,
    date: 'August 1, 2026',
    reflection: reflection,
    reflectedAt: reflection == null ? null : '2026-08-01T12:00:00.000Z',
    keptAt: '2026-08-01T10:00:00.000Z',
  );
}

JournalPdfPublication _publication(List<int> bytes, List<String> labels) {
  return JournalPdfPublication(
    bytes: Uint8List.fromList(bytes),
    accessibility: JournalPdfAccessibility(pageLabels: labels),
  );
}

void main() {
  group('JournalPdfFingerprint', () {
    test('is stable for identical publication inputs', () {
      final first = JournalPdfFingerprint.create(
        items: [_item()],
        ownerName: '  Doğukan  ',
        locale: const Locale('tr'),
        brightness: Brightness.light,
        generatedAt: DateTime(2026, 1, 1),
      );
      final second = JournalPdfFingerprint.create(
        items: [_item()],
        ownerName: 'Doğukan',
        locale: const Locale('tr'),
        brightness: Brightness.light,
        generatedAt: DateTime(2026, 12, 31, 23, 59),
      );

      expect(second, first);
    });

    test('changes for every input that can alter publication bytes', () {
      String fingerprint({
        List<FavoriteItem>? items,
        String? ownerName = 'Doğukan',
        Locale locale = const Locale('tr'),
        Brightness brightness = Brightness.light,
        int year = 2026,
      }) {
        return JournalPdfFingerprint.create(
          items: items ?? [_item()],
          ownerName: ownerName,
          locale: locale,
          brightness: brightness,
          generatedAt: DateTime(year),
        );
      }

      final baseline = fingerprint();
      expect(
        fingerprint(items: [_item(reflection: 'A changed reflection.')]),
        isNot(baseline),
      );
      expect(fingerprint(ownerName: 'Another owner'), isNot(baseline));
      expect(fingerprint(locale: const Locale('en')), isNot(baseline));
      expect(fingerprint(brightness: Brightness.dark), isNot(baseline));
      expect(fingerprint(year: 2027), isNot(baseline));
    });

    test('ignores incidental repository order when chronology is unchanged',
        () {
      final older = _item(id: 'older').copyWith(
        keptAt: '2025-08-01T10:00:00.000Z',
      );
      final newer = _item(id: 'newer').copyWith(
        keptAt: '2026-08-01T10:00:00.000Z',
      );
      String fingerprint(List<FavoriteItem> items) {
        return JournalPdfFingerprint.create(
          items: items,
          ownerName: null,
          locale: const Locale('en'),
          brightness: Brightness.light,
          generatedAt: DateTime(2026),
        );
      }

      expect(
        fingerprint(<FavoriteItem>[newer, older]),
        fingerprint(<FavoriteItem>[older, newer]),
      );
    });
  });

  group('ProtectedJournalPdfCache', () {
    late Directory root;
    late _RecordingProtectionBridge protection;
    late ProtectedJournalPdfCache cache;
    var token = 0;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('east-journal-cache-');
      protection = _RecordingProtectionBridge();
      cache = ProtectedJournalPdfCache(
        rootDirectoryProvider: () async => root,
        fileProtectionBridge: protection,
        tokenFactory: () => 'token-${token++}',
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('round-trips bytes and exact physical-page accessibility labels',
        () async {
      final publication = _publication(
        <int>[1, 2, 3, 4, 5],
        <String>['Cover', '2026', 'Entry one', 'The end'],
      );

      await cache.write('fingerprint-a', publication);
      final restored = await cache.read('fingerprint-a');

      expect(restored, isNotNull);
      expect(restored!.bytes, publication.bytes);
      expect(
        restored.accessibility.pageLabels,
        publication.accessibility.pageLabels,
      );
      expect(
        protection.protectedPaths.where((path) => path.endsWith('.pdf')),
        isNotEmpty,
      );
      expect(
        protection.protectedPaths.where((path) => path.endsWith('.json')),
        isNotEmpty,
      );
    });

    test('rejects and removes a cache whose PDF checksum no longer matches',
        () async {
      await cache.write(
        'fingerprint-a',
        _publication(<int>[1, 2, 3], <String>['Cover']),
      );
      final directory = Directory('${root.path}/east_journal_pdf_cache');
      final pdf = File('${directory.path}/fingerprint-a.pdf');
      final manifest = File('${directory.path}/fingerprint-a.json');
      await pdf.writeAsBytes(<int>[9, 9, 9], flush: true);

      expect(await cache.read('fingerprint-a'), isNull);
      expect(await pdf.exists(), isFalse);
      expect(await manifest.exists(), isFalse);
    });

    test('keeps only the newest derived publication slot', () async {
      await cache.write(
        'fingerprint-a',
        _publication(<int>[1], <String>['First']),
      );
      await cache.write(
        'fingerprint-b',
        _publication(<int>[2], <String>['Second']),
      );

      expect(await cache.read('fingerprint-a'), isNull);
      final latest = await cache.read('fingerprint-b');
      expect(latest, isNotNull);
      expect(latest!.bytes, Uint8List.fromList(<int>[2]));
      expect(latest.accessibility.pageLabels, <String>['Second']);
    });
  });
}
