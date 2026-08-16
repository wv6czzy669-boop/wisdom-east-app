/// Build 26 Phase 4E-5: a stateful, test-only stand-in for one real private
/// CloudKit database's `EASTKeptZone` -- shared by every
/// `E2ECloudKitPlatformBridge` (see `sync_device_harness.dart`) that
/// represents an independent simulated device signed into the SAME iCloud
/// account, exactly as a real CloudKit private database is shared
/// server-side across a user's own devices. This class is not itself a
/// device: it owns no local Kept/Reflection state, no intent store, no
/// account-bucket bootstrap state -- only the remote records a real private
/// database would hold.
///
/// Deliberately narrow, per the Phase 4E-5 read-only audit's design:
///
/// - Maintains remote records keyed by their deterministic CloudKit
///   `recordName`, storing each record's `recordType`, its exact wire-level
///   `fields` map (as already produced by the REAL `CloudKitRecordChangeInput`
///   -- never a second, competing field shape), an opaque, freshly-minted
///   `systemFields` value per successful write, and the global monotonic
///   change-sequence number that write landed at.
/// - `modify` reproduces exactly the conditional-save semantics
///   `CloudKitRecordChangeInput.previousSystemFields` already documents:
///   `null` -> unconditional save; non-null -> accept only if it equals the
///   record's currently-stored `systemFields`, else a per-record failure
///   using the existing `syncErrorCodeServerRecordChanged` symbolic code --
///   never a new error vocabulary of this file's own invention.
/// - `fetch` reproduces exactly `CloudKitZoneChangesRequest
///   .previousServerToken`'s documented semantics: `null` -> a full baseline
///   of every currently-stored record; a non-null (opaque, self-issued)
///   token -> only the records whose change-sequence is newer than that
///   token's own sequence.
/// - Every returned projection is decoded through the REAL, existing wire
///   codecs (`CloudKeptWisdomWireEnvelope.tryDecodeIncoming`/
///   `CloudEastSyncStateWireEnvelope.tryDecode`) -- this file never
///   reimplements or reinterprets a single projection field itself, so it
///   cannot silently drift from what production's own transport boundary
///   actually accepts.
/// - Implements no domain conflict-resolution rule of any kind: no Kept
///   winner precedence, no Reflection merge precedence, no tombstone-vs-
///   active winner, no `mutationId` tie-breaking beyond the transport-level
///   `previousSystemFields` identity check above, and no `DataEpoch`
///   business semantics. Those remain exclusively the responsibility of the
///   real production coordinators/resolver this harness exercises
///   end-to-end (`resolveKeptWisdomConflict`, `KeptSyncBootstrapCoordinator`,
///   `IncomingKeptSyncCoordinator`).
/// - Models physical record deletion only via
///   [forceUnexpectedPhysicalDeletionOnNextFetch] -- current production
///   physical-deletion semantics remain fail-closed
///   (`CloudKitZoneChangesOutcome.unexpectedPhysicalDeletion`); this class
///   never otherwise removes a stored record (a logical delete is always
///   represented, exactly as production requires, by a tombstone-form
///   `CKKeptWisdom` update).
///
/// Synthetic content only; no real MethodChannel, no real CloudKit
/// container, no network access anywhere in this file.
library;

import 'dart:convert';

import 'package:wisdom_app/sync/cloud_east_sync_state_projection.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/sync_error_classification.dart';
import 'package:wisdom_app/sync_platform/cloud_east_sync_state_wire_envelope.dart';
import 'package:wisdom_app/sync_platform/cloud_kept_wisdom_wire_envelope.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_delete_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_kept_wisdom_record_names_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_modify_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_sync_state_epoch_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_changes_contract.dart';

/// One record as the synthetic server itself stores it -- deliberately not
/// a `CloudKeptWisdomProjection`/`CloudEastSyncStateProjection` directly, so
/// this file never has to guess which decoder applies without first
/// consulting [recordType].
class _StoredServerRecord {
  _StoredServerRecord({
    required this.recordType,
    required this.fields,
    required this.systemFields,
    required this.changeSeq,
  });

  final String recordType;
  final Map<Object?, Object?> fields;
  final String systemFields;
  final int changeSeq;
}

/// Test-only, in-memory, stateful CloudKit private-database stand-in. See
/// the library doc comment for the full semantics contract.
class SyntheticCloudKitServer {
  final Map<String, _StoredServerRecord> _records = {};
  int _sequence = 0;

  String? _forceModifyTransportFailureCode;
  String? _forceFetchTransportFailureCode;
  bool _forceTokenExpiredOnNextFetch = false;
  bool _forceUnexpectedPhysicalDeletionOnNextFetch = false;

  // ---------------------------------------------------------------------
  // Section B: deterministic, one-shot fault injection. Each hook fires
  // exactly once and clears itself the moment it is consumed by [modify]/
  // [fetch] -- no sleeps, no polling, no wall-clock races.
  // ---------------------------------------------------------------------

  /// The next [modify] call fails at the transport level -- no per-record
  /// outcome is ever produced, mirroring
  /// `CloudKitModifyRecordsOverallStatus.transportFailure`.
  void forceTransportFailureOnNextModify([
    String code = syncErrorCodeNetworkFailure,
  ]) {
    _forceModifyTransportFailureCode = code;
  }

  /// The next [fetch] call fails at the transport level, mirroring
  /// `CloudKitZoneChangesOutcome.failure`.
  void forceTransportFailureOnNextFetch([
    String code = syncErrorCodeNetworkFailure,
  ]) {
    _forceFetchTransportFailureCode = code;
  }

  /// The next [fetch] call reports `CloudKitZoneChangesOutcome.tokenExpired`
  /// regardless of the token presented.
  void forceTokenExpiredOnNextFetch() {
    _forceTokenExpiredOnNextFetch = true;
  }

  /// The next [fetch] call reports
  /// `CloudKitZoneChangesOutcome.unexpectedPhysicalDeletion`.
  void forceUnexpectedPhysicalDeletionOnNextFetch() {
    _forceUnexpectedPhysicalDeletionOnNextFetch = true;
  }

  // ---------------------------------------------------------------------
  // Scenario 18 support only: a controlled, test-only stand-in for an
  // externally-driven `CKEastSyncState` change (e.g. a real Delete All
  /// Synced Data on some other, out-of-scope client). Never used to
  // simulate an ordinary simulated device's own upload -- every simulated
  // device's own control-record creation always goes through [modify],
  // exactly as production's own `KeptSyncBootstrapCoordinator` requires.
  // ---------------------------------------------------------------------

  void seedControlRecordDirectly(CloudEastSyncStateProjection projection) {
    final fields = CloudEastSyncStateWireEnvelope.encode(projection);
    _sequence += 1;
    _records[CloudEastSyncStateProjection.recordName] = _StoredServerRecord(
      recordType: CloudEastSyncStateProjection.recordType,
      fields: fields,
      systemFields: _mintSystemFields(CloudEastSyncStateProjection.recordName),
      changeSeq: _sequence,
    );
  }

  // ---------------------------------------------------------------------
  // Section A: modify/fetch.
  // ---------------------------------------------------------------------

  Future<CloudKitModifyRecordsResult> modify(
    CloudKitModifyRecordsRequest request,
  ) async {
    final failureCode = _forceModifyTransportFailureCode;
    if (failureCode != null) {
      _forceModifyTransportFailureCode = null;
      return CloudKitModifyRecordsResult.transportFailure(failureCode);
    }

    final outcomes = <CloudKitRecordModifyOutcome>[];
    var anyFailure = false;

    for (final input in request.records) {
      final recordName = input.fields['recordName'];
      if (recordName is! String || recordName.isEmpty) {
        throw StateError(
          'SyntheticCloudKitServer received a CloudKitRecordChangeInput '
          'with no recordName -- this indicates a test-harness bug (every '
          'real CloudKitRecordChangeInput always carries one).',
        );
      }

      final current = _records[recordName];
      final previous = input.previousSystemFields;

      // Conditional-save semantics -- mirrors the native transport's own
      // `.ifServerRecordUnchanged` policy exactly. `previous == null` is
      // always an unconditional save (`.changedKeys`-equivalent), even if a
      // record already exists under this name.
      if (previous != null && current?.systemFields != previous) {
        anyFailure = true;
        outcomes.add(
          CloudKitRecordModifyOutcome.failure(
            recordName: recordName,
            errorCode: syncErrorCodeServerRecordChanged,
          ),
        );
        continue;
      }

      _sequence += 1;
      final freshSystemFields = _mintSystemFields(recordName);
      _records[recordName] = _StoredServerRecord(
        recordType: input.recordType,
        fields: input.fields,
        systemFields: freshSystemFields,
        changeSeq: _sequence,
      );
      outcomes.add(
        CloudKitRecordModifyOutcome.success(
          recordName: recordName,
          systemFields: freshSystemFields,
        ),
      );
    }

    // An empty request is a valid, well-defined no-op -- `anyFailure`
    // remains `false` and `outcomes` remains empty, matching
    // `CloudKitModifyRecordsOverallStatus.allSucceeded`'s own documented
    // "empty modify request behavior" exactly.
    return anyFailure
        ? CloudKitModifyRecordsResult.partialFailure(outcomes)
        : CloudKitModifyRecordsResult.allSucceeded(outcomes);
  }

  Future<CloudKitZoneChangesResult> fetch(
    CloudKitZoneChangesRequest request,
  ) async {
    final failureCode = _forceFetchTransportFailureCode;
    if (failureCode != null) {
      _forceFetchTransportFailureCode = null;
      return CloudKitZoneChangesResult.failure(failureCode);
    }
    if (_forceTokenExpiredOnNextFetch) {
      _forceTokenExpiredOnNextFetch = false;
      return CloudKitZoneChangesResult.tokenExpired();
    }
    if (_forceUnexpectedPhysicalDeletionOnNextFetch) {
      _forceUnexpectedPhysicalDeletionOnNextFetch = false;
      return CloudKitZoneChangesResult.unexpectedPhysicalDeletion();
    }

    final previousToken = request.previousServerToken;
    final sinceSeq = previousToken == null ? 0 : _decodeToken(previousToken);

    final changed = _records.values
        .where((stored) => stored.changeSeq > sinceSeq)
        .toList(growable: false)
      ..sort((a, b) => a.changeSeq.compareTo(b.changeSeq));

    final keptProjections = <CloudKeptWisdomProjection>[];
    final syncStateProjections = <CloudEastSyncStateProjection>[];
    final systemFieldsByRecordName = <String, String>{};

    for (final stored in changed) {
      if (stored.recordType == CloudKeptWisdomProjection.recordType) {
        final decoded = CloudKeptWisdomWireEnvelope.tryDecodeIncoming({
          ...stored.fields,
          'systemFields': stored.systemFields,
        });
        if (decoded == null) {
          throw StateError(
            'SyntheticCloudKitServer stored a CKKeptWisdom record that the '
            'real CloudKeptWisdomWireEnvelope could not decode back -- this '
            'indicates a test-harness bug, never a real production defect '
            '(this class never reimplements that decoder).',
          );
        }
        keptProjections.add(decoded.projection);
        systemFieldsByRecordName[decoded.projection.recordName] =
            decoded.systemFields;
      } else if (stored.recordType == CloudEastSyncStateProjection.recordType) {
        final decoded = CloudEastSyncStateWireEnvelope.tryDecode(stored.fields);
        if (decoded == null) {
          throw StateError(
            'SyntheticCloudKitServer stored a CKEastSyncState record that '
            'the real CloudEastSyncStateWireEnvelope could not decode back '
            '-- this indicates a test-harness bug.',
          );
        }
        syncStateProjections.add(decoded);
      } else {
        throw StateError(
          'SyntheticCloudKitServer stored a record of an unrecognized '
          'recordType "${stored.recordType}".',
        );
      }
    }

    return CloudKitZoneChangesResult.success(
      changedKeptWisdomRecords: keptProjections,
      changedSyncStateRecords: syncStateProjections,
      serverToken: _encodeToken(_sequence),
      keptWisdomRecordSystemFields: systemFieldsByRecordName,
    );
  }

  /// Test-only inspection: the number of records currently stored,
  /// regardless of type -- for assertions that want to prove "nothing was
  /// written" without depending on a specific record name.
  int get storedRecordCount => _records.length;

  // ---------------------------------------------------------------------
  // Build 26 Phase 5 (slice 3): the three deletion-transport methods
  // `CloudKitRemoteDeletionRunner` calls (`fetchSyncStateEpoch`/
  // `listKeptWisdomRecordNames`/`deleteKeptWisdomRecords`) -- added here,
  // on the one already-shared, already-reviewed in-memory record store,
  // rather than as a second, competing fake state model. Each reuses the
  // exact same [_records] map [modify]/[fetch] already maintain, and the
  // exact same real wire codec ([CloudEastSyncStateWireEnvelope.tryDecode])
  // `fetch` already uses -- never a second, hand-rolled decode. No fault
  // injection hook exists for these three (unlike [modify]/[fetch]) because
  // no test in this Slice needs one; `CloudKitPlatformException`-based
  // transport-failure classification is already independently covered by
  // `test/sync_deletion/cloud_kit_remote_deletion_runner_test.dart`'s own
  // small, self-contained fake bridge.
  // ---------------------------------------------------------------------

  Future<CloudKitSyncStateEpochResult> fetchSyncStateEpoch() async {
    final stored = _records[CloudEastSyncStateProjection.recordName];
    if (stored == null) return CloudKitSyncStateEpochResult.notFound();
    final decoded = CloudEastSyncStateWireEnvelope.tryDecode(stored.fields);
    if (decoded == null) {
      throw StateError(
        'SyntheticCloudKitServer stored a CKEastSyncState record that the '
        'real CloudEastSyncStateWireEnvelope could not decode back -- this '
        'indicates a test-harness bug.',
      );
    }
    return CloudKitSyncStateEpochResult.found(
      dataEpoch: decoded.dataEpoch,
      systemFields: stored.systemFields,
    );
  }

  Future<CloudKitKeptWisdomRecordNamesResult>
      listKeptWisdomRecordNames() async {
    final names = _records.entries
        .where(
          (entry) =>
              entry.value.recordType == CloudKeptWisdomProjection.recordType,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    return CloudKitKeptWisdomRecordNamesResult.success(names);
  }

  Future<CloudKitDeleteKeptWisdomRecordsResult> deleteKeptWisdomRecords(
    CloudKitDeleteKeptWisdomRecordsRequest request,
  ) async {
    final outcomes = <CloudKitRecordDeleteOutcome>[];
    for (final recordName in request.recordNames) {
      final stored = _records[recordName];
      if (stored != null &&
          stored.recordType == CloudKeptWisdomProjection.recordType) {
        _records.remove(recordName);
        outcomes.add(CloudKitRecordDeleteOutcome.success(
          recordName: recordName,
        ));
      } else {
        // Already absent (or never a CKKeptWisdom record) -- reported as a
        // per-record `unknownItem` failure, exactly as the real transport
        // would; the deletion runner itself is the one place that treats
        // this idempotently, never this fake.
        outcomes.add(CloudKitRecordDeleteOutcome.failure(
          recordName: recordName,
          errorCode: syncErrorCodeUnknownItem,
        ));
      }
    }
    final anyFailure = outcomes.any((outcome) => !outcome.success);
    return anyFailure
        ? CloudKitDeleteKeptWisdomRecordsResult.partialFailure(outcomes)
        : CloudKitDeleteKeptWisdomRecordsResult.allSucceeded(outcomes);
  }

  // ---------------------------------------------------------------------
  // Opaque token/system-fields minting. Both use real `base64Encode` over a
  // fixed byte sequence so the produced values always satisfy this
  // codebase's own `looksLikeOpaqueBase64`/`_looksLikeOpaqueSystemFields`
  // shape checks (`^[A-Za-z0-9+/]+={0,2}$`) -- never a hand-rolled string
  // that merely looks plausible.
  // ---------------------------------------------------------------------

  String _mintSystemFields(String recordName) =>
      base64Encode(utf8.encode('sf:$recordName:$_sequence'));

  String _encodeToken(int seq) => base64Encode(utf8.encode('seq:$seq'));

  int _decodeToken(String token) {
    final decoded = utf8.decode(base64Decode(token));
    if (!decoded.startsWith('seq:')) {
      throw StateError(
        'SyntheticCloudKitServer received a server token it did not itself '
        'issue: "$token".',
      );
    }
    return int.parse(decoded.substring('seq:'.length));
  }
}
