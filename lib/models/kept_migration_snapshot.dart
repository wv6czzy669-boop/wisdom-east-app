import 'dart:convert';

final RegExp _canonicalUuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// One raw legacy `favorites` StringList entry, captured verbatim at its
/// original index.
final class KeptMigrationSnapshotEntry {
  const KeptMigrationSnapshotEntry({
    required this.index,
    required this.rawValue,
  });

  final int index;
  final String rawValue;

  Map<String, dynamic> encode() => {
        'index': index,
        'rawValue': rawValue,
      };

  static KeptMigrationSnapshotEntry decode(Map<String, dynamic> data) {
    final index = _readInt(data, 'index');
    final rawValue = _readString(data, 'rawValue');
    return KeptMigrationSnapshotEntry(index: index, rawValue: rawValue);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeptMigrationSnapshotEntry &&
        other.index == index &&
        other.rawValue == rawValue;
  }

  @override
  int get hashCode => Object.hash(index, rawValue);

  static int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid migration snapshot entry.');
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String) return value;
    throw const FormatException('Invalid migration snapshot entry.');
  }
}

/// A durable, protected, byte-exact capture of the entire legacy
/// `favorites` StringList at the moment migration began reading it.
///
/// Once written and verified, this snapshot — not SharedPreferences — is
/// the retry authority for a migration attempt: every retry re-decodes
/// from this frozen snapshot rather than re-reading `favorites`, so a
/// concurrent or interleaved change to SharedPreferences after the
/// snapshot was captured can never change what a retried migration
/// produces.
final class KeptMigrationSnapshot {
  KeptMigrationSnapshot({
    required this.migrationId,
    required DateTime capturedAt,
    required this.legacyKey,
    List<KeptMigrationSnapshotEntry> entries = const [],
  })  : capturedAt = capturedAt.toUtc(),
        entries = List.unmodifiable(entries) {
    _validate(
      migrationId: migrationId,
      legacyKey: legacyKey,
      entries: this.entries,
    );
  }

  static const int currentSchemaVersion = 1;

  /// The only legacy key Build 25 ever used for Kept/Reflection data.
  static const String expectedLegacyKey = 'favorites';

  final String migrationId;
  final DateTime capturedAt;
  final String legacyKey;
  final List<KeptMigrationSnapshotEntry> entries;

  Map<String, dynamic> encode() => {
        'schemaVersion': currentSchemaVersion,
        'migrationId': migrationId,
        'capturedAtMs': capturedAt.millisecondsSinceEpoch,
        'legacyKey': legacyKey,
        'entries': entries.map((entry) => entry.encode()).toList(),
      };

  String encodeString() => jsonEncode(encode());

  static KeptMigrationSnapshot decode(Map<String, dynamic> data) {
    final schemaVersion = _readInt(data, 'schemaVersion');
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported migration snapshot schema.');
    }

    final migrationId = _readString(data, 'migrationId');
    final capturedAtMs = _readInt(data, 'capturedAtMs');
    final legacyKey = _readString(data, 'legacyKey');

    final rawEntries = data['entries'];
    if (rawEntries is! List) {
      throw const FormatException('Invalid migration snapshot.');
    }
    final entries = <KeptMigrationSnapshotEntry>[];
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map<String, dynamic>) {
        throw const FormatException('Invalid migration snapshot entry.');
      }
      entries.add(KeptMigrationSnapshotEntry.decode(rawEntry));
    }

    return KeptMigrationSnapshot(
      migrationId: migrationId,
      capturedAt:
          DateTime.fromMillisecondsSinceEpoch(capturedAtMs, isUtc: true),
      legacyKey: legacyKey,
      entries: entries,
    );
  }

  static KeptMigrationSnapshot decodeString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid migration snapshot.');
    }
    return decode(decoded);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeptMigrationSnapshot &&
        other.migrationId == migrationId &&
        other.capturedAt.isAtSameMomentAs(capturedAt) &&
        other.legacyKey == legacyKey &&
        _listEquals(other.entries, entries);
  }

  @override
  int get hashCode => Object.hash(
        migrationId,
        capturedAt.millisecondsSinceEpoch,
        legacyKey,
        Object.hashAll(entries),
      );

  static bool _listEquals(
    List<KeptMigrationSnapshotEntry> a,
    List<KeptMigrationSnapshotEntry> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static void _validate({
    required String migrationId,
    required String legacyKey,
    required List<KeptMigrationSnapshotEntry> entries,
  }) {
    if (!_canonicalUuidV4Pattern.hasMatch(migrationId)) {
      throw const FormatException('Invalid migration snapshot migrationId.');
    }
    if (legacyKey != expectedLegacyKey) {
      throw const FormatException('Invalid migration snapshot legacyKey.');
    }
    for (var i = 0; i < entries.length; i += 1) {
      if (entries[i].index != i) {
        throw const FormatException(
          'Migration snapshot entries must have contiguous zero-based '
          'indices matching their list order.',
        );
      }
    }
  }

  static int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid migration snapshot.');
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String) return value;
    throw const FormatException('Invalid migration snapshot.');
  }
}
