import '../sync/sync_record_identity.dart';

/// Build 26 Phase 4B-1: static, content-free bridge/build information (see
/// `lib/sync_platform/cloud_kit_platform_bridge.dart`'s `getBridgeInfo`).
/// Never exposes signing, Apple Account, record IDs, or user content.
final class CloudKitBridgeInfo {
  const CloudKitBridgeInfo({
    required this.bridgeVersion,
    required this.expectedZoneName,
    required this.expectedRecordTypes,
    required this.privateDatabaseOnly,
    required this.capabilityActivationExpected,
  });

  final int bridgeVersion;
  final String expectedZoneName;
  final List<String> expectedRecordTypes;
  final bool privateDatabaseOnly;

  /// Whether the iCloud capability/entitlement is expected to have been
  /// activated by this point. Always `false` until Phase 4B-2's manual
  /// Xcode steps are performed -- Phase 4B-1 never activates it.
  final bool capabilityActivationExpected;

  /// Parses a loosely-typed native result map. Returns `null` for anything
  /// malformed -- never throws, never guesses.
  static CloudKitBridgeInfo? tryParse(Map<Object?, Object?> raw) {
    final bridgeVersion = raw['bridgeVersion'];
    if (bridgeVersion is! int || bridgeVersion < 1) return null;

    final expectedZoneName = raw['expectedZoneName'];
    if (expectedZoneName is! String || expectedZoneName.isEmpty) return null;

    final rawRecordTypes = raw['expectedRecordTypes'];
    if (rawRecordTypes is! List) return null;
    final expectedRecordTypes = <String>[];
    for (final entry in rawRecordTypes) {
      if (entry is! String || entry.isEmpty) return null;
      expectedRecordTypes.add(entry);
    }
    if (expectedRecordTypes.isEmpty) return null;

    final privateDatabaseOnly = raw['privateDatabaseOnly'];
    if (privateDatabaseOnly is! bool) return null;

    final capabilityActivationExpected = raw['capabilityActivationExpected'];
    if (capabilityActivationExpected is! bool) return null;

    return CloudKitBridgeInfo(
      bridgeVersion: bridgeVersion,
      expectedZoneName: expectedZoneName,
      expectedRecordTypes: List.unmodifiable(expectedRecordTypes),
      privateDatabaseOnly: privateDatabaseOnly,
      capabilityActivationExpected: capabilityActivationExpected,
    );
  }

  /// Cross-checks this bridge's reported constants against the Phase 4A
  /// pure Dart sync-domain constants already defined in
  /// `lib/sync/sync_record_identity.dart` -- proves the two independently
  /// maintained layers (pure Dart sync domain vs. native bridge) have not
  /// silently drifted apart, without merging them into one file or one
  /// layer importing the other's implementation.
  bool matchesPhase4ADomainConstants() {
    return expectedZoneName == keptRecordZoneName &&
        expectedRecordTypes.contains(keptWisdomRecordType) &&
        expectedRecordTypes.contains(syncStateRecordType) &&
        privateDatabaseOnly;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CloudKitBridgeInfo &&
        other.bridgeVersion == bridgeVersion &&
        other.expectedZoneName == expectedZoneName &&
        _listEquals(other.expectedRecordTypes, expectedRecordTypes) &&
        other.privateDatabaseOnly == privateDatabaseOnly &&
        other.capabilityActivationExpected == capabilityActivationExpected;
  }

  @override
  int get hashCode => Object.hash(
        bridgeVersion,
        expectedZoneName,
        Object.hashAll(expectedRecordTypes),
        privateDatabaseOnly,
        capabilityActivationExpected,
      );
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
