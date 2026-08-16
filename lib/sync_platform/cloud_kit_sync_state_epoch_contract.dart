/// Build 26 Phase 5 (slice 2): the platform-channel result contract for
/// `fetchSyncStateEpoch` -- a narrow, single-record, content-minimal read of
/// the `CKEastSyncState` singleton, used only by the Phase 5 remote
/// deletion runner's epoch-barrier step (`lib/sync_deletion/`). Deliberately
/// distinct from `fetchPrivateZoneChanges`: that method is a change-token
/// delta fetch that also returns every changed `CKKeptWisdom` record's full
/// content, and advances/returns a server token tied to Phase 4's own
/// incremental-sync checkpoint bookkeeping -- neither is appropriate for a
/// deletion runner that must never read wisdom/Reflection content and must
/// never interact with the normal sync checkpoint at all.
///
/// This file only defines the validated shape `fetchSyncStateEpoch`'s
/// result takes -- see `method_channel_cloud_kit_platform_bridge.dart` for
/// the one place that actually invokes it.
library;

import '../sync/data_epoch.dart';

/// The overall shape of a `fetchSyncStateEpoch` result.
enum CloudKitSyncStateEpochOutcome {
  /// The `CKEastSyncState` singleton record exists and was decoded.
  found,

  /// No `CKEastSyncState` record exists yet in the private zone. Distinct
  /// from [failure] -- this is an ordinary, expected state for a device
  /// whose bucket has never been bootstrapped, not an error.
  notFound,

  /// The read could not complete -- [CloudKitSyncStateEpochResult.errorCode]
  /// carries the reason.
  failure,

  /// Reserved for a raw payload this Dart build does not recognize --
  /// fail-closed default, never treated as [found].
  unknown,
}

/// The full result of one `fetchSyncStateEpoch` call. Carries only the
/// current authoritative [DataEpoch] and the record's opaque system fields
/// (needed so a subsequent conditional save can use CloudKit's own
/// `.ifServerRecordUnchanged` precondition) -- never `resetAtMs`,
/// `mutationId`, or `schemaVersion`, none of which the deletion runner needs
/// to make its epoch-barrier decision.
final class CloudKitSyncStateEpochResult {
  const CloudKitSyncStateEpochResult._({
    required this.outcome,
    this.dataEpoch,
    this.systemFields,
    this.errorCode,
  });

  factory CloudKitSyncStateEpochResult.found({
    required DataEpoch dataEpoch,
    required String systemFields,
  }) =>
      CloudKitSyncStateEpochResult._(
        outcome: CloudKitSyncStateEpochOutcome.found,
        dataEpoch: dataEpoch,
        systemFields: systemFields,
      );

  factory CloudKitSyncStateEpochResult.notFound() =>
      const CloudKitSyncStateEpochResult._(
        outcome: CloudKitSyncStateEpochOutcome.notFound,
      );

  factory CloudKitSyncStateEpochResult.failure(String errorCode) =>
      CloudKitSyncStateEpochResult._(
        outcome: CloudKitSyncStateEpochOutcome.failure,
        errorCode: errorCode,
      );

  final CloudKitSyncStateEpochOutcome outcome;

  /// Populated for [CloudKitSyncStateEpochOutcome.found] only.
  final DataEpoch? dataEpoch;

  /// Populated for [CloudKitSyncStateEpochOutcome.found] only. Opaque;
  /// never parsed, compared, or logged by Dart.
  final String? systemFields;

  final String? errorCode;

  /// Strictly parses a raw `fetchSyncStateEpoch` result payload. Rejects any
  /// top-level key outside the approved set, any wrong type, and any
  /// `outcome` this Dart build does not recognize -- fail-closed, never
  /// coerced into [CloudKitSyncStateEpochOutcome.found].
  static CloudKitSyncStateEpochResult tryParse(Map<Object?, Object?> raw) {
    const allowedKeys = {'outcome', 'dataEpoch', 'systemFields', 'errorCode'};
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) {
        return const CloudKitSyncStateEpochResult._(
          outcome: CloudKitSyncStateEpochOutcome.unknown,
        );
      }
    }

    final outcomeValue = raw['outcome'];
    switch (outcomeValue) {
      case 'found':
        final dataEpochValue = raw['dataEpoch'];
        final systemFieldsValue = raw['systemFields'];
        if (dataEpochValue is! String ||
            !DataEpoch.isValid(dataEpochValue) ||
            systemFieldsValue is! String ||
            systemFieldsValue.isEmpty) {
          return const CloudKitSyncStateEpochResult._(
            outcome: CloudKitSyncStateEpochOutcome.unknown,
          );
        }
        return CloudKitSyncStateEpochResult.found(
          dataEpoch: DataEpoch.parse(dataEpochValue),
          systemFields: systemFieldsValue,
        );
      case 'notFound':
        return CloudKitSyncStateEpochResult.notFound();
      case 'failure':
        final errorCode = raw['errorCode'];
        if (errorCode is! String || errorCode.isEmpty) {
          return const CloudKitSyncStateEpochResult._(
            outcome: CloudKitSyncStateEpochOutcome.unknown,
          );
        }
        return CloudKitSyncStateEpochResult.failure(errorCode);
      default:
        return const CloudKitSyncStateEpochResult._(
          outcome: CloudKitSyncStateEpochOutcome.unknown,
        );
    }
  }

  /// Content-safe: renders the outcome and whether an epoch/system-fields
  /// value is present, never the epoch's own value or the opaque system
  /// fields themselves.
  @override
  String toString() => 'CloudKitSyncStateEpochResult(outcome: $outcome, '
      'hasDataEpoch: ${dataEpoch != null}, errorCode: $errorCode)';
}
