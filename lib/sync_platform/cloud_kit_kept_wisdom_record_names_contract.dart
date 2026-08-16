/// Build 26 Phase 5 (slice 2): the platform-channel result contract for
/// `listKeptWisdomRecordNames` -- a content-free listing of every
/// `CKKeptWisdom` record currently in `EASTKeptZone`, used only by the
/// Phase 5 remote deletion runner (`lib/sync_deletion/`) to discover which
/// records to purge, and again afterward to verify zero remain.
///
/// Deliberately carries only opaque `recordName` strings -- never
/// `revealId`, `wisdomText`, `reflectionText`, or any other field a
/// `CKKeptWisdom` record holds. The native side is expected to issue this
/// query with `desiredKeys: []` (no field data fetched from CloudKit at
/// all), so there is no content for this contract to accidentally carry
/// even if a future edit were careless -- there is no field on this class
/// capable of holding it.
library;

/// The overall shape of a `listKeptWisdomRecordNames` result.
enum CloudKitKeptWisdomRecordNamesOutcome {
  /// The listing (including every page CloudKit reported internally)
  /// completed. An empty zone is a well-defined, successful empty list --
  /// never an error.
  success,

  /// The listing could not complete --
  /// [CloudKitKeptWisdomRecordNamesResult.errorCode] carries the reason.
  failure,

  /// Reserved for a raw payload this Dart build does not recognize --
  /// fail-closed default, never treated as [success].
  unknown,
}

/// The full result of one `listKeptWisdomRecordNames` call.
final class CloudKitKeptWisdomRecordNamesResult {
  const CloudKitKeptWisdomRecordNamesResult._({
    required this.outcome,
    this.recordNames = const [],
    this.errorCode,
  });

  factory CloudKitKeptWisdomRecordNamesResult.success(
    List<String> recordNames,
  ) =>
      CloudKitKeptWisdomRecordNamesResult._(
        outcome: CloudKitKeptWisdomRecordNamesOutcome.success,
        recordNames: List.unmodifiable(recordNames),
      );

  factory CloudKitKeptWisdomRecordNamesResult.failure(String errorCode) =>
      CloudKitKeptWisdomRecordNamesResult._(
        outcome: CloudKitKeptWisdomRecordNamesOutcome.failure,
        errorCode: errorCode,
      );

  final CloudKitKeptWisdomRecordNamesOutcome outcome;

  /// Populated for [CloudKitKeptWisdomRecordNamesOutcome.success] only.
  /// Every entry is an opaque CloudKit `recordName` -- never a `revealId`
  /// directly, even though this codebase's record names are deterministic
  /// functions of `revealId` (`deriveKeptWisdomRecordName`); this contract
  /// never decodes, parses, or interprets an entry, only carries it as an
  /// opaque token to pass back to `deleteKeptWisdomRecords`.
  final List<String> recordNames;

  final String? errorCode;

  /// Strictly parses a raw `listKeptWisdomRecordNames` result payload.
  /// Rejects any top-level key outside the approved set, any wrong type, and
  /// any `outcome` this Dart build does not recognize -- fail-closed, never
  /// coerced into [CloudKitKeptWisdomRecordNamesOutcome.success].
  static CloudKitKeptWisdomRecordNamesResult tryParse(
    Map<Object?, Object?> raw,
  ) {
    const allowedKeys = {'outcome', 'recordNames', 'errorCode'};
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) {
        return const CloudKitKeptWisdomRecordNamesResult._(
          outcome: CloudKitKeptWisdomRecordNamesOutcome.unknown,
        );
      }
    }

    final outcomeValue = raw['outcome'];
    switch (outcomeValue) {
      case 'success':
        final rawNames = raw['recordNames'];
        if (rawNames is! List) {
          return const CloudKitKeptWisdomRecordNamesResult._(
            outcome: CloudKitKeptWisdomRecordNamesOutcome.unknown,
          );
        }
        final names = <String>[];
        for (final entry in rawNames) {
          if (entry is! String || entry.isEmpty) {
            return const CloudKitKeptWisdomRecordNamesResult._(
              outcome: CloudKitKeptWisdomRecordNamesOutcome.unknown,
            );
          }
          names.add(entry);
        }
        return CloudKitKeptWisdomRecordNamesResult.success(names);
      case 'failure':
        final errorCode = raw['errorCode'];
        if (errorCode is! String || errorCode.isEmpty) {
          return const CloudKitKeptWisdomRecordNamesResult._(
            outcome: CloudKitKeptWisdomRecordNamesOutcome.unknown,
          );
        }
        return CloudKitKeptWisdomRecordNamesResult.failure(errorCode);
      default:
        return const CloudKitKeptWisdomRecordNamesResult._(
          outcome: CloudKitKeptWisdomRecordNamesOutcome.unknown,
        );
    }
  }

  /// Content-safe: a bare `recordName` (`"east-kept-" + revealId`) is never
  /// wisdom/Reflection content, but this still renders only a count, never
  /// the list itself, consistent with every other transport result in this
  /// codebase.
  @override
  String toString() => 'CloudKitKeptWisdomRecordNamesResult(outcome: $outcome, '
      'recordCount: ${recordNames.length}, errorCode: $errorCode)';
}
