/// Build 26 Phase 4E-1: the one versioned envelope
/// `ProtectedLocalSyncIntentStore` persists as a whole -- the durable
/// collection of every not-yet-resolved [LocalSyncIntent].
library;

import 'dart:convert';

import 'local_sync_intent.dart';

/// The complete, versioned local-sync-intent envelope.
///
/// At most one pending intent may exist per deterministic record name at a
/// time -- supersession (handled by `LocalSyncIntentStore.enqueueIntent`)
/// always overwrites the existing entry for that record rather than adding
/// a second one, mirroring `AccountSyncState`'s own outbox invariant
/// exactly. This envelope's own [_validate] enforces that structurally, so
/// a corrupted on-disk file that somehow violated it can never be silently
/// accepted.
final class LocalSyncIntentEnvelope {
  factory LocalSyncIntentEnvelope({List<LocalSyncIntent> intents = const []}) {
    _validate(intents);
    return LocalSyncIntentEnvelope._(intents: List.unmodifiable(intents));
  }

  const LocalSyncIntentEnvelope._({required this.intents});

  factory LocalSyncIntentEnvelope.empty() => LocalSyncIntentEnvelope();

  static const int currentSchemaVersion = 1;

  /// Every currently-pending intent, in deterministic order: a new intent
  /// is appended at the end; a supersession overwrites its predecessor's
  /// exact position rather than moving to the end.
  final List<LocalSyncIntent> intents;

  LocalSyncIntentEnvelope copyWith({List<LocalSyncIntent>? intents}) {
    return LocalSyncIntentEnvelope(intents: intents ?? this.intents);
  }

  Map<String, dynamic> encode() => {
        'schemaVersion': currentSchemaVersion,
        'intents': intents.map((intent) => intent.encode()).toList(),
      };

  String encodeString() => jsonEncode(encode());

  static LocalSyncIntentEnvelope decode(Map<String, dynamic> data) {
    const allowedKeys = {'schemaVersion', 'intents'};
    for (final key in data.keys) {
      if (!allowedKeys.contains(key)) {
        throw const FormatException(
          'Unrecognized top-level key in local sync intent envelope.',
        );
      }
    }

    final schemaVersion = data['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != currentSchemaVersion) {
      throw const FormatException(
        'Unsupported local sync intent envelope schema.',
      );
    }

    final rawIntents = data['intents'];
    if (rawIntents is! List) {
      throw const FormatException('Invalid local sync intent envelope.');
    }

    final intents = <LocalSyncIntent>[];
    for (final rawIntent in rawIntents) {
      if (rawIntent is! Map<Object?, Object?>) {
        throw const FormatException('Invalid local sync intent envelope.');
      }
      final intent = LocalSyncIntent.tryDecode(rawIntent);
      if (intent == null) {
        throw const FormatException('Invalid local sync intent envelope.');
      }
      intents.add(intent);
    }

    return LocalSyncIntentEnvelope(intents: intents);
  }

  static LocalSyncIntentEnvelope decodeString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid local sync intent envelope.');
    }
    return decode(decoded);
  }

  static void _validate(List<LocalSyncIntent> intents) {
    final seenIntentIds = <String>{};
    final seenRecordNames = <String>{};
    for (final intent in intents) {
      if (!seenIntentIds.add(intent.intentId)) {
        throw const FormatException(
          'Local sync intent envelope contains a duplicate intentId.',
        );
      }
      if (!seenRecordNames.add(intent.recordName)) {
        throw const FormatException(
          'Local sync intent envelope contains more than one pending '
          'intent for the same record.',
        );
      }
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalSyncIntentEnvelope &&
        _listEquals(other.intents, intents);
  }

  @override
  int get hashCode => Object.hashAll(intents);

  static bool _listEquals(List<LocalSyncIntent> a, List<LocalSyncIntent> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
