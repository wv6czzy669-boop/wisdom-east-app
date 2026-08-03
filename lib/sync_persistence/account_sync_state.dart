/// Build 26 Phase 4D-1: the durable, per-account-fingerprint sync state --
/// the local counterpart of ADR-007's Local state envelope `syncMetadata`
/// and `outbox` concepts, and of
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §6's "the zone's server
/// change token... persisted in `syncMetadata`".
///
/// Scoped by an opaque CloudKit account fingerprint (see
/// `CloudKitAccountSnapshot.accountFingerprint`, Phase 4B-1) -- never a raw
/// CloudKit user identifier, never derived from email/Apple ID/device name.
/// This type itself carries no fingerprint value; the fingerprint is only
/// ever used as a lookup key one layer up
/// (`sync_persistence_envelope.dart`), so nothing in this file can leak it
/// into a diagnostic string by accident.
library;

import '../sync/data_epoch.dart';
import 'persisted_outbox_mutation.dart';

/// Thrown by [AccountSyncState]'s constructor when the given fields would
/// violate one of this type's structural invariants (see the constructor's
/// own doc comment). Never thrown by [AccountSyncState.tryDecode], which
/// reports the same class of problem by returning `null` instead, per this
/// codebase's fail-closed `tryParse`/`tryDecode` convention.
class AccountSyncStateFormatException implements Exception {
  const AccountSyncStateFormatException(this.message);

  final String message;

  @override
  String toString() => 'AccountSyncStateFormatException: $message';
}

/// Loosely validates that a string "looks like" an opaque Base64 payload --
/// deliberately shallow. This store never decodes or interprets a server
/// token or a record's system fields; it only refuses to persist a value
/// that could not possibly be the opaque Base64 string the native transport
/// (Phase 4C-2, `CloudKitOpaqueArchive.swift`) actually produces.
bool looksLikeOpaqueBase64(String value) {
  if (value.isEmpty) return false;
  return RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(value);
}

/// A conservative shape check for a `CKKeptWisdom` record name -- the
/// `east-kept-<uuid>` form `deriveKeptWisdomRecordName` produces
/// (`lib/sync/sync_record_identity.dart`). Kept intentionally local to this
/// storage layer (not a call into `sync_record_identity.dart` itself) since
/// this is a defensive wire-shape check on already-derived strings being
/// read back from disk, not a fresh derivation.
final RegExp _keptWisdomRecordNamePattern = RegExp(
  r'^east-kept-[0-9a-f]{8}-[0-9a-f]{4}-[45][0-9a-f]{3}-[89ab][0-9a-f]{3}-'
  r'[0-9a-f]{12}$',
  caseSensitive: false,
);

bool looksLikeKeptWisdomRecordName(String value) =>
    _keptWisdomRecordNamePattern.hasMatch(value);

/// One account's complete durable sync state: the authoritative
/// account-scoped [dataEpoch], the opaque server change token, opaque
/// per-record system fields, and the durable outbox.
///
/// **Correction round:** [dataEpoch] is now a mandatory field of every
/// account bucket -- reusing exactly the `DataEpoch` type and validation
/// already established by the Phase 4A sync projections
/// (`CloudKeptWisdomProjection.dataEpoch`, `CloudEastSyncStateProjection
/// .dataEpoch`) and `SyncChange` (via its projection), never a new epoch
/// type or normalization rule. There is no default: constructing or
/// decoding an `AccountSyncState` without one fails closed (see the
/// constructor and [tryDecode] below). Every queued outbox mutation must
/// carry the *same* `dataEpoch` as this bucket -- enforced structurally by
/// [_validate], so a mismatched mutation can never even be constructed into
/// a valid [AccountSyncState], let alone persisted or decoded.
///
/// Immutable. Every mutating operation (`copyWith` or a
/// `SyncPersistenceStore` method) produces a new instance rather than
/// mutating this one in place -- consistent with `KeptStateEnvelope` and
/// every other envelope-shaped value type in this codebase. [copyWith]
/// deliberately exposes no way to change [dataEpoch] -- every convenience
/// mutation (clearing the token, applying mutation outcomes, replacing
/// system fields) therefore preserves it automatically, by construction,
/// never by a caller remembering to pass it through. Only building a whole
/// new [AccountSyncState] from scratch (a genuine epoch reset, out of this
/// phase's scope) can ever change it.
final class AccountSyncState {
  factory AccountSyncState({
    required DataEpoch dataEpoch,
    String? serverChangeToken,
    Map<String, String> recordSystemFields = const {},
    List<PersistedOutboxMutation> outbox = const [],
  }) {
    _validate(
      dataEpoch: dataEpoch,
      serverChangeToken: serverChangeToken,
      recordSystemFields: recordSystemFields,
      outbox: outbox,
    );
    return AccountSyncState._(
      dataEpoch: dataEpoch,
      serverChangeToken: serverChangeToken,
      recordSystemFields: Map.unmodifiable(recordSystemFields),
      outbox: List.unmodifiable(outbox),
    );
  }

  const AccountSyncState._({
    required this.dataEpoch,
    required this.serverChangeToken,
    required this.recordSystemFields,
    required this.outbox,
  });

  /// The empty state a never-yet-synced account starts from, under the
  /// given, already-known-valid [dataEpoch]. There is no zero-argument
  /// `empty()` any more -- account-bucket creation always requires an
  /// explicit epoch (see the class doc comment); this factory only removes
  /// the boilerplate of specifying empty token/fields/outbox alongside it.
  /// A `null` [serverChangeToken] means "initial fetch" -- see
  /// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §12.2 row 5.
  factory AccountSyncState.empty(DataEpoch dataEpoch) =>
      AccountSyncState(dataEpoch: dataEpoch);

  /// The authoritative epoch this account bucket -- and every mutation
  /// queued inside it -- belongs to. See the class doc comment.
  final DataEpoch dataEpoch;

  /// Opaque, transport-produced server change token, exactly as returned by
  /// `fetchPrivateZoneChanges` (Phase 4C-2) -- never decoded, interpreted,
  /// normalized, or re-encoded by this store. `null` means no successful
  /// fetch has ever completed for this account -- the next fetch must be an
  /// initial one (`previousServerToken: null`).
  final String? serverChangeToken;

  /// Opaque, per-record CloudKit "system fields" blobs (Phase 4C-2's
  /// `CloudKitRecordModifyOutcome.systemFields` /
  /// `CloudKitRecordChangeInput.previousSystemFields`), keyed by the
  /// deterministic CloudKit record name they belong to. Never decoded,
  /// never associated by wisdom text.
  final Map<String, String> recordSystemFields;

  /// The durable, not-yet-fully-acknowledged outbound mutation queue, in
  /// deterministic enqueue order.
  final List<PersistedOutboxMutation> outbox;

  /// Deliberately has no `dataEpoch` parameter -- see the class doc comment.
  /// Every other field defaults to "unchanged" exactly as before.
  AccountSyncState copyWith({
    Object? serverChangeToken = _unset,
    Map<String, String>? recordSystemFields,
    List<PersistedOutboxMutation>? outbox,
  }) {
    return AccountSyncState(
      dataEpoch: dataEpoch,
      serverChangeToken: identical(serverChangeToken, _unset)
          ? this.serverChangeToken
          : serverChangeToken as String?,
      recordSystemFields: recordSystemFields ?? this.recordSystemFields,
      outbox: outbox ?? this.outbox,
    );
  }

  /// Encodes this state into the loosely-typed `Map` shape the sync-state
  /// envelope's JSON file stores. [dataEpoch] is always present -- there is
  /// no "absent means default" case for this field.
  Map<String, Object?> encode() => {
        'dataEpoch': dataEpoch.value,
        if (serverChangeToken != null) 'serverChangeToken': serverChangeToken,
        'recordSystemFields': recordSystemFields,
        'outbox': outbox.map((entry) => entry.encode()).toList(),
      };

  /// Strictly parses one raw account-state map. Returns `null` for anything
  /// malformed -- an unrecognized key, a **missing or malformed
  /// `dataEpoch`** (mandatory; never defaulted), a token or system-field
  /// value that does not look like opaque Base64, a record name that does
  /// not look like a real `CKKeptWisdom` record name, a duplicate outbox
  /// `mutationId`, a duplicate outbox `recordName`, an outbox mutation whose
  /// own `dataEpoch` does not match this bucket's `dataEpoch`, or any outbox
  /// entry [PersistedOutboxMutation.tryDecode] itself rejects. Never throws.
  static AccountSyncState? tryDecode(Map<Object?, Object?> raw) {
    const allowedKeys = {
      'dataEpoch',
      'serverChangeToken',
      'recordSystemFields',
      'outbox',
    };
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) return null;
    }

    // Mandatory, never defaulted: a missing or malformed dataEpoch fails the
    // whole account-state decode closed.
    final dataEpochValue = raw['dataEpoch'];
    if (dataEpochValue is! String || !DataEpoch.isValid(dataEpochValue)) {
      return null;
    }
    final dataEpoch = DataEpoch.parse(dataEpochValue);

    final tokenValue = raw['serverChangeToken'];
    if (tokenValue != null) {
      if (tokenValue is! String || !looksLikeOpaqueBase64(tokenValue)) {
        return null;
      }
    }

    final rawSystemFields = raw['recordSystemFields'];
    if (rawSystemFields != null && rawSystemFields is! Map) return null;
    final recordSystemFields = <String, String>{};
    if (rawSystemFields is Map) {
      for (final entry in rawSystemFields.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || !looksLikeKeptWisdomRecordName(key)) {
          return null;
        }
        if (value is! String || !looksLikeOpaqueBase64(value)) return null;
        recordSystemFields[key] = value;
      }
    }

    final rawOutbox = raw['outbox'];
    if (rawOutbox != null && rawOutbox is! List) return null;
    final outbox = <PersistedOutboxMutation>[];
    if (rawOutbox is List) {
      for (final rawEntry in rawOutbox) {
        if (rawEntry is! Map<Object?, Object?>) return null;
        final entry = PersistedOutboxMutation.tryDecode(rawEntry);
        if (entry == null) return null;
        outbox.add(entry);
      }
    }

    try {
      return AccountSyncState(
        dataEpoch: dataEpoch,
        serverChangeToken: tokenValue as String?,
        recordSystemFields: recordSystemFields,
        outbox: outbox,
      );
    } on AccountSyncStateFormatException {
      return null;
    }
  }

  static void _validate({
    required DataEpoch dataEpoch,
    required String? serverChangeToken,
    required Map<String, String> recordSystemFields,
    required List<PersistedOutboxMutation> outbox,
  }) {
    if (serverChangeToken != null &&
        !looksLikeOpaqueBase64(serverChangeToken)) {
      throw const AccountSyncStateFormatException(
        'serverChangeToken does not look like an opaque transport token.',
      );
    }

    for (final entry in recordSystemFields.entries) {
      if (!looksLikeKeptWisdomRecordName(entry.key)) {
        throw const AccountSyncStateFormatException(
          'recordSystemFields contains a key that is not a valid record '
          'name.',
        );
      }
      if (!looksLikeOpaqueBase64(entry.value)) {
        throw const AccountSyncStateFormatException(
          'recordSystemFields contains a value that is not opaque Base64.',
        );
      }
    }

    final seenMutationIds = <String>{};
    final seenRecordNames = <String>{};
    for (final entry in outbox) {
      if (!seenMutationIds.add(entry.mutationId)) {
        throw const AccountSyncStateFormatException(
          'Outbox contains a duplicate mutationId.',
        );
      }
      if (!seenRecordNames.add(entry.recordName)) {
        throw const AccountSyncStateFormatException(
          'Outbox contains more than one pending mutation for the same '
          'record name.',
        );
      }
      if (entry.change.projection.dataEpoch != dataEpoch) {
        throw const AccountSyncStateFormatException(
          'An outbox mutation dataEpoch does not match the account '
          'dataEpoch.',
        );
      }
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AccountSyncState &&
        other.dataEpoch == dataEpoch &&
        other.serverChangeToken == serverChangeToken &&
        _mapEquals(other.recordSystemFields, recordSystemFields) &&
        _listEquals(other.outbox, outbox);
  }

  @override
  int get hashCode => Object.hash(
        dataEpoch,
        serverChangeToken,
        Object.hashAllUnordered(
          recordSystemFields.entries.map((e) => Object.hash(e.key, e.value)),
        ),
        Object.hashAll(outbox),
      );

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _listEquals(
    List<PersistedOutboxMutation> a,
    List<PersistedOutboxMutation> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Sentinel used only to distinguish "argument omitted" from "argument
/// explicitly passed as `null`" in [AccountSyncState.copyWith].
const Object _unset = Object();
