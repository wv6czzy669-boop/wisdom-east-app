import 'dart:convert';
import 'dart:typed_data';

import '../models/favorite_item.dart';
import '../utils/date_formatter.dart';

/// The two in-memory export payloads and their deterministic filenames.
/// Never written to a permanent location by this class -- see
/// `DataExportService` for how these bytes actually reach the native share
/// sheet.
class DataExportDocument {
  const DataExportDocument({
    required this.jsonBytes,
    required this.txtBytes,
    required this.jsonFilename,
    required this.txtFilename,
  });

  final Uint8List jsonBytes;
  final Uint8List txtBytes;
  final String jsonFilename;
  final String txtFilename;
}

/// EAST. — pure builder for the user-owned data export (JSON + TXT).
///
/// Deliberately separated from any file/share/platform concern: this class
/// takes already-loaded [FavoriteItem]s (the exact same read model Kept,
/// Return, and Journal already use) and an already-loaded optional Journal
/// owner name, and produces two in-memory byte payloads. No I/O, no
/// platform channel, nothing to mock beyond plain data -- fully testable
/// without any native/UI surface.
///
/// Only meaningful, user-owned ACTIVE content is included: a Kept
/// occurrence's stable local `recordId`, optional `revealId`, wisdom text,
/// and `keptAt`, and (only when present) a Reflection's matching identity,
/// text, and `reflectedAt`. Every CloudKit-internal,
/// sync-internal, purchase, analytics, rating, notification,
/// Return-scheduling, and rolling-24h-lock field is structurally absent --
/// this builder never even receives them, since [FavoriteItem] itself never
/// carries them (see its own class doc comment). Pre-`revealId` records are
/// exported with their existing [FavoriteItem.id]; export never fabricates or
/// persists a new domain identity.
class DataExportBuilder {
  const DataExportBuilder();

  static const String formatName = 'EAST Data Export';
  static const int schemaVersion = 2;
  static const String _divider = '--------------------------------';

  DataExportDocument build({
    required List<FavoriteItem> items,
    required String? journalOwnerName,
    required DateTime exportedAt,
  }) {
    final sorted = _sortedChronologically(items);

    final jsonText = _buildJson(
      sorted: sorted,
      journalOwnerName: journalOwnerName,
      exportedAt: exportedAt,
    );
    final txtText = _buildTxt(
      sorted: sorted,
      journalOwnerName: journalOwnerName,
      exportedAt: exportedAt,
    );
    final stamp = _dateStamp(exportedAt);

    return DataExportDocument(
      jsonBytes: Uint8List.fromList(utf8.encode(jsonText)),
      txtBytes: Uint8List.fromList(utf8.encode(txtText)),
      jsonFilename: 'EAST-Data-$stamp.json',
      txtFilename: 'EAST-Data-$stamp.txt',
    );
  }

  /// Oldest → newest by [FavoriteItem.keptAt]. An item with no parseable
  /// `keptAt` sorts after every dated item; ties (including the undated
  /// group) break deterministically on the occurrence's existing identity --
  /// `revealId` when present, otherwise its local `id`. Wisdom text and input
  /// order are never used as identity.
  List<FavoriteItem> _sortedChronologically(List<FavoriteItem> items) {
    final sorted = List<FavoriteItem>.from(items);
    sorted.sort((a, b) {
      final aAt = DateTime.tryParse(a.keptAt ?? '');
      final bAt = DateTime.tryParse(b.keptAt ?? '');
      if (aAt != null && bAt != null) {
        final byDate = aAt.compareTo(bAt);
        return byDate != 0
            ? byDate
            : _referenceId(a).compareTo(_referenceId(b));
      }
      if (aAt == null && bAt == null) {
        return _referenceId(a).compareTo(_referenceId(b));
      }
      return aAt == null ? 1 : -1;
    });
    return sorted;
  }

  String _referenceId(FavoriteItem item) => item.revealId ?? item.id;

  String _buildJson({
    required List<FavoriteItem> sorted,
    required String? journalOwnerName,
    required DateTime exportedAt,
  }) {
    final kept = sorted
        .map((item) => {
              'recordId': item.id,
              'revealId': item.revealId,
              'wisdomText': item.text,
              'keptAt': item.keptAt,
            })
        .toList();

    final reflections = sorted
        .where((item) => item.hasReflection)
        .map((item) => {
              'recordId': item.id,
              'revealId': item.revealId,
              'reflectionText': item.reflection,
              'reflectedAt': item.reflectedAt,
            })
        .toList();

    final document = {
      'format': formatName,
      'version': schemaVersion,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'journalOwnerName': journalOwnerName,
      'kept': kept,
      'reflections': reflections,
    };

    return const JsonEncoder.withIndent('  ').convert(document);
  }

  String _buildTxt({
    required List<FavoriteItem> sorted,
    required String? journalOwnerName,
    required DateTime exportedAt,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('EAST.');
    buffer.writeln('Data Export');
    buffer.writeln();
    buffer.writeln('Exported: ${formatFavoriteDisplayDate(exportedAt)}');
    if (journalOwnerName != null) {
      buffer.writeln('For: $journalOwnerName');
    }
    buffer.writeln();
    buffer.writeln(_divider);

    for (final item in sorted) {
      buffer.writeln();
      buffer.writeln('[${item.date}]');
      buffer.writeln();
      buffer.writeln(item.text);

      if (item.hasReflection) {
        buffer.writeln();
        buffer.writeln('Reflection:');
        buffer.writeln(item.reflection);
      }

      // Unobtrusive machine/reference metadata only -- never part of the
      // main prose above.
      buffer.writeln();
      buffer.writeln('Reference: ${_referenceId(item)}');
      buffer.writeln();
      buffer.writeln(_divider);
    }

    return buffer.toString();
  }

  String _dateStamp(DateTime exportedAt) {
    final local = exportedAt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
