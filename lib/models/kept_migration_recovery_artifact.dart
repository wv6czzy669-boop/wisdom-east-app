import 'dart:convert';

final RegExp _canonicalUuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Which step of migration a legacy entry failed at. Deliberately narrow —
/// this is not a general error taxonomy, only the three ways a legacy
/// `favorites` entry can fail to become an active [KeptRecord].
enum KeptMigrationFailureStage { decode, convert, duplicateIdentity }

/// One legacy entry that could not become an active Kept record, with a
/// safe, content-free reason. Never carries an exception's `toString()` or
/// a stack trace — only a stable [reasonCode].
final class KeptMigrationRecoveryEntry {
  const KeptMigrationRecoveryEntry({
    required this.index,
    required this.rawValue,
    required this.stage,
    required this.reasonCode,
  });

  final int index;
  final String rawValue;
  final KeptMigrationFailureStage stage;
  final String reasonCode;

  Map<String, dynamic> encode() => {
        'index': index,
        'rawValue': rawValue,
        'stage': _encodeStage(stage),
        'reasonCode': reasonCode,
      };

  static KeptMigrationRecoveryEntry decode(Map<String, dynamic> data) {
    final index = _readInt(data, 'index');
    final rawValue = _readString(data, 'rawValue');
    final stage = _decodeStage(_readString(data, 'stage'));
    final reasonCode = _readString(data, 'reasonCode');
    return KeptMigrationRecoveryEntry(
      index: index,
      rawValue: rawValue,
      stage: stage,
      reasonCode: reasonCode,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeptMigrationRecoveryEntry &&
        other.index == index &&
        other.rawValue == rawValue &&
        other.stage == stage &&
        other.reasonCode == reasonCode;
  }

  @override
  int get hashCode => Object.hash(index, rawValue, stage, reasonCode);

  static String _encodeStage(KeptMigrationFailureStage stage) {
    switch (stage) {
      case KeptMigrationFailureStage.decode:
        return 'decode';
      case KeptMigrationFailureStage.convert:
        return 'convert';
      case KeptMigrationFailureStage.duplicateIdentity:
        return 'duplicateIdentity';
    }
  }

  static KeptMigrationFailureStage _decodeStage(String value) {
    switch (value) {
      case 'decode':
        return KeptMigrationFailureStage.decode;
      case 'convert':
        return KeptMigrationFailureStage.convert;
      case 'duplicateIdentity':
        return KeptMigrationFailureStage.duplicateIdentity;
      default:
        throw const FormatException('Invalid migration recovery stage.');
    }
  }

  static int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid migration recovery entry.');
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String) return value;
    throw const FormatException('Invalid migration recovery entry.');
  }
}

/// A durable, protected record of every legacy `favorites` entry that could
/// not safely become part of the migrated active-record set — because it
/// failed to decode, failed to convert into a valid [KeptRecord], or
/// conflicted with another entry's identity.
///
/// No corrupt legacy item is ever silently discarded: every one of them
/// appears exactly once in [corruptEntries], byte-exact in [rawValue].
final class KeptMigrationRecoveryArtifact {
  KeptMigrationRecoveryArtifact({
    required this.migrationId,
    required DateTime createdAt,
    required this.legacyEntryCount,
    required this.usableEntryCount,
    List<KeptMigrationRecoveryEntry> corruptEntries = const [],
  })  : createdAt = createdAt.toUtc(),
        corruptEntries = List.unmodifiable(corruptEntries) {
    _validate(
      migrationId: migrationId,
      legacyEntryCount: legacyEntryCount,
      usableEntryCount: usableEntryCount,
      corruptEntries: this.corruptEntries,
    );
  }

  static const int currentSchemaVersion = 1;

  final String migrationId;
  final DateTime createdAt;
  final int legacyEntryCount;
  final int usableEntryCount;
  final List<KeptMigrationRecoveryEntry> corruptEntries;

  Map<String, dynamic> encode() => {
        'schemaVersion': currentSchemaVersion,
        'migrationId': migrationId,
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        'legacyEntryCount': legacyEntryCount,
        'usableEntryCount': usableEntryCount,
        'corruptEntries': corruptEntries.map((e) => e.encode()).toList(),
      };

  String encodeString() => jsonEncode(encode());

  static KeptMigrationRecoveryArtifact decode(Map<String, dynamic> data) {
    final schemaVersion = _readInt(data, 'schemaVersion');
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported migration recovery schema.');
    }

    final migrationId = _readString(data, 'migrationId');
    final createdAtMs = _readInt(data, 'createdAtMs');
    final legacyEntryCount = _readInt(data, 'legacyEntryCount');
    final usableEntryCount = _readInt(data, 'usableEntryCount');

    final rawEntries = data['corruptEntries'];
    if (rawEntries is! List) {
      throw const FormatException('Invalid migration recovery artifact.');
    }
    final corruptEntries = <KeptMigrationRecoveryEntry>[];
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map<String, dynamic>) {
        throw const FormatException('Invalid migration recovery entry.');
      }
      corruptEntries.add(KeptMigrationRecoveryEntry.decode(rawEntry));
    }

    return KeptMigrationRecoveryArtifact(
      migrationId: migrationId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true),
      legacyEntryCount: legacyEntryCount,
      usableEntryCount: usableEntryCount,
      corruptEntries: corruptEntries,
    );
  }

  static KeptMigrationRecoveryArtifact decodeString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid migration recovery artifact.');
    }
    return decode(decoded);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeptMigrationRecoveryArtifact &&
        other.migrationId == migrationId &&
        other.createdAt.isAtSameMomentAs(createdAt) &&
        other.legacyEntryCount == legacyEntryCount &&
        other.usableEntryCount == usableEntryCount &&
        _listEquals(other.corruptEntries, corruptEntries);
  }

  @override
  int get hashCode => Object.hash(
        migrationId,
        createdAt.millisecondsSinceEpoch,
        legacyEntryCount,
        usableEntryCount,
        Object.hashAll(corruptEntries),
      );

  static bool _listEquals(
    List<KeptMigrationRecoveryEntry> a,
    List<KeptMigrationRecoveryEntry> b,
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
    required int legacyEntryCount,
    required int usableEntryCount,
    required List<KeptMigrationRecoveryEntry> corruptEntries,
  }) {
    if (!_canonicalUuidV4Pattern.hasMatch(migrationId)) {
      throw const FormatException('Invalid migration recovery migrationId.');
    }
    if (legacyEntryCount < 0 || usableEntryCount < 0) {
      throw const FormatException(
        'Migration recovery counts cannot be negative.',
      );
    }
    if (usableEntryCount + corruptEntries.length != legacyEntryCount) {
      throw const FormatException(
        'Migration recovery usable/corrupt counts must sum to the legacy '
        'count.',
      );
    }
    final seenIndices = <int>{};
    for (final entry in corruptEntries) {
      if (!seenIndices.add(entry.index)) {
        throw const FormatException(
          'Migration recovery artifact contains a duplicate entry index.',
        );
      }
      if (entry.reasonCode.trim().isEmpty) {
        throw const FormatException(
          'Migration recovery entry reasonCode cannot be blank.',
        );
      }
    }
  }

  static int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid migration recovery artifact.');
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String) return value;
    throw const FormatException('Invalid migration recovery artifact.');
  }
}
