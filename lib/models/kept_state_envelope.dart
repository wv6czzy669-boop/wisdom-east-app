import 'dart:convert';

import 'kept_record.dart';

/// The Phase 3A protected-state envelope: the single authoritative
/// collection of active Kept records.
///
/// Phase 3A intentionally serializes only [activeRecords]. Later ADR-007
/// phases add `dataEpoch`, `pendingUndoDeletions`, `tombstones`, `outbox`,
/// `syncMetadata`, and `pendingEpochCleanup` as additive top-level JSON
/// fields — their absence here does not require a destructive migration
/// later, since [decode] already ignores unknown top-level keys and a
/// future decoder will simply default them when reading an
/// envelope written by this Phase 3A code.
class KeptStateEnvelope {
  KeptStateEnvelope({
    List<KeptRecord> activeRecords = const [],
  }) : activeRecords = List.unmodifiable(activeRecords) {
    _validate(this.activeRecords);
  }

  static const int currentSchemaVersion = 3;

  /// The active Kept record collection, in the exact order provided.
  /// Always unmodifiable — callers must build a new [KeptStateEnvelope] (or
  /// use [copyWith]) to change its contents.
  final List<KeptRecord> activeRecords;

  Map<String, dynamic> encode() => {
        'schemaVersion': currentSchemaVersion,
        'activeRecords':
            activeRecords.map((record) => record.encode()).toList(),
      };

  String encodeString() => jsonEncode(encode());

  static KeptStateEnvelope decode(Map<String, dynamic> data) {
    final schemaVersion = _readInt(data, 'schemaVersion');
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported kept state envelope schema.');
    }

    final rawActiveRecords = data['activeRecords'];
    if (rawActiveRecords is! List) {
      throw const FormatException('Invalid kept state envelope.');
    }

    final activeRecords = <KeptRecord>[];
    for (final rawRecord in rawActiveRecords) {
      if (rawRecord is! Map<String, dynamic>) {
        throw const FormatException('Invalid kept state envelope.');
      }
      activeRecords.add(KeptRecord.decode(rawRecord));
    }

    return KeptStateEnvelope(activeRecords: activeRecords);
  }

  static KeptStateEnvelope decodeString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid kept state envelope.');
    }
    return decode(decoded);
  }

  KeptStateEnvelope copyWith({List<KeptRecord>? activeRecords}) {
    return KeptStateEnvelope(
      activeRecords: activeRecords ?? this.activeRecords,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeptStateEnvelope &&
        _listEquals(other.activeRecords, activeRecords);
  }

  @override
  int get hashCode => Object.hashAll(activeRecords);

  static void _validate(List<KeptRecord> activeRecords) {
    final seenIds = <String>{};
    final seenRevealIds = <String>{};

    for (final record in activeRecords) {
      if (!seenIds.add(record.id)) {
        throw const FormatException(
          'Kept state envelope contains a duplicate record ID.',
        );
      }
      if (!seenRevealIds.add(record.revealId)) {
        throw const FormatException(
          'Kept state envelope contains a duplicate revealId.',
        );
      }
    }
  }

  static bool _listEquals(List<KeptRecord> a, List<KeptRecord> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid kept state envelope.');
  }
}
