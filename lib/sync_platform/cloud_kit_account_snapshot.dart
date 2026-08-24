/// Build 26 Phase 4B-1: the Dart-side platform-bridge account snapshot
/// model. Deliberately lives under `lib/sync_platform/`, separate from the
/// pure Phase 4A sync domain (`lib/sync/`) -- this is the shape of what the
/// native bridge actually reports today, not a pure business-rule type. See
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s Phase 4B-1 section for the
/// exact wire contract this parses.
library;

/// Normalized CloudKit account availability reported by the native bridge.
/// [unknown] exists so a genuinely unrecognized wire value (a future native
/// case this build does not yet know about, or malformed input) always has a
/// safe place to land -- it is never silently coerced to [available].
enum CloudKitAccountAvailability {
  available,
  noAccount,
  restricted,
  couldNotDetermine,
  temporarilyUnavailable,
  unknown,
}

extension CloudKitAccountAvailabilityWireCodec on CloudKitAccountAvailability {
  static const String _available = 'available';
  static const String _noAccount = 'noAccount';
  static const String _restricted = 'restricted';
  static const String _couldNotDetermine = 'couldNotDetermine';
  static const String _temporarilyUnavailable = 'temporarilyUnavailable';

  /// Normalizes [value] to a [CloudKitAccountAvailability]. Never throws:
  /// any value outside the recognized wire vocabulary -- including a value
  /// a *future* native bridge might report that this build's Dart code
  /// predates -- safely maps to [CloudKitAccountAvailability.unknown]
  /// rather than being silently coerced to
  /// [CloudKitAccountAvailability.available] or causing a crash.
  static CloudKitAccountAvailability fromWireValue(String value) {
    switch (value) {
      case _available:
        return CloudKitAccountAvailability.available;
      case _noAccount:
        return CloudKitAccountAvailability.noAccount;
      case _restricted:
        return CloudKitAccountAvailability.restricted;
      case _couldNotDetermine:
        return CloudKitAccountAvailability.couldNotDetermine;
      case _temporarilyUnavailable:
        return CloudKitAccountAvailability.temporarilyUnavailable;
      default:
        return CloudKitAccountAvailability.unknown;
    }
  }
}

/// A content-free snapshot of the current CloudKit account state, as
/// reported by `getAccountSnapshot` (see
/// `lib/sync_platform/cloud_kit_platform_bridge.dart`).
///
/// [accountFingerprint], when present, is an opaque token only -- never a
/// raw CloudKit user record ID or record name (the native side has already
/// hashed it before it ever reaches Dart; see
/// `ios/Runner/CloudKitAccountFingerprintUtility.swift`). It exists solely
/// to support a future same-account/different-account boundary check
/// (design doc §5) and must never be logged or displayed -- see
/// [toLogSafeSummary].
final class CloudKitAccountSnapshot {
  const CloudKitAccountSnapshot({
    required this.availability,
    required this.isPrivateDatabaseUsable,
    required this.accountFingerprint,
    required this.fingerprintResolved,
    required this.bridgeVersion,
  });

  final CloudKitAccountAvailability availability;
  final bool isPrivateDatabaseUsable;

  /// Opaque. Never the raw CloudKit user record ID. `null` whenever
  /// [fingerprintResolved] is `false`.
  final String? accountFingerprint;

  /// Whether the native side was able to resolve [accountFingerprint] on
  /// this call. `false` whenever the account is not
  /// [CloudKitAccountAvailability.available], or when an identity-fetch
  /// failure occurred -- an unresolved fingerprint is never treated as
  /// proof of anything about account identity (design doc §5: "an
  /// identity-fetch failure must not falsely report that the account is a
  /// different user").
  final bool fingerprintResolved;

  final int bridgeVersion;

  /// Parses a loosely-typed native result map. Returns `null` for anything
  /// malformed -- a missing/wrong-typed field, or an internally
  /// inconsistent combination (e.g. `fingerprintResolved: true` with no
  /// `accountFingerprint`) -- never throws, never guesses. Fails closed per
  /// this phase's requirement that a malformed native snapshot must not be
  /// silently accepted.
  static CloudKitAccountSnapshot? tryParse(Map<Object?, Object?> raw) {
    final statusValue = raw['status'];
    if (statusValue is! String || statusValue.isEmpty) return null;

    final isPrivateDatabaseUsable = raw['isPrivateDatabaseUsable'];
    if (isPrivateDatabaseUsable is! bool) return null;

    final fingerprintResolved = raw['fingerprintResolved'];
    if (fingerprintResolved is! bool) return null;

    final bridgeVersion = raw['bridgeVersion'];
    if (bridgeVersion is! int || bridgeVersion < 1) return null;

    final fingerprintValue = raw['accountFingerprint'];
    if (fingerprintValue != null && fingerprintValue is! String) return null;

    // Internal consistency: a resolved fingerprint must carry a non-empty
    // value; an unresolved one must carry none. A native side reporting
    // otherwise is malformed, not a variant to tolerate -- fail closed.
    if (fingerprintResolved) {
      if (fingerprintValue == null || (fingerprintValue as String).isEmpty) {
        return null;
      }
    } else if (fingerprintValue != null) {
      return null;
    }

    return CloudKitAccountSnapshot(
      availability:
          CloudKitAccountAvailabilityWireCodec.fromWireValue(statusValue),
      isPrivateDatabaseUsable: isPrivateDatabaseUsable,
      accountFingerprint: fingerprintValue as String?,
      fingerprintResolved: fingerprintResolved,
      bridgeVersion: bridgeVersion,
    );
  }

  /// A privacy-safe summary suitable for logs/diagnostics: never includes
  /// [accountFingerprint]'s actual value, only whether one was resolved.
  Map<String, Object?> toLogSafeSummary() => {
        'availability': availability.name,
        'isPrivateDatabaseUsable': isPrivateDatabaseUsable,
        'fingerprintResolved': fingerprintResolved,
        'bridgeVersion': bridgeVersion,
      };

  @override
  String toString() => 'CloudKitAccountSnapshot(${toLogSafeSummary()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CloudKitAccountSnapshot &&
        other.availability == availability &&
        other.isPrivateDatabaseUsable == isPrivateDatabaseUsable &&
        other.accountFingerprint == accountFingerprint &&
        other.fingerprintResolved == fingerprintResolved &&
        other.bridgeVersion == bridgeVersion;
  }

  @override
  int get hashCode => Object.hash(
        availability,
        isPrivateDatabaseUsable,
        accountFingerprint,
        fingerprintResolved,
        bridgeVersion,
      );
}
