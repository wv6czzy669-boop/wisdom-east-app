// Build 26 Phase 4A: structural proof that the CloudKit sync domain can
// never represent daily access / the rolling 24-hour lock, and that no
// projection type can ever leak wisdom or Reflection content into a
// diagnostic-shaped summary. See
// docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §1 and §7.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync/sync_tombstone.dart';

/// Strips `//`, `///`, and `/* */` comments from [source] while leaving
/// single-, double-, and triple-quoted string literals untouched -- so a
/// `//` or `/*` sequence inside a string literal is never mistaken for a
/// comment, and a forbidden-looking identifier named only in an explanatory
/// doc comment is never mistaken for real code. Comment characters are
/// replaced with spaces (never removed outright), and newlines are always
/// preserved, so this only ever narrows what the caller sees as "code" --
/// it can never turn commented-out code into something that reads as a
/// real dependency. Dart block comments may nest, so nesting depth is
/// tracked explicitly. Used only by test 1 below; test 2 (the import/export
/// directive check) deliberately does not use this and instead reads raw
/// line text, so a real dependency can never hide from both checks at once.
String _stripComments(String source) {
  final buffer = StringBuffer();
  var i = 0;
  final length = source.length;

  while (i < length) {
    final char = source[i];

    // Line comment: `//` or `///`, up to (not including) the newline.
    if (char == '/' && i + 1 < length && source[i + 1] == '/') {
      while (i < length && source[i] != '\n') {
        buffer.write(' ');
        i++;
      }
      continue;
    }

    // Block comment: `/* ... */`. Dart block comments may nest, so track
    // depth rather than stopping at the first `*/`.
    if (char == '/' && i + 1 < length && source[i + 1] == '*') {
      var depth = 1;
      buffer.write('  ');
      i += 2;
      while (i < length && depth > 0) {
        if (i + 1 < length && source[i] == '/' && source[i + 1] == '*') {
          depth++;
          buffer.write('  ');
          i += 2;
          continue;
        }
        if (i + 1 < length && source[i] == '*' && source[i + 1] == '/') {
          depth--;
          buffer.write('  ');
          i += 2;
          continue;
        }
        buffer.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }

    // Triple-quoted string: `'''` or `"""`. Copied through untouched
    // (including any `//` or `/*` inside it) so it is never mistaken for a
    // comment start.
    if ((char == "'" || char == '"') &&
        i + 2 < length &&
        source[i + 1] == char &&
        source[i + 2] == char) {
      final quote = char * 3;
      buffer.write(quote);
      i += 3;
      while (i < length && !source.startsWith(quote, i)) {
        buffer.write(source[i]);
        i++;
      }
      if (i < length) {
        buffer.write(quote);
        i += 3;
      }
      continue;
    }

    // Single-line, single- or double-quoted string, with backslash escapes
    // honored so an escaped quote never prematurely ends the string.
    if (char == "'" || char == '"') {
      final quote = char;
      buffer.write(char);
      i++;
      while (i < length && source[i] != quote && source[i] != '\n') {
        if (source[i] == '\\' && i + 1 < length) {
          buffer.write(source[i]);
          buffer.write(source[i + 1]);
          i += 2;
          continue;
        }
        buffer.write(source[i]);
        i++;
      }
      if (i < length && source[i] == quote) {
        buffer.write(quote);
        i++;
      }
      continue;
    }

    buffer.write(char);
    i++;
  }

  return buffer.toString();
}

void main() {
  group('structural: the sync domain never references daily access', () {
    // These substrings are what a daily-access dependency or a leaked
    // ritual-lock concept would look like if one were ever accidentally
    // introduced into lib/sync/ -- this test reads the actual committed
    // source, not a description of it, so it fails the moment any of these
    // are introduced, deliberately or not.
    //
    // The scan runs against [_stripComments]'s output, never the raw file
    // text: explanatory prose (a doc comment reassuring the reader "this
    // never depends on X") must never fail this test merely for naming the
    // forbidden concept in words -- only an actual import, export, type
    // reference, or other code-level token counts. A dedicated,
    // comment-independent check of import/export directives (test 2 below)
    // exists specifically so this leniency can never be exploited to hide
    // a real dependency inside a comment-adjacent trick (e.g. a
    // deliberately malformed comment) -- directives are parsed from the raw
    // line text directly, never from the comment-stripped version.
    const forbiddenSubstrings = [
      'DailyWisdomRecord',
      'DailyAccessRepository',
      'DailyWisdomAccessService',
      'daily_wisdom_access',
      'daily_wisdom_record.dart',
      'daily_access_repository.dart',
      'unlockAt',
      'lockDuration',
      'pending_daily_wisdom_reveal',
      'PendingDailyWisdomReveal',
    ];

    // Forbidden substrings scoped to import/export target paths only --
    // deliberately a superset check (a forbidden file path found anywhere
    // in an import/export line's string literal), independent of whether
    // the general comment-stripped scan above would also have caught it.
    const forbiddenImportPathSubstrings = [
      'daily_wisdom_record.dart',
      'daily_access_repository.dart',
      'daily_wisdom_access_service.dart',
      'pending_daily_wisdom_reveal.dart',
      'daily_access_snapshot.dart',
    ];

    late Directory syncDir;
    late List<File> dartFiles;

    setUpAll(() {
      syncDir = Directory('lib/sync');
      expect(
        syncDir.existsSync(),
        isTrue,
        reason: 'Expected lib/sync to exist relative to the package root '
            '(the directory flutter test runs from).',
      );
      dartFiles = syncDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
    });

    test(
        '1. no file under lib/sync/ contains, in real code (never in a '
        'comment or doc comment), any daily-access type, file, or '
        'ritual-lock identifier', () {
      expect(dartFiles, isNotEmpty);

      final violations = <String>[];
      for (final file in dartFiles) {
        final codeOnly = _stripComments(file.readAsStringSync());
        for (final forbidden in forbiddenSubstrings) {
          if (codeOnly.contains(forbidden)) {
            violations.add('${file.path} contains "$forbidden" in code '
                '(outside any comment)');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: violations.join('\n'),
      );
    });

    test(
        '2. no file under lib/sync/ imports or exports any daily-access '
        'file, checked directly against raw import/export directive lines '
        '-- independent of the comment-aware scan above', () {
      final violations = <String>[];
      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (final line in lines) {
          final trimmed = line.trimLeft();
          final isDirective =
              trimmed.startsWith('import ') || trimmed.startsWith('export ');
          if (!isDirective) continue;
          for (final forbiddenPath in forbiddenImportPathSubstrings) {
            if (trimmed.contains(forbiddenPath)) {
              violations.add('${file.path}: directive "$trimmed" references '
                  '"$forbiddenPath"');
            }
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        '3. every file scanned is a real, non-empty pure-Dart source file '
        '(the checks above are not vacuously passing over zero files)', () {
      expect(dartFiles.length, greaterThanOrEqualTo(8));
      for (final file in dartFiles) {
        expect(file.readAsStringSync().trim(), isNotEmpty);
      }
    });

    test(
        '4. a forbidden identifier mentioned only in a comment or doc '
        'comment does not fail the comment-aware scan (proves the scan '
        'distinguishes prose from code, rather than merely happening to '
        'pass today)', () {
      const source = '''
/// This class never depends on DailyWisdomRecord or unlockAt.
// Also never on DailyAccessRepository.
int realCode() => 1;
''';
      final codeOnly = _stripComments(source);
      for (final forbidden in forbiddenSubstrings) {
        expect(codeOnly.contains(forbidden), isFalse, reason: forbidden);
      }
      // The real code line itself must still survive stripping intact.
      expect(codeOnly, contains('int realCode() => 1;'));
    });

    test(
        '5. a forbidden identifier that genuinely appears in code (not a '
        'comment) is still caught (proves the scan cannot be trivially '
        'satisfied by wrapping everything in a comment)', () {
      const source = '''
// A comment mentioning nothing forbidden.
class Probe {
  DailyWisdomRecord? x;
}
''';
      final codeOnly = _stripComments(source);
      expect(codeOnly.contains('DailyWisdomRecord'), isTrue);
    });
  });

  group('type-level: no constructor path accepts a daily-access type', () {
    const revealId = 'c947bbb4-f86a-4db3-87c9-ed5e718bbd98';
    final epoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
    final now = DateTime.utc(2026, 8, 1, 20, 0);

    test(
        '3. CloudKeptWisdomProjection.active only accepts a KeptRecord -- '
        'there is no overload, named constructor, or optional parameter '
        'that accepts anything daily-access-shaped', () {
      final record = KeptRecord(
        id: 'local-id-1',
        revealId: revealId,
        wisdomText: 'Be still and know.',
        revealedAt: now,
        keptAt: now,
        updatedAt: now,
        mutationId: '22222222-2222-4222-8222-222222222222',
      );

      // The mere fact that this compiles with a KeptRecord (a statically
      // required, non-optional first positional argument) and that the
      // structural scan above proves lib/sync/ never imports a
      // daily-access type at all, together prove there is no code path by
      // which a DailyWisdomRecord could ever reach a projection.
      expect(
        () => CloudKeptWisdomProjection.active(record, dataEpoch: epoch),
        returnsNormally,
      );
    });
  });

  group('privacy: no diagnostic-shaped summary ever leaks content', () {
    const revealId = 'c947bbb4-f86a-4db3-87c9-ed5e718bbd98';
    final epoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
    final now = DateTime.utc(2026, 8, 1, 20, 0);
    const secretWisdom =
        'This exact wisdom text must never appear in any log-safe summary.';
    const secretReflection =
        'This exact reflection text must never appear in any log-safe summary.';

    test('4. CloudKeptWisdomProjection.toLogSafeSummary excludes both', () {
      final record = KeptRecord(
        id: 'local-id-1',
        revealId: revealId,
        wisdomText: secretWisdom,
        revealedAt: now,
        keptAt: now,
        reflectionText: secretReflection,
        reflectedAt: now,
        updatedAt: now,
        mutationId: '22222222-2222-4222-8222-222222222222',
      );
      final projection =
          CloudKeptWisdomProjection.active(record, dataEpoch: epoch);

      final summary = projection.toLogSafeSummary();
      final rendered = summary.toString();
      expect(rendered, isNot(contains(secretWisdom)));
      expect(rendered, isNot(contains(secretReflection)));
    });

    test('5. SyncChange.toLogSafeSummary excludes both, for a create change',
        () {
      final record = KeptRecord(
        id: 'local-id-1',
        revealId: revealId,
        wisdomText: secretWisdom,
        revealedAt: now,
        keptAt: now,
        reflectionText: secretReflection,
        reflectedAt: now,
        updatedAt: now,
        mutationId: '22222222-2222-4222-8222-222222222222',
      );
      final projection =
          CloudKeptWisdomProjection.active(record, dataEpoch: epoch);
      final change = SyncChange(
        kind: SyncChangeKind.create,
        projection: projection,
        enqueuedAt: now,
      );

      final rendered = change.toLogSafeSummary().toString();
      expect(rendered, isNot(contains(secretWisdom)));
      expect(rendered, isNot(contains(secretReflection)));
    });

    test(
        '6. a tombstone-form summary structurally cannot leak content -- '
        'it has none to leak', () {
      final tombstone = SyncTombstone(
        revealId: revealId,
        dataEpoch: epoch,
        updatedAt: now,
        deletedAt: now,
        mutationId: '22222222-2222-4222-8222-222222222222',
      );
      final projection = CloudKeptWisdomProjection.tombstone(tombstone);
      final rendered = projection.toLogSafeSummary().toString();

      expect(rendered, isNot(contains(secretWisdom)));
      expect(rendered, isNot(contains(secretReflection)));
    });
  });
}
