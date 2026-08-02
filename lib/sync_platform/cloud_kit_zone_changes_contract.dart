/// Build 26 Phase 4C-2: the platform-channel request/result contract for
/// `fetchPrivateZoneChanges` -- the narrow read-side half of the private
/// CloudKit record transport. See `cloud_kit_modify_records_contract.dart`'s
/// doc comment for the same transport-boundary-only rationale; this file is
/// its fetch-side counterpart.
library;

import '../sync/cloud_east_sync_state_projection.dart';
import '../sync/cloud_kept_wisdom_projection.dart';
import 'cloud_east_sync_state_wire_envelope.dart';
import 'cloud_kept_wisdom_wire_envelope.dart';

/// A request to fetch every `EASTKeptZone` change since [previousServerToken]
/// -- or, when `null`, every record currently in the zone (an initial,
/// tokenless fetch). [previousServerToken] is always opaque: produced only
/// by a prior [CloudKitZoneChangesResult.serverToken], never constructed,
/// decoded, or compared by Dart.
final class CloudKitZoneChangesRequest {
  const CloudKitZoneChangesRequest({this.previousServerToken});

  final String? previousServerToken;

  Map<Object?, Object?> toChannelArguments() => {
        'previousServerToken': previousServerToken,
      };

  /// Content-safe: never renders the opaque token itself.
  @override
  String toString() => 'CloudKitZoneChangesRequest('
      'hasPreviousServerToken: ${previousServerToken != null})';
}

/// The overall shape of a `fetchPrivateZoneChanges` result.
enum CloudKitZoneChangesOutcome {
  /// The fetch (including every page CloudKit reported via `moreComing`)
  /// completed; [CloudKitZoneChangesResult.serverToken] is the new token to
  /// present on the next incremental fetch. A zone with no changes since
  /// [CloudKitZoneChangesRequest.previousServerToken] is a successful,
  /// well-defined empty change set -- never an error. A successful result
  /// never carries any deletion-related data at all: see
  /// [unexpectedPhysicalDeletion] below.
  success,

  /// [CloudKitZoneChangesRequest.previousServerToken] is no longer valid
  /// (CloudKit's own `CKError.Code.changeTokenExpired`). The caller must
  /// discard it and retry with `previousServerToken: null` (a full
  /// resync) -- structurally distinct from every other failure because its
  /// correct handling (discard-and-resync) is categorically different from
  /// an ordinary retryable/permanent failure. See the native
  /// `CloudKitRecordTransportCoordinator` doc comment: this is a deliberate,
  /// minimal, disclosed extension of the existing symbolic-error
  /// vocabulary, the architecture document did not yet define a token-
  /// expiry outcome. This phase never mutates or persists a token itself;
  /// a caller that discards a token after this outcome and later needs
  /// zone data again must issue a fresh initial fetch
  /// (`previousServerToken: null`).
  tokenExpired,

  /// This architecture is tombstone-only
  /// (`docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §4.2): a deletion is
  /// always represented as a tombstone-form update, arriving through
  /// [CloudKitZoneChangesResult.changedKeptWisdomRecords] like any other
  /// change, never as a native CloudKit record deletion. If the native
  /// transport ever observes an actual physical-deletion notification
  /// anyway (only possible via an out-of-band actor, e.g. a manual
  /// CloudKit Dashboard action -- never this transport itself), the entire
  /// fetch fails closed with this outcome: no changed records are
  /// returned, no token is returned, and the deleted record's own name is
  /// never included anywhere in the result, an error, a log, or any
  /// `toString`. This is refused, not reported.
  unexpectedPhysicalDeletion,

  /// The fetch could not complete -- [CloudKitZoneChangesResult.errorCode]
  /// carries the reason.
  failure,

  /// Reserved for a raw payload this Dart build does not recognize --
  /// fail-closed default.
  unknown,
}

/// The full result of one `fetchPrivateZoneChanges` call. Carries no
/// deletion-name/deletion-identity field of any kind -- see
/// [CloudKitZoneChangesOutcome.unexpectedPhysicalDeletion].
final class CloudKitZoneChangesResult {
  const CloudKitZoneChangesResult._({
    required this.outcome,
    required this.changedKeptWisdomRecords,
    required this.changedSyncStateRecords,
    this.serverToken,
    this.errorCode,
  });

  factory CloudKitZoneChangesResult.success({
    required List<CloudKeptWisdomProjection> changedKeptWisdomRecords,
    required List<CloudEastSyncStateProjection> changedSyncStateRecords,
    required String serverToken,
  }) =>
      CloudKitZoneChangesResult._(
        outcome: CloudKitZoneChangesOutcome.success,
        changedKeptWisdomRecords: List.unmodifiable(changedKeptWisdomRecords),
        changedSyncStateRecords: List.unmodifiable(changedSyncStateRecords),
        serverToken: serverToken,
      );

  factory CloudKitZoneChangesResult.tokenExpired() =>
      const CloudKitZoneChangesResult._(
        outcome: CloudKitZoneChangesOutcome.tokenExpired,
        changedKeptWisdomRecords: [],
        changedSyncStateRecords: [],
      );

  /// An out-of-band physical deletion was observed. Deliberately takes no
  /// parameter of any kind -- there is nothing safe to carry about it, and
  /// nothing here for a caller to (mis)use to recover the deleted record's
  /// identity.
  factory CloudKitZoneChangesResult.unexpectedPhysicalDeletion() =>
      const CloudKitZoneChangesResult._(
        outcome: CloudKitZoneChangesOutcome.unexpectedPhysicalDeletion,
        changedKeptWisdomRecords: [],
        changedSyncStateRecords: [],
      );

  factory CloudKitZoneChangesResult.failure(String errorCode) =>
      CloudKitZoneChangesResult._(
        outcome: CloudKitZoneChangesOutcome.failure,
        changedKeptWisdomRecords: const [],
        changedSyncStateRecords: const [],
        errorCode: errorCode,
      );

  final CloudKitZoneChangesOutcome outcome;
  final List<CloudKeptWisdomProjection> changedKeptWisdomRecords;
  final List<CloudEastSyncStateProjection> changedSyncStateRecords;
  final String? serverToken;
  final String? errorCode;

  /// Strictly parses a raw `fetchPrivateZoneChanges` result payload.
  /// Rejects any top-level key outside the approved set -- there is no
  /// `deletedRecordNames` key in that set at all; a raw payload that still
  /// carries one (e.g. from a native build that has not yet been
  /// corrected) is rejected as an unrecognized key, fail-closed, never
  /// silently accepted or ignored. Every entry of
  /// `changedKeptWisdomRecords`/`changedSyncStateRecords` is decoded through
  /// the existing Phase 4C-1 wire envelopes ([CloudKeptWisdomWireEnvelope]/
  /// [CloudEastSyncStateWireEnvelope]) -- never a second, parallel
  /// validation path -- so a malformed changed record fails the entire
  /// parse closed (returns [CloudKitZoneChangesOutcome.unknown]) rather
  /// than silently dropping just that one record; the native side is
  /// responsible for never sending one that would fail this decode (native
  /// test: "changed-record strict decoding").
  static CloudKitZoneChangesResult tryParse(Map<Object?, Object?> raw) {
    const allowedKeys = {
      'outcome',
      'changedKeptWisdomRecords',
      'changedSyncStateRecords',
      'serverToken',
      'errorCode',
    };
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) {
        return const CloudKitZoneChangesResult._(
          outcome: CloudKitZoneChangesOutcome.unknown,
          changedKeptWisdomRecords: [],
          changedSyncStateRecords: [],
        );
      }
    }

    final outcomeValue = raw['outcome'];
    switch (outcomeValue) {
      case 'success':
        final keptRecords = _tryParseKeptWisdomRecords(
          raw['changedKeptWisdomRecords'],
        );
        final syncStateRecords = _tryParseSyncStateRecords(
          raw['changedSyncStateRecords'],
        );
        final serverToken = raw['serverToken'];
        if (keptRecords == null ||
            syncStateRecords == null ||
            serverToken is! String ||
            serverToken.isEmpty) {
          return const CloudKitZoneChangesResult._(
            outcome: CloudKitZoneChangesOutcome.unknown,
            changedKeptWisdomRecords: [],
            changedSyncStateRecords: [],
          );
        }
        return CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: keptRecords,
          changedSyncStateRecords: syncStateRecords,
          serverToken: serverToken,
        );
      case 'tokenExpired':
        return CloudKitZoneChangesResult.tokenExpired();
      case 'unexpectedPhysicalDeletion':
        return CloudKitZoneChangesResult.unexpectedPhysicalDeletion();
      case 'failure':
        final errorCode = raw['errorCode'];
        if (errorCode is! String || errorCode.isEmpty) {
          return const CloudKitZoneChangesResult._(
            outcome: CloudKitZoneChangesOutcome.unknown,
            changedKeptWisdomRecords: [],
            changedSyncStateRecords: [],
          );
        }
        return CloudKitZoneChangesResult.failure(errorCode);
      default:
        return const CloudKitZoneChangesResult._(
          outcome: CloudKitZoneChangesOutcome.unknown,
          changedKeptWisdomRecords: [],
          changedSyncStateRecords: [],
        );
    }
  }

  static List<CloudKeptWisdomProjection>? _tryParseKeptWisdomRecords(
    Object? raw,
  ) {
    if (raw is! List) return null;
    final parsed = <CloudKeptWisdomProjection>[];
    for (final entry in raw) {
      if (entry is! Map<Object?, Object?>) return null;
      final projection = CloudKeptWisdomWireEnvelope.tryDecode(entry);
      if (projection == null) return null;
      parsed.add(projection);
    }
    return parsed;
  }

  static List<CloudEastSyncStateProjection>? _tryParseSyncStateRecords(
    Object? raw,
  ) {
    if (raw is! List) return null;
    final parsed = <CloudEastSyncStateProjection>[];
    for (final entry in raw) {
      if (entry is! Map<Object?, Object?>) return null;
      final projection = CloudEastSyncStateWireEnvelope.tryDecode(entry);
      if (projection == null) return null;
      parsed.add(projection);
    }
    return parsed;
  }

  /// Content-safe: [changedKeptWisdomRecords]/[changedSyncStateRecords] are
  /// never rendered directly -- only their counts. No deleted-record
  /// identity is ever a field on this class, so there is nothing of that
  /// kind for this (or any) `toString` to expose.
  @override
  String toString() => 'CloudKitZoneChangesResult(outcome: $outcome, '
      'changedKeptWisdomCount: ${changedKeptWisdomRecords.length}, '
      'changedSyncStateCount: ${changedSyncStateRecords.length}, '
      'errorCode: $errorCode)';
}
