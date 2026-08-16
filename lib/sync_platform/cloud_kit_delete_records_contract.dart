/// Build 26 Phase 5 (slice 2): the platform-channel request/result contract
/// for `deleteKeptWisdomRecords` -- the narrow, physical-delete half of the
/// Phase 5 remote-deletion transport, used only by the deletion runner
/// (`lib/sync_deletion/`). Deliberately separate from
/// `cloud_kit_modify_records_contract.dart`'s `modifyPrivateRecords`: that
/// method is Phase 4's save-only record transport, whose own native
/// coordinator has a locked, tested invariant that it never issues a
/// physical CloudKit record deletion (normal sync is tombstone-only). This
/// contract's one purpose is exactly the opposite -- physical deletion -- so
/// it is intentionally a new, distinct method rather than a mode flag on
/// the existing one, keeping that invariant provably unweakened.
///
/// One request carries only opaque `recordName` strings (as returned by
/// `listKeptWisdomRecordNames`) -- never a `revealId`, never wisdom or
/// Reflection content, never a `CKRecord`-shaped payload.
library;

/// A request to physically delete the named `CKKeptWisdom` records from
/// `EASTKeptZone`. Empty [recordNames] is a valid, well-defined no-op
/// request. The caller (the deletion runner) is responsible for keeping
/// [recordNames] within a single CloudKit-safe batch size -- this contract
/// does not itself chunk a larger list.
final class CloudKitDeleteKeptWisdomRecordsRequest {
  const CloudKitDeleteKeptWisdomRecordsRequest({required this.recordNames});

  final List<String> recordNames;

  Map<Object?, Object?> toChannelArguments() => {
        'recordNames': List<String>.unmodifiable(recordNames),
      };

  @override
  String toString() => 'CloudKitDeleteKeptWisdomRecordsRequest('
      'recordCount: ${recordNames.length})';
}

/// The outcome for exactly one record within a
/// [CloudKitDeleteKeptWisdomRecordsResult].
///
/// A record CloudKit reports as already absent (`unknownItem`) is still
/// reported here as a normal per-record failure outcome, carrying that
/// exact `errorCode` -- this contract never itself decides that "already
/// absent" means "success" (see
/// `lib/sync/sync_error_classification.dart`'s "Swift only reports what
/// happened" convention). The deletion runner is the one place that
/// interprets `unknownItem` as an idempotent, retry-safe non-failure.
final class CloudKitRecordDeleteOutcome {
  const CloudKitRecordDeleteOutcome._({
    required this.recordName,
    required this.success,
    this.errorCode,
  });

  factory CloudKitRecordDeleteOutcome.success({required String recordName}) =>
      CloudKitRecordDeleteOutcome._(recordName: recordName, success: true);

  factory CloudKitRecordDeleteOutcome.failure({
    required String recordName,
    required String errorCode,
  }) =>
      CloudKitRecordDeleteOutcome._(
        recordName: recordName,
        success: false,
        errorCode: errorCode,
      );

  final String recordName;
  final bool success;
  final String? errorCode;

  /// Strictly parses one raw outcome map. Rejects any key outside the
  /// approved set, any wrong type, and any `success`/field-presence
  /// combination other than the two documented above. Returns `null` for
  /// anything malformed -- never throws.
  static CloudKitRecordDeleteOutcome? tryParse(Map<Object?, Object?> raw) {
    const allowedKeys = {'recordName', 'success', 'errorCode'};
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) return null;
    }

    final recordName = raw['recordName'];
    if (recordName is! String || recordName.isEmpty) return null;

    final success = raw['success'];
    if (success is! bool) return null;

    if (success) {
      if (raw['errorCode'] != null) return null;
      return CloudKitRecordDeleteOutcome.success(recordName: recordName);
    }

    final errorCode = raw['errorCode'];
    if (errorCode is! String || errorCode.isEmpty) return null;
    return CloudKitRecordDeleteOutcome.failure(
      recordName: recordName,
      errorCode: errorCode,
    );
  }

  /// Content-safe: a bare `recordName` is never wisdom/Reflection content.
  @override
  String toString() => 'CloudKitRecordDeleteOutcome(recordName: $recordName, '
      'success: $success, errorCode: $errorCode)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CloudKitRecordDeleteOutcome &&
        other.recordName == recordName &&
        other.success == success &&
        other.errorCode == errorCode;
  }

  @override
  int get hashCode => Object.hash(recordName, success, errorCode);
}

/// The overall shape of a `deleteKeptWisdomRecords` result -- mirrors
/// [CloudKitModifyRecordsOverallStatus]'s three-way shape exactly (see
/// `cloud_kit_modify_records_contract.dart`).
enum CloudKitDeleteRecordsOverallStatus {
  /// Every requested record was deleted successfully. Also the status for
  /// an empty request.
  allSucceeded,

  /// At least one requested record has a known outcome, and at least one
  /// outcome is a failure.
  partialFailure,

  /// The operation could not run at all, or could not report a per-record
  /// outcome for *any* requested record.
  transportFailure,

  /// Reserved for a raw payload this Dart build does not recognize --
  /// fail-closed default, never treated as [allSucceeded].
  unknown,
}

/// The full result of one `deleteKeptWisdomRecords` call.
final class CloudKitDeleteKeptWisdomRecordsResult {
  const CloudKitDeleteKeptWisdomRecordsResult._({
    required this.overallStatus,
    required this.outcomes,
    this.errorCode,
  });

  factory CloudKitDeleteKeptWisdomRecordsResult.allSucceeded(
    List<CloudKitRecordDeleteOutcome> outcomes,
  ) =>
      CloudKitDeleteKeptWisdomRecordsResult._(
        overallStatus: CloudKitDeleteRecordsOverallStatus.allSucceeded,
        outcomes: List.unmodifiable(outcomes),
      );

  factory CloudKitDeleteKeptWisdomRecordsResult.partialFailure(
    List<CloudKitRecordDeleteOutcome> outcomes,
  ) =>
      CloudKitDeleteKeptWisdomRecordsResult._(
        overallStatus: CloudKitDeleteRecordsOverallStatus.partialFailure,
        outcomes: List.unmodifiable(outcomes),
      );

  factory CloudKitDeleteKeptWisdomRecordsResult.transportFailure(
    String errorCode,
  ) =>
      CloudKitDeleteKeptWisdomRecordsResult._(
        overallStatus: CloudKitDeleteRecordsOverallStatus.transportFailure,
        outcomes: const [],
        errorCode: errorCode,
      );

  final CloudKitDeleteRecordsOverallStatus overallStatus;
  final List<CloudKitRecordDeleteOutcome> outcomes;
  final String? errorCode;

  /// Strictly parses a raw `deleteKeptWisdomRecords` result payload. Rejects
  /// any top-level key outside the approved set, any wrong type, and any
  /// `overallStatus` this Dart build does not recognize.
  static CloudKitDeleteKeptWisdomRecordsResult tryParse(
    Map<Object?, Object?> raw,
  ) {
    const allowedKeys = {'overallStatus', 'outcomes', 'errorCode'};
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) {
        return const CloudKitDeleteKeptWisdomRecordsResult._(
          overallStatus: CloudKitDeleteRecordsOverallStatus.unknown,
          outcomes: [],
        );
      }
    }

    final statusValue = raw['overallStatus'];
    switch (statusValue) {
      case 'allSucceeded':
        final outcomes = _tryParseOutcomes(raw['outcomes']);
        if (outcomes == null) {
          return const CloudKitDeleteKeptWisdomRecordsResult._(
            overallStatus: CloudKitDeleteRecordsOverallStatus.unknown,
            outcomes: [],
          );
        }
        return CloudKitDeleteKeptWisdomRecordsResult.allSucceeded(outcomes);
      case 'partialFailure':
        final outcomes = _tryParseOutcomes(raw['outcomes']);
        if (outcomes == null) {
          return const CloudKitDeleteKeptWisdomRecordsResult._(
            overallStatus: CloudKitDeleteRecordsOverallStatus.unknown,
            outcomes: [],
          );
        }
        return CloudKitDeleteKeptWisdomRecordsResult.partialFailure(outcomes);
      case 'transportFailure':
        final errorCode = raw['errorCode'];
        if (errorCode is! String || errorCode.isEmpty) {
          return const CloudKitDeleteKeptWisdomRecordsResult._(
            overallStatus: CloudKitDeleteRecordsOverallStatus.unknown,
            outcomes: [],
          );
        }
        return CloudKitDeleteKeptWisdomRecordsResult.transportFailure(
          errorCode,
        );
      default:
        return const CloudKitDeleteKeptWisdomRecordsResult._(
          overallStatus: CloudKitDeleteRecordsOverallStatus.unknown,
          outcomes: [],
        );
    }
  }

  static List<CloudKitRecordDeleteOutcome>? _tryParseOutcomes(Object? raw) {
    if (raw is! List) return null;
    final parsed = <CloudKitRecordDeleteOutcome>[];
    for (final entry in raw) {
      if (entry is! Map<Object?, Object?>) return null;
      final outcome = CloudKitRecordDeleteOutcome.tryParse(entry);
      if (outcome == null) return null;
      parsed.add(outcome);
    }
    return parsed;
  }

  @override
  String toString() =>
      'CloudKitDeleteKeptWisdomRecordsResult(overallStatus: $overallStatus, '
      'outcomeCount: ${outcomes.length}, errorCode: $errorCode)';
}
