import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/reflection_history.dart';
import 'package:wisdom_app/services/data_export_builder.dart';
import 'package:wisdom_app/services/journal_pdf_builder.dart';
import 'package:wisdom_app/services/journal_pdf_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime.utc(2026, 9, 1);
  FavoriteItem item({int count = 2, String suffix = ''}) => FavoriteItem(
        id: 'kept-one',
        text: 'Peace enters slowly.',
        date: 'September 1, 2026',
        keptAt: date.toIso8601String(),
        reflection: 'The original 👨‍👩‍👧‍👦.',
        reflectedAt: date.toIso8601String(),
        reflectionHistoryJson: ReflectionHistory(thoughts: [
          for (var i = 1; i <= count; i++)
            ReflectionThought(
              id: 'aaaaaaaa-0000-4000-8000-${i.toString().padLeft(12, '0')}',
              mutationId:
                  'bbbbbbbb-0000-4000-8000-${i.toString().padLeft(12, '0')}',
              text:
                  'Thought $i: ${List.filled(count > 2 ? 18 : 1, 'There is room for a different understanding.').join(' ')} $suffix',
              createdAtMs: date.add(Duration(days: i)).millisecondsSinceEpoch,
              updatedAtMs:
                  date.add(Duration(days: i, hours: 1)).millisecondsSinceEpoch,
            ),
        ]).encode(),
      );

  test('JSON and text export retain every dated thought without sync metadata',
      () {
    final source = item();
    final export = const DataExportBuilder()
        .build(items: [source], journalOwnerName: null, exportedAt: date);
    final json = jsonDecode(utf8.decode(export.jsonBytes)) as Map;
    final reflection = (json['reflections'] as List).single as Map;
    expect(reflection['reflectionText'], source.reflection);
    final thoughts = reflection['thoughts'] as List;
    expect(thoughts, hasLength(2));
    expect(thoughts.first['createdAt'], '2026-09-02T00:00:00.000Z');
    expect(thoughts.first['updatedAt'], '2026-09-02T01:00:00.000Z');
    expect(utf8.decode(export.jsonBytes), isNot(contains('mutationId')));
    expect(utf8.decode(export.jsonBytes), isNot(contains('clearedAtMs')));
    final plain = utf8.decode(export.txtBytes);
    for (final thought in source.reflectionHistory.thoughts) {
      expect(plain, contains(thought.text));
    }
    expect(plain.indexOf('Thought 1:'), lessThan(plain.indexOf('Thought 2:')));
  });

  test(
      'long thought histories paginate and preserve every thought in VoiceOver',
      () async {
    final source = item(count: 12);
    final publication = await JournalPdfBuilder()
        .buildPublication(items: [source], now: date, compress: false);
    final physicalPages = RegExp(r'/Type\s*/Page(?!s)\b')
        .allMatches(latin1.decode(publication.bytes))
        .length;
    expect(physicalPages, greaterThan(6));
    expect(publication.accessibility.pageLabels, hasLength(physicalPages));
    final spoken = publication.accessibility.pageLabels.join('\n');
    expect(spoken, contains(source.reflection!));
    for (final thought in source.reflectionHistory.thoughts) {
      expect(spoken, contains(thought.text));
    }
    expect(spoken, contains('September 2, 2026'));
    expect(spoken, contains('September 13, 2026'));
  });

  test(
      'a later thought invalidates a cached Journal even when the original is unchanged',
      () {
    String fingerprint(FavoriteItem source) => JournalPdfFingerprint.create(
        items: [source],
        ownerName: null,
        locale: const Locale('en'),
        brightness: Brightness.light,
        generatedAt: date);
    expect(fingerprint(item(suffix: 'A revised later thought.')),
        isNot(fingerprint(item())));
  });
}
