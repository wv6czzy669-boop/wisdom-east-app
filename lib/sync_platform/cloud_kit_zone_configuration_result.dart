import 'cloud_kit_account_snapshot.dart';

/// Build 26 Phase 4B-1: the result of `configurePrivateZone` (see
/// `lib/sync_platform/cloud_kit_platform_bridge.dart`). Content-free --
/// identifiers, flags, and a symbolic error code only.
final class CloudKitZoneConfigurationResult {
  const CloudKitZoneConfigurationResult({
    required this.success,
    required this.zoneCreated,
    required this.zoneAlreadyExisted,
    required this.accountAvailability,
    this.errorCode,
  });

  final bool success;

  /// `true` only when this exact call newly created the zone.
  final bool zoneCreated;

  /// `true` when the zone already existed -- treated as success, per the
  /// design doc's idempotency requirement, never as an error.
  final bool zoneAlreadyExisted;

  final CloudKitAccountAvailability accountAvailability;

  /// A symbolic error code from `lib/sync/sync_error_classification.dart`'s
  /// vocabulary (or an unrecognized one the native side reported), present
  /// only when [success] is `false`. This layer never classifies it itself
  /// -- see `lib/sync_platform/cloud_kit_platform_error.dart`.
  final String? errorCode;

  /// Parses a loosely-typed native result map. Returns `null` for anything
  /// malformed or internally inconsistent (e.g. claiming both
  /// [zoneCreated] and [zoneAlreadyExisted], or claiming [success] while
  /// also carrying an [errorCode]) -- never throws, never guesses.
  static CloudKitZoneConfigurationResult? tryParse(Map<Object?, Object?> raw) {
    final success = raw['success'];
    if (success is! bool) return null;

    final zoneCreated = raw['zoneCreated'];
    if (zoneCreated is! bool) return null;

    final zoneAlreadyExisted = raw['zoneAlreadyExisted'];
    if (zoneAlreadyExisted is! bool) return null;

    final statusValue = raw['accountStatus'];
    if (statusValue is! String || statusValue.isEmpty) return null;

    final errorCodeValue = raw['errorCode'];
    if (errorCodeValue != null && errorCodeValue is! String) return null;
    if (errorCodeValue is String && errorCodeValue.isEmpty) return null;

    if (zoneCreated && zoneAlreadyExisted) return null;
    if (success && errorCodeValue != null) return null;
    if (!success && errorCodeValue == null) return null;
    if (!success && (zoneCreated || zoneAlreadyExisted)) return null;

    return CloudKitZoneConfigurationResult(
      success: success,
      zoneCreated: zoneCreated,
      zoneAlreadyExisted: zoneAlreadyExisted,
      accountAvailability:
          CloudKitAccountAvailabilityWireCodec.fromWireValue(statusValue),
      errorCode: errorCodeValue as String?,
    );
  }

  Map<String, Object?> toLogSafeSummary() => {
        'success': success,
        'zoneCreated': zoneCreated,
        'zoneAlreadyExisted': zoneAlreadyExisted,
        'accountAvailability': accountAvailability.name,
        'errorCode': errorCode,
      };

  @override
  String toString() => 'CloudKitZoneConfigurationResult(${toLogSafeSummary()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CloudKitZoneConfigurationResult &&
        other.success == success &&
        other.zoneCreated == zoneCreated &&
        other.zoneAlreadyExisted == zoneAlreadyExisted &&
        other.accountAvailability == accountAvailability &&
        other.errorCode == errorCode;
  }

  @override
  int get hashCode => Object.hash(
        success,
        zoneCreated,
        zoneAlreadyExisted,
        accountAvailability,
        errorCode,
      );
}
