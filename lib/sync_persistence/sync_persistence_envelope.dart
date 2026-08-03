/// Build 26 Phase 4D-1: the one versioned, account-scoped local sync-state
/// envelope this phase's protected store persists as a whole.
///
/// **Deliberate, disclosed refinement of ADR-007's original sketch** (same
/// class of documented supersession as
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §0's `recordName`
/// derivation change): ADR-007's Local state envelope originally described
/// `outbox` and `syncMetadata` as additive top-level fields of the *same*
/// `east_kept_state_v3.json` file `KeptStateEnvelope` already owns. This
/// phase's own instruction is explicit and newer: keep this state in a
/// **separate** protected store, never inside the existing authoritative
/// Kept envelope, and never altering `KeptStateEnvelope`'s own format. That
/// instruction is followed here, not silently reconciled -- see
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §13.1 for the same note
/// recorded in the authoritative design document.
///
/// This envelope scopes state by an **opaque CloudKit account fingerprint**
/// (`CloudKitAccountSnapshot.accountFingerprint`, Phase 4B-1) so that two
/// fingerprints' state can never mix. The fingerprint is used here only as a
/// `Map` key -- it is never written into a file path, a diagnostic string,
/// or a log line anywhere in this store, precisely so a fingerprint can
/// never leak through this phase's own file-path or stage-name logging
/// (contrast with `ProtectedFileKeptStateStore`, whose directory path is
/// safe to log because it carries no per-account component at all -- this
/// envelope's file path is equally fingerprint-free; only its JSON *content*
/// is scoped by fingerprint, and JSON content is never logged by this
/// codebase's `keptDiagnostic` convention).
library;

import 'dart:convert';

import 'account_sync_state.dart';

/// A conservative shape check for the opaque account fingerprint
/// (`CloudKitAccountFingerprintUtility.fingerprint(for:)`, Phase 4B-1): a
/// namespaced SHA-256 hash, rendered as lowercase hex. This is a defensive
/// wire-shape check only -- this store never interprets what the
/// fingerprint means, only that it has the shape the native bridge actually
/// produces.
final RegExp _accountFingerprintPattern = RegExp(r'^[0-9a-f]{64}$');

bool looksLikeAccountFingerprint(String value) =>
    _accountFingerprintPattern.hasMatch(value);

/// The complete, versioned, multi-account local sync-state envelope.
///
/// Immutable. [accounts] holds every account fingerprint's *active* durable
/// sync state; [quarantinedAccounts] holds fingerprints whose state has been
/// explicitly quarantined (set aside, not destroyed) rather than cleared --
/// see `SyncPersistenceStore.quarantineAccountState`. The two maps are
/// always disjoint: a fingerprint never appears in both at once.
final class SyncPersistenceEnvelope {
  factory SyncPersistenceEnvelope({
    Map<String, AccountSyncState> accounts = const {},
    Map<String, AccountSyncState> quarantinedAccounts = const {},
  }) {
    _validate(accounts: accounts, quarantinedAccounts: quarantinedAccounts);
    return SyncPersistenceEnvelope._(
      accounts: Map.unmodifiable(accounts),
      quarantinedAccounts: Map.unmodifiable(quarantinedAccounts),
    );
  }

  const SyncPersistenceEnvelope._({
    required this.accounts,
    required this.quarantinedAccounts,
  });

  factory SyncPersistenceEnvelope.empty() => SyncPersistenceEnvelope();

  static const int currentSchemaVersion = 1;

  final Map<String, AccountSyncState> accounts;
  final Map<String, AccountSyncState> quarantinedAccounts;

  SyncPersistenceEnvelope copyWith({
    Map<String, AccountSyncState>? accounts,
    Map<String, AccountSyncState>? quarantinedAccounts,
  }) {
    return SyncPersistenceEnvelope(
      accounts: accounts ?? this.accounts,
      quarantinedAccounts: quarantinedAccounts ?? this.quarantinedAccounts,
    );
  }

  /// Returns a copy with [fingerprint]'s active entry set to [state].
  SyncPersistenceEnvelope withAccount(
    String fingerprint,
    AccountSyncState state,
  ) {
    final next = Map<String, AccountSyncState>.from(accounts);
    next[fingerprint] = state;
    final nextQuarantined =
        Map<String, AccountSyncState>.from(quarantinedAccounts)
          ..remove(fingerprint);
    return copyWith(accounts: next, quarantinedAccounts: nextQuarantined);
  }

  /// Returns a copy with [fingerprint] moved from [accounts] into
  /// [quarantinedAccounts] (a no-op producing an equivalent envelope if
  /// [fingerprint] has no active entry).
  SyncPersistenceEnvelope withAccountQuarantined(String fingerprint) {
    final existing = accounts[fingerprint];
    if (existing == null) return this;
    final nextActive = Map<String, AccountSyncState>.from(accounts)
      ..remove(fingerprint);
    final nextQuarantined =
        Map<String, AccountSyncState>.from(quarantinedAccounts);
    nextQuarantined[fingerprint] = existing;
    return copyWith(accounts: nextActive, quarantinedAccounts: nextQuarantined);
  }

  /// Returns a copy with [fingerprint] entirely removed from both
  /// [accounts] and [quarantinedAccounts] -- a genuine, explicit clear, not
  /// a quarantine.
  SyncPersistenceEnvelope withAccountCleared(String fingerprint) {
    final nextActive = Map<String, AccountSyncState>.from(accounts)
      ..remove(fingerprint);
    final nextQuarantined =
        Map<String, AccountSyncState>.from(quarantinedAccounts)
          ..remove(fingerprint);
    return copyWith(accounts: nextActive, quarantinedAccounts: nextQuarantined);
  }

  Map<String, dynamic> encode() => {
        'schemaVersion': currentSchemaVersion,
        'accounts': accounts.map(
          (fingerprint, state) => MapEntry(fingerprint, state.encode()),
        ),
        'quarantinedAccounts': quarantinedAccounts.map(
          (fingerprint, state) => MapEntry(fingerprint, state.encode()),
        ),
      };

  String encodeString() => jsonEncode(encode());

  static SyncPersistenceEnvelope decode(Map<String, dynamic> data) {
    const allowedKeys = {'schemaVersion', 'accounts', 'quarantinedAccounts'};
    for (final key in data.keys) {
      if (!allowedKeys.contains(key)) {
        throw const FormatException(
          'Unrecognized top-level key in sync persistence envelope.',
        );
      }
    }

    final schemaVersion = data['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != currentSchemaVersion) {
      throw const FormatException(
        'Unsupported sync persistence envelope schema.',
      );
    }

    final accounts = _decodeAccountsMap(data['accounts']);
    final quarantinedAccounts = _decodeAccountsMap(data['quarantinedAccounts']);

    for (final fingerprint in accounts.keys) {
      if (quarantinedAccounts.containsKey(fingerprint)) {
        throw const FormatException(
          'A fingerprint cannot be both active and quarantined.',
        );
      }
    }

    return SyncPersistenceEnvelope(
      accounts: accounts,
      quarantinedAccounts: quarantinedAccounts,
    );
  }

  static SyncPersistenceEnvelope decodeString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid sync persistence envelope.');
    }
    return decode(decoded);
  }

  static Map<String, AccountSyncState> _decodeAccountsMap(Object? raw) {
    if (raw == null) return const {};
    if (raw is! Map) {
      throw const FormatException('Invalid sync persistence envelope.');
    }

    final result = <String, AccountSyncState>{};
    for (final entry in raw.entries) {
      final fingerprint = entry.key;
      if (fingerprint is! String || !looksLikeAccountFingerprint(fingerprint)) {
        throw const FormatException(
          'Invalid account fingerprint in sync persistence envelope.',
        );
      }
      final rawState = entry.value;
      if (rawState is! Map<Object?, Object?>) {
        throw const FormatException('Invalid sync persistence envelope.');
      }
      final state = AccountSyncState.tryDecode(rawState);
      if (state == null) {
        throw const FormatException(
          'Invalid account sync state in sync persistence envelope.',
        );
      }
      result[fingerprint] = state;
    }
    return result;
  }

  static void _validate({
    required Map<String, AccountSyncState> accounts,
    required Map<String, AccountSyncState> quarantinedAccounts,
  }) {
    for (final fingerprint in accounts.keys) {
      if (!looksLikeAccountFingerprint(fingerprint)) {
        throw const FormatException(
          'Invalid account fingerprint in sync persistence envelope.',
        );
      }
    }
    for (final fingerprint in quarantinedAccounts.keys) {
      if (!looksLikeAccountFingerprint(fingerprint)) {
        throw const FormatException(
          'Invalid account fingerprint in sync persistence envelope.',
        );
      }
      if (accounts.containsKey(fingerprint)) {
        throw const FormatException(
          'A fingerprint cannot be both active and quarantined.',
        );
      }
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncPersistenceEnvelope &&
        _mapEquals(other.accounts, accounts) &&
        _mapEquals(other.quarantinedAccounts, quarantinedAccounts);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(
          accounts.entries.map((e) => Object.hash(e.key, e.value)),
        ),
        Object.hashAllUnordered(
          quarantinedAccounts.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  static bool _mapEquals(
    Map<String, AccountSyncState> a,
    Map<String, AccountSyncState> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
