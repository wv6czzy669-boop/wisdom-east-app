import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/favorite_item.dart';
import '../persistence/file_protection_bridge.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../utils/journal_owner_name_policy.dart';
import 'journal_pdf_builder.dart';

/// A derived Journal publication cache. It is never authoritative user data:
/// a missing, stale, or malformed entry simply causes a fresh local build.
abstract interface class JournalPdfCache {
  Future<JournalPdfPublication?> read(String fingerprint);

  Future<void> write(String fingerprint, JournalPdfPublication publication);
}

/// Deterministic cache identity for every input that can affect PDF bytes.
abstract final class JournalPdfFingerprint {
  static const int renderSchemaVersion = 2;

  static String create({
    required List<FavoriteItem> items,
    required String? ownerName,
    required Locale locale,
    required Brightness brightness,
    required DateTime generatedAt,
  }) {
    // JournalPdfBuilder renders chronologically. Canonicalize the cache input
    // to that same order so a repository refresh that returns the identical
    // records in a different incidental order does not rebuild identical PDF
    // bytes. Equal/unknown timestamps retain their original order because
    // that order genuinely affects the publication in that ambiguous case.
    final indexedItems = items.asMap().entries.toList(growable: false)
      ..sort((a, b) {
        final aKeptAt = _keptAt(a.value);
        final bKeptAt = _keptAt(b.value);
        if (aKeptAt != null && bKeptAt != null) {
          final byTimestamp = aKeptAt.compareTo(bKeptAt);
          if (byTimestamp != 0) return byTimestamp;
        } else if (aKeptAt != bKeptAt) {
          return aKeptAt == null ? -1 : 1;
        }
        return a.key.compareTo(b.key);
      });
    final payload = <String, Object?>{
      'schemaVersion': renderSchemaVersion,
      'publicationYear': generatedAt.year,
      'locale': locale.toLanguageTag(),
      'brightness': brightness.name,
      'ownerName': JournalOwnerNamePolicy.normalize(ownerName),
      'items': <Object?>[
        for (final entry in indexedItems)
          <String, Object?>{
            'id': entry.value.id,
            'revealId': entry.value.revealId,
            'wisdomId': entry.value.wisdomId,
            'text': entry.value.text,
            'date': entry.value.date,
            'reflection': entry.value.reflection,
            'reflectedAt': entry.value.reflectedAt,
            'keptAt': entry.value.keptAt,
          },
      ],
    };
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  static DateTime? _keptAt(FavoriteItem item) {
    final raw = item.keptAt;
    return raw == null ? null : DateTime.tryParse(raw);
  }
}

/// A single protected, content-addressed cache slot in Application Support.
///
/// PDF bytes are written before their manifest. The manifest contains the
/// byte hash and exact VoiceOver page labels, so an interrupted write can
/// never be mistaken for a complete publication. Files are protected with
/// `NSFileProtectionComplete`, matching EAST.'s private persistence layer.
final class ProtectedJournalPdfCache implements JournalPdfCache {
  ProtectedJournalPdfCache({
    Future<Directory> Function()? rootDirectoryProvider,
    FileProtectionBridge? fileProtectionBridge,
    PersistenceOperationCoordinator? operationCoordinator,
    String Function()? tokenFactory,
  })  : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationSupportDirectory,
        _fileProtectionBridge =
            fileProtectionBridge ?? const MethodChannelFileProtectionBridge(),
        _coordinator =
            operationCoordinator ?? PersistenceOperationCoordinator(),
        _tokenFactory = tokenFactory ?? (() => const Uuid().v4());

  static const String resourceKey = 'protected_journal_pdf_cache';
  static const String _directoryName = 'east_journal_pdf_cache';
  static const int _manifestSchemaVersion = 1;

  final Future<Directory> Function() _rootDirectoryProvider;
  final FileProtectionBridge _fileProtectionBridge;
  final PersistenceOperationCoordinator _coordinator;
  final String Function() _tokenFactory;

  @override
  Future<JournalPdfPublication?> read(String fingerprint) {
    return _coordinator.runExclusive<JournalPdfPublication?>(
      resourceKey: resourceKey,
      operation: () async {
        final directory = await _directory();
        final pdf = File('${directory.path}/$fingerprint.pdf');
        final manifest = File('${directory.path}/$fingerprint.json');
        if (!await pdf.exists() || !await manifest.exists()) return null;

        try {
          await _fileProtectionBridge.protectAndVerifyComplete(pdf.path);
          await _fileProtectionBridge.protectAndVerifyComplete(manifest.path);
          final decoded = jsonDecode(await manifest.readAsString());
          if (decoded is! Map<String, Object?> ||
              decoded['schemaVersion'] != _manifestSchemaVersion ||
              decoded['fingerprint'] != fingerprint) {
            throw const FormatException('Invalid Journal cache manifest.');
          }
          final rawLabels = decoded['pageLabels'];
          final expectedHash = decoded['pdfSha256'];
          if (rawLabels is! List ||
              rawLabels.isEmpty ||
              !rawLabels.every((label) => label is String) ||
              expectedHash is! String) {
            throw const FormatException('Invalid Journal cache fields.');
          }
          final bytes = await pdf.readAsBytes();
          if (sha256.convert(bytes).toString() != expectedHash) {
            throw const FormatException('Journal cache checksum mismatch.');
          }
          return JournalPdfPublication(
            bytes: Uint8List.fromList(bytes),
            accessibility: JournalPdfAccessibility(
              pageLabels: rawLabels.cast<String>(),
            ),
          );
        } catch (_) {
          await _deleteBestEffort(pdf);
          await _deleteBestEffort(manifest);
          return null;
        }
      },
    );
  }

  @override
  Future<void> write(
    String fingerprint,
    JournalPdfPublication publication,
  ) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final directory = await _directory();
        final token = _tokenFactory();
        final finalPdf = File('${directory.path}/$fingerprint.pdf');
        final finalManifest = File('${directory.path}/$fingerprint.json');
        final tempPdf = File('${directory.path}/.$fingerprint.$token.pdf');
        final tempManifest =
            File('${directory.path}/.$fingerprint.$token.json');

        try {
          await _writeBytes(tempPdf, publication.bytes);
          final manifest = jsonEncode(<String, Object?>{
            'schemaVersion': _manifestSchemaVersion,
            'fingerprint': fingerprint,
            'pdfSha256': sha256.convert(publication.bytes).toString(),
            'pageLabels': publication.accessibility.pageLabels,
          });
          await _writeText(tempManifest, manifest);

          await _deleteBestEffort(finalPdf);
          await tempPdf.rename(finalPdf.path);
          await _fileProtectionBridge.protectAndVerifyComplete(finalPdf.path);
          await _deleteBestEffort(finalManifest);
          await tempManifest.rename(finalManifest.path);
          await _fileProtectionBridge
              .protectAndVerifyComplete(finalManifest.path);
          await _removeOtherEntries(directory, fingerprint);
        } finally {
          await _deleteBestEffort(tempPdf);
          await _deleteBestEffort(tempManifest);
        }
      },
    );
  }

  Future<Directory> _directory() async {
    final root = await _rootDirectoryProvider();
    final directory = Directory('${root.path}/$_directoryName');
    await directory.create(recursive: true);
    await _fileProtectionBridge.protectAndVerifyComplete(directory.path);
    return directory;
  }

  Future<void> _writeBytes(File file, Uint8List bytes) async {
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
    await _fileProtectionBridge.protectAndVerifyComplete(file.path);
  }

  Future<void> _writeText(File file, String value) async {
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.writeString(value);
      await handle.flush();
    } finally {
      await handle.close();
    }
    await _fileProtectionBridge.protectAndVerifyComplete(file.path);
  }

  Future<void> _removeOtherEntries(
    Directory directory,
    String fingerprint,
  ) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name == '$fingerprint.pdf' || name == '$fingerprint.json') {
          continue;
        }
        await _deleteBestEffort(entity);
      }
    } catch (_) {
      // Redundant derived cache files never affect publication correctness.
    }
  }

  Future<void> _deleteBestEffort(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A stale derived file is harmless and will fail validation next read.
    }
  }
}
