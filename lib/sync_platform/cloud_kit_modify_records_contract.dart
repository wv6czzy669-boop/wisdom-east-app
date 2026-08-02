/// Build 26 Phase 4C-2: the platform-channel request/result contract for
/// `modifyPrivateRecords` -- the narrow save-side half of the private
/// CloudKit record transport. Deliberately lives under `lib/sync_platform/`,
/// alongside the Phase 4C-1 wire envelopes it builds on, never inside the
/// pure Phase 4A sync domain (`lib/sync/`).
///
/// This phase is transport-**boundary** code, not a transport
/// implementation: nothing in this file performs a `MethodChannel` call --
/// see `method_channel_cloud_kit_platform_bridge.dart` for the one place
/// that actually invokes `modifyPrivateRecords`. This file only defines the
/// validated shapes that call's request and result take.
///
/// Every request record is built exclusively from an already-validated pure
/// projection ([CloudKeptWisdomProjection]/[CloudEastSyncStateProjection]),
/// via [CloudKitRecordChangeInput.keptWisdom]/`.syncState` -- there is no
/// public constructor that accepts a raw, untyped field map, so a caller
/// cannot smuggle an unapproved field onto the wire from the Dart side any
/// more than the existing wire envelopes allow from the native side.
library;

import '../sync/cloud_east_sync_state_projection.dart';
import '../sync/cloud_kept_wisdom_projection.dart';
import 'cloud_east_sync_state_wire_envelope.dart';
import 'cloud_kept_wisdom_wire_envelope.dart';

/// One record to save, plus the opaque, previously-observed CloudKit
/// "system fields" blob (record change tag) to save it against, if any.
///
/// [previousSystemFields] is never interpreted by Dart -- it is an opaque
/// Base64 string, produced only by a prior [CloudKitModifyRecordsResult] or
/// [CloudKitZoneChangesResult] outcome for the exact same record, and
/// consumed only by the native transport (§ "opaque change-token/system-
/// fields representation"). Passing `null` means "no known prior server
/// version" -- the native side then saves unconditionally for a
/// newly-created record, exactly as CloudKit's own `.changedKeys` policy
/// would for a record it has never seen, though the transport otherwise
/// uses `.ifServerRecordUnchanged` (see the native
/// `CloudKitRecordTransportCoordinator` doc comment for the exact save-
/// policy rationale).
final class CloudKitRecordChangeInput {
  const CloudKitRecordChangeInput._({
    required this.recordType,
    required this.fields,
    this.previousSystemFields,
  });

  /// Builds a change input from an already-validated
  /// [CloudKeptWisdomProjection] -- active or tombstone form. There is no
  /// way to reach this constructor with an unvalidated/raw field map: the
  /// projection itself was already either derived from a real
  /// [CloudKeptWisdomProjection.active]/`.tombstone` call or fail-closed
  /// parsed via [CloudKeptWisdomProjection.tryParseRemote].
  factory CloudKitRecordChangeInput.keptWisdom(
    CloudKeptWisdomProjection projection, {
    String? previousSystemFields,
  }) {
    return CloudKitRecordChangeInput._(
      recordType: CloudKeptWisdomWireEnvelope.recordType,
      fields: CloudKeptWisdomWireEnvelope.encode(projection),
      previousSystemFields: previousSystemFields,
    );
  }

  /// Builds a change input from an already-validated
  /// [CloudEastSyncStateProjection] singleton.
  factory CloudKitRecordChangeInput.syncState(
    CloudEastSyncStateProjection projection, {
    String? previousSystemFields,
  }) {
    return CloudKitRecordChangeInput._(
      recordType: CloudEastSyncStateWireEnvelope.recordType,
      fields: CloudEastSyncStateWireEnvelope.encode(projection),
      previousSystemFields: previousSystemFields,
    );
  }

  /// One of [CloudKeptWisdomWireEnvelope.recordType] or
  /// [CloudEastSyncStateWireEnvelope.recordType] -- never any other value,
  /// since the only two factories above are the only way to construct this
  /// class.
  final String recordType;

  /// The exact wire-envelope `Map` shape `encode()` already produces for
  /// this record -- already allowlist-safe by construction.
  final Map<Object?, Object?> fields;

  /// Opaque previously-observed system-fields blob, or `null`. Never
  /// logged, never parsed, never compared by Dart.
  final String? previousSystemFields;

  /// The exact `Map` this one record contributes to a
  /// `modifyPrivateRecords` MethodChannel argument payload.
  Map<Object?, Object?> toChannelMap() => {
        'recordType': recordType,
        'fields': fields,
        if (previousSystemFields != null)
          'previousSystemFields': previousSystemFields,
      };

  /// Content-safe: never renders [fields] (which, for an active-form
  /// [CloudKeptWisdomProjection], can carry `wisdomText`/`reflectionText`)
  /// or [previousSystemFields].
  @override
  String toString() => 'CloudKitRecordChangeInput(recordType: $recordType, '
      'hasPreviousSystemFields: ${previousSystemFields != null})';
}

/// A request to atomically save one or more validated records in
/// `EASTKeptZone`. Empty [records] is a valid, well-defined no-op request
/// (§ "empty modify request behavior") -- the native side still completes
/// with `overallStatus: allSucceeded` and an empty `outcomes` list, never
/// an error, since there is nothing to fail.
final class CloudKitModifyRecordsRequest {
  const CloudKitModifyRecordsRequest({required this.records});

  final List<CloudKitRecordChangeInput> records;

  Map<Object?, Object?> toChannelArguments() => {
        'records': records.map((r) => r.toChannelMap()).toList(growable: false),
      };

  @override
  String toString() =>
      'CloudKitModifyRecordsRequest(recordCount: ${records.length})';
}

/// The outcome for exactly one record within a [CloudKitModifyRecordsResult].
///
/// [success] and [errorCode] are mutually exclusive: a successful outcome
/// never carries an [errorCode], and a failed outcome never carries
/// [systemFields] -- CloudKit itself never confirms a record succeeded
/// without also handing back its post-save system fields, and a record this
/// transport never claims succeeded can never have a "current" system-
/// fields snapshot to report.
final class CloudKitRecordModifyOutcome {
  const CloudKitRecordModifyOutcome._({
    required this.recordName,
    required this.success,
    this.systemFields,
    this.errorCode,
  });

  /// A successful per-record outcome. [systemFields] is the fresh, opaque,
  /// securely-archived system-fields blob CloudKit returned for this exact
  /// save -- callers should retain it (outside this phase's scope) as the
  /// [CloudKitRecordChangeInput.previousSystemFields] input for this
  /// record's *next* save, so that save can use conflict-safe
  /// `.ifServerRecordUnchanged` semantics instead of an unconditional
  /// overwrite.
  factory CloudKitRecordModifyOutcome.success({
    required String recordName,
    required String systemFields,
  }) =>
      CloudKitRecordModifyOutcome._(
        recordName: recordName,
        success: true,
        systemFields: systemFields,
      );

  /// A failed per-record outcome, carrying only a stable symbolic
  /// [errorCode] -- e.g. `serverRecordChanged` for a save-policy conflict --
  /// never a localized message or any record content.
  factory CloudKitRecordModifyOutcome.failure({
    required String recordName,
    required String errorCode,
  }) =>
      CloudKitRecordModifyOutcome._(
        recordName: recordName,
        success: false,
        errorCode: errorCode,
      );

  final String recordName;
  final bool success;
  final String? systemFields;
  final String? errorCode;

  /// Strictly parses one raw outcome map. Rejects any key outside the
  /// approved set, any wrong type, and any `success`/field-presence
  /// combination other than the two documented above. Returns `null` for
  /// anything malformed -- never throws.
  static CloudKitRecordModifyOutcome? tryParse(Map<Object?, Object?> raw) {
    const allowedKeys = {'recordName', 'success', 'systemFields', 'errorCode'};
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) return null;
    }

    final recordName = raw['recordName'];
    if (recordName is! String || recordName.isEmpty) return null;

    final success = raw['success'];
    if (success is! bool) return null;

    if (success) {
      final systemFields = raw['systemFields'];
      if (systemFields is! String || systemFields.isEmpty) return null;
      if (raw['errorCode'] != null) return null;
      return CloudKitRecordModifyOutcome.success(
        recordName: recordName,
        systemFields: systemFields,
      );
    }

    final errorCode = raw['errorCode'];
    if (errorCode is! String || errorCode.isEmpty) return null;
    if (raw['systemFields'] != null) return null;
    return CloudKitRecordModifyOutcome.failure(
      recordName: recordName,
      errorCode: errorCode,
    );
  }

  /// Content-safe: a record name derived solely from `revealId`/the fixed
  /// sync-state literal is never wisdom/Reflection content.
  @override
  String toString() => 'CloudKitRecordModifyOutcome(recordName: $recordName, '
      'success: $success, errorCode: $errorCode)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CloudKitRecordModifyOutcome &&
        other.recordName == recordName &&
        other.success == success &&
        other.systemFields == systemFields &&
        other.errorCode == errorCode;
  }

  @override
  int get hashCode => Object.hash(recordName, success, systemFields, errorCode);
}

/// The overall shape of a `modifyPrivateRecords` result -- always exactly
/// one of these three, never a fourth, ambiguous state.
enum CloudKitModifyRecordsOverallStatus {
  /// Every requested record was saved successfully. Also the status for an
  /// empty request (§ "empty modify request behavior").
  allSucceeded,

  /// At least one requested record has a known outcome (success or
  /// failure), and at least one outcome is a failure -- including a
  /// `serverRecordChanged` conflict, which is always represented as a
  /// per-record failure outcome here, never a distinct top-level status.
  partialFailure,

  /// The operation could not run at all, or could not report a per-record
  /// outcome for *any* requested record (e.g. the device has no network) --
  /// [CloudKitModifyRecordsResult.errorCode] carries the reason.
  /// Structurally distinct from [partialFailure]: this transport never
  /// claims a record failed individually unless CloudKit itself was able to
  /// attempt it.
  transportFailure,

  /// Reserved for a raw payload this Dart build does not recognize --
  /// fail-closed default, never treated as [allSucceeded].
  unknown,
}

/// The full result of one `modifyPrivateRecords` call.
final class CloudKitModifyRecordsResult {
  const CloudKitModifyRecordsResult._({
    required this.overallStatus,
    required this.outcomes,
    this.errorCode,
  });

  factory CloudKitModifyRecordsResult.allSucceeded(
    List<CloudKitRecordModifyOutcome> outcomes,
  ) =>
      CloudKitModifyRecordsResult._(
        overallStatus: CloudKitModifyRecordsOverallStatus.allSucceeded,
        outcomes: List.unmodifiable(outcomes),
      );

  factory CloudKitModifyRecordsResult.partialFailure(
    List<CloudKitRecordModifyOutcome> outcomes,
  ) =>
      CloudKitModifyRecordsResult._(
        overallStatus: CloudKitModifyRecordsOverallStatus.partialFailure,
        outcomes: List.unmodifiable(outcomes),
      );

  factory CloudKitModifyRecordsResult.transportFailure(String errorCode) =>
      CloudKitModifyRecordsResult._(
        overallStatus: CloudKitModifyRecordsOverallStatus.transportFailure,
        outcomes: const [],
        errorCode: errorCode,
      );

  final CloudKitModifyRecordsOverallStatus overallStatus;
  final List<CloudKitRecordModifyOutcome> outcomes;
  final String? errorCode;

  /// Strictly parses a raw `modifyPrivateRecords` result payload. Rejects
  /// any top-level key outside the approved set, any wrong type, and any
  /// `overallStatus` this Dart build does not recognize -- an unrecognized
  /// status is fail-closed reported as [CloudKitModifyRecordsOverallStatus
  /// .unknown] with no outcomes trusted, never coerced into
  /// [CloudKitModifyRecordsOverallStatus.allSucceeded].
  static CloudKitModifyRecordsResult tryParse(Map<Object?, Object?> raw) {
    const allowedKeys = {'overallStatus', 'outcomes', 'errorCode'};
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) {
        return const CloudKitModifyRecordsResult._(
          overallStatus: CloudKitModifyRecordsOverallStatus.unknown,
          outcomes: [],
        );
      }
    }

    final statusValue = raw['overallStatus'];
    switch (statusValue) {
      case 'allSucceeded':
        final outcomes = _tryParseOutcomes(raw['outcomes']);
        if (outcomes == null) {
          return const CloudKitModifyRecordsResult._(
            overallStatus: CloudKitModifyRecordsOverallStatus.unknown,
            outcomes: [],
          );
        }
        return CloudKitModifyRecordsResult.allSucceeded(outcomes);
      case 'partialFailure':
        final outcomes = _tryParseOutcomes(raw['outcomes']);
        if (outcomes == null) {
          return const CloudKitModifyRecordsResult._(
            overallStatus: CloudKitModifyRecordsOverallStatus.unknown,
            outcomes: [],
          );
        }
        return CloudKitModifyRecordsResult.partialFailure(outcomes);
      case 'transportFailure':
        final errorCode = raw['errorCode'];
        if (errorCode is! String || errorCode.isEmpty) {
          return const CloudKitModifyRecordsResult._(
            overallStatus: CloudKitModifyRecordsOverallStatus.unknown,
            outcomes: [],
          );
        }
        return CloudKitModifyRecordsResult.transportFailure(errorCode);
      default:
        return const CloudKitModifyRecordsResult._(
          overallStatus: CloudKitModifyRecordsOverallStatus.unknown,
          outcomes: [],
        );
    }
  }

  static List<CloudKitRecordModifyOutcome>? _tryParseOutcomes(Object? raw) {
    if (raw is! List) return null;
    final parsed = <CloudKitRecordModifyOutcome>[];
    for (final entry in raw) {
      if (entry is! Map<Object?, Object?>) return null;
      final outcome = CloudKitRecordModifyOutcome.tryParse(entry);
      if (outcome == null) return null;
      parsed.add(outcome);
    }
    return parsed;
  }

  @override
  String toString() =>
      'CloudKitModifyRecordsResult(overallStatus: $overallStatus, '
      'outcomeCount: ${outcomes.length}, errorCode: $errorCode)';
}
