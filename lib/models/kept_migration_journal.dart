import 'dart:convert';

/// Canonical RFC 4122 UUID v4 shape only. A [KeptMigrationJournal.migrationId]
/// is always freshly minted per migration attempt (never a deterministic
/// v5 identity), so only v4 is accepted here — unlike the combined v4/v5
/// pattern `KeptRecord` accepts for `revealId`/`mutationId`.
final RegExp _canonicalUuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// The three states a persisted Build 25 -> Build 26 Kept-storage migration
/// journal may encode. `notStarted` is deliberately not a member of this
/// enum — it is represented by the complete absence of a journal record,
/// never by a stored value.
enum KeptMigrationState { writing, verified, complete }

/// Durable, crash-safe progress record for the Build 25 `favorites` ->
/// protected Kept-state migration.
///
/// This journal is the migration's own state machine checkpoint — separate
/// from the pre-migration snapshot (the retry authority for legacy data)
/// and the recovery artifact (undecodable/conflicting entries). It never
/// carries wisdom text, reflection text, or raw legacy values; only
/// counts, file names, timestamps, and identifiers.
final class KeptMigrationJournal {
  KeptMigrationJournal({
    required this.state,
    required this.migrationId,
    required DateTime startedAt,
    required DateTime updatedAt,
    this.legacyEntryCount,
    this.usableEntryCount,
    this.corruptEntryCount,
    this.snapshotFileName,
    this.recoveryFileName,
  })  : startedAt = startedAt.toUtc(),
        updatedAt = updatedAt.toUtc() {
    _validate(
      state: state,
      migrationId: migrationId,
      legacyEntryCount: legacyEntryCount,
      usableEntryCount: usableEntryCount,
      corruptEntryCount: corruptEntryCount,
      snapshotFileName: snapshotFileName,
      recoveryFileName: recoveryFileName,
    );
  }

  static const int currentSchemaVersion = 1;

  final KeptMigrationState state;
  final String migrationId;
  final DateTime startedAt;
  final DateTime updatedAt;
  final int? legacyEntryCount;
  final int? usableEntryCount;
  final int? corruptEntryCount;
  final String? snapshotFileName;
  final String? recoveryFileName;

  KeptMigrationJournal copyWith({
    KeptMigrationState? state,
    DateTime? updatedAt,
    int? legacyEntryCount,
    int? usableEntryCount,
    int? corruptEntryCount,
    String? snapshotFileName,
    String? recoveryFileName,
  }) {
    return KeptMigrationJournal(
      state: state ?? this.state,
      migrationId: migrationId,
      startedAt: startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      legacyEntryCount: legacyEntryCount ?? this.legacyEntryCount,
      usableEntryCount: usableEntryCount ?? this.usableEntryCount,
      corruptEntryCount: corruptEntryCount ?? this.corruptEntryCount,
      snapshotFileName: snapshotFileName ?? this.snapshotFileName,
      recoveryFileName: recoveryFileName ?? this.recoveryFileName,
    );
  }

  Map<String, dynamic> encode() => {
        'schemaVersion': currentSchemaVersion,
        'state': _encodeState(state),
        'migrationId': migrationId,
        'startedAtMs': startedAt.millisecondsSinceEpoch,
        'updatedAtMs': updatedAt.millisecondsSinceEpoch,
        if (legacyEntryCount != null) 'legacyEntryCount': legacyEntryCount,
        if (usableEntryCount != null) 'usableEntryCount': usableEntryCount,
        if (corruptEntryCount != null) 'corruptEntryCount': corruptEntryCount,
        if (snapshotFileName != null) 'snapshotFileName': snapshotFileName,
        if (recoveryFileName != null) 'recoveryFileName': recoveryFileName,
      };

  String encodeString() => jsonEncode(encode());

  static KeptMigrationJournal decode(Map<String, dynamic> data) {
    final schemaVersion = _readInt(data, 'schemaVersion');
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported migration journal schema.');
    }

    final state = _decodeState(_readString(data, 'state'));
    final migrationId = _readString(data, 'migrationId');
    final startedAtMs = _readInt(data, 'startedAtMs');
    final updatedAtMs = _readInt(data, 'updatedAtMs');
    final legacyEntryCount = _readOptionalInt(data, 'legacyEntryCount');
    final usableEntryCount = _readOptionalInt(data, 'usableEntryCount');
    final corruptEntryCount = _readOptionalInt(data, 'corruptEntryCount');
    final snapshotFileName = _readOptionalString(data, 'snapshotFileName');
    final recoveryFileName = _readOptionalString(data, 'recoveryFileName');

    return KeptMigrationJournal(
      state: state,
      migrationId: migrationId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAtMs, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs, isUtc: true),
      legacyEntryCount: legacyEntryCount,
      usableEntryCount: usableEntryCount,
      corruptEntryCount: corruptEntryCount,
      snapshotFileName: snapshotFileName,
      recoveryFileName: recoveryFileName,
    );
  }

  static KeptMigrationJournal decodeString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid migration journal.');
    }
    return decode(decoded);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeptMigrationJournal &&
        other.state == state &&
        other.migrationId == migrationId &&
        other.startedAt.isAtSameMomentAs(startedAt) &&
        other.updatedAt.isAtSameMomentAs(updatedAt) &&
        other.legacyEntryCount == legacyEntryCount &&
        other.usableEntryCount == usableEntryCount &&
        other.corruptEntryCount == corruptEntryCount &&
        other.snapshotFileName == snapshotFileName &&
        other.recoveryFileName == recoveryFileName;
  }

  @override
  int get hashCode => Object.hash(
        state,
        migrationId,
        startedAt.millisecondsSinceEpoch,
        updatedAt.millisecondsSinceEpoch,
        legacyEntryCount,
        usableEntryCount,
        corruptEntryCount,
        snapshotFileName,
        recoveryFileName,
      );

  static String _encodeState(KeptMigrationState state) {
    switch (state) {
      case KeptMigrationState.writing:
        return 'writing';
      case KeptMigrationState.verified:
        return 'verified';
      case KeptMigrationState.complete:
        return 'complete';
    }
  }

  static KeptMigrationState _decodeState(String value) {
    switch (value) {
      case 'writing':
        return KeptMigrationState.writing;
      case 'verified':
        return KeptMigrationState.verified;
      case 'complete':
        return KeptMigrationState.complete;
      default:
        throw const FormatException('Invalid migration journal state.');
    }
  }

  static void _validate({
    required KeptMigrationState state,
    required String migrationId,
    required int? legacyEntryCount,
    required int? usableEntryCount,
    required int? corruptEntryCount,
    required String? snapshotFileName,
    required String? recoveryFileName,
  }) {
    if (!_canonicalUuidV4Pattern.hasMatch(migrationId)) {
      throw const FormatException('Invalid migration journal migrationId.');
    }
    for (final count in [
      legacyEntryCount,
      usableEntryCount,
      corruptEntryCount
    ]) {
      if (count != null && count < 0) {
        throw const FormatException(
            'Migration journal counts cannot be negative.');
      }
    }
    if (legacyEntryCount != null &&
        usableEntryCount != null &&
        corruptEntryCount != null &&
        usableEntryCount + corruptEntryCount != legacyEntryCount) {
      throw const FormatException(
        'Migration journal usable/corrupt counts must sum to the legacy count.',
      );
    }
    if (corruptEntryCount == 0 && recoveryFileName != null) {
      throw const FormatException(
        'Migration journal cannot reference a recovery file with zero corrupt entries.',
      );
    }
    if (corruptEntryCount != null &&
        corruptEntryCount > 0 &&
        recoveryFileName == null) {
      throw const FormatException(
        'Migration journal with corrupt entries must reference a recovery file.',
      );
    }

    if (state == KeptMigrationState.writing) {
      return; // Partial metadata is explicitly allowed while writing.
    }

    // verified and complete both require the full metadata set.
    if (legacyEntryCount == null ||
        usableEntryCount == null ||
        corruptEntryCount == null ||
        snapshotFileName == null) {
      throw const FormatException(
        'Verified/complete migration journal is missing required metadata.',
      );
    }
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String) return value;
    throw const FormatException('Invalid migration journal.');
  }

  static String? _readOptionalString(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;
    final value = data[key];
    if (value is String) return value;
    throw const FormatException('Invalid migration journal.');
  }

  static int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid migration journal.');
  }

  static int? _readOptionalInt(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;
    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid migration journal.');
  }
}
