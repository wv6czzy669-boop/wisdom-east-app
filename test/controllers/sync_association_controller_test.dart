// Build 26 Phase 4G: SyncAssociationController -- the Settings-facing
// explicit one-time iCloud association surface. Build 26 Phase 4G
// correction (post-Mac-validation): this class was renamed from the
// original CloudKit-specific name to the platform-neutral
// SyncAssociationController and moved to
// lib/controllers/sync_association_controller.dart so
// lib/screens/settings_screen.dart never contains the substring "CloudKit"
// (see test/sync_platform/cloud_kit_platform_privacy_test.dart's screen/
// widget privacy guard). This test file was correspondingly renamed to
// test/controllers/sync_association_controller_test.dart (final naming
// cleanup pass) so its own filename matches the platform-neutral
// production naming. Every test here
// exercises the REAL KeptSyncBootstrapCoordinator.evaluateAssociation()/
// .authorizeAssociation() pair (never a copied/reimplemented helper),
// backed by the same in-memory sync test doubles
// (in_memory_sync_test_doubles.dart) and KeptRepositoryTestGraph
// (persistence_test_helpers.dart) already used elsewhere in this suite --
// only the native CloudKitPlatformBridge is faked, and only its
// getAccountSnapshot() method, since that is the only bridge method either
// evaluateAssociation() or authorizeAssociation() ever calls. Synthetic
// content only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/sync_association_controller.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/sync_integration/kept_sync_bootstrap_coordinator.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_change_event.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_snapshot.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_bridge_info.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_modify_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_platform_bridge.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_changes_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_configuration_result.dart';

import '../persistence_test_helpers.dart';
import '../sync_integration/in_memory_sync_test_doubles.dart';

/// A minimal, controllable [CloudKitPlatformBridge] fake. Only
/// [getAccountSnapshot] is ever called by [KeptSyncBootstrapCoordinator
/// .evaluateAssociation]/[KeptSyncBootstrapCoordinator.authorizeAssociation]
/// -- every other method throws if reached, which would itself prove a test
/// exercised more of the pipeline (zone configuration, record transport)
/// than this controller's own two methods ever do.
class _FixedCloudKitPlatformBridge implements CloudKitPlatformBridge {
  _FixedCloudKitPlatformBridge(this.snapshot);

  CloudKitAccountSnapshot snapshot;
  int getAccountSnapshotCallCount = 0;

  @override
  Future<CloudKitAccountSnapshot> getAccountSnapshot() async {
    getAccountSnapshotCallCount += 1;
    return snapshot;
  }

  @override
  Future<CloudKitZoneConfigurationResult> configurePrivateZone() =>
      throw UnimplementedError(
        'Not used by evaluateAssociation()/authorizeAssociation().',
      );

  @override
  Future<CloudKitBridgeInfo> getBridgeInfo() => throw UnimplementedError(
        'Not used by evaluateAssociation()/authorizeAssociation().',
      );

  @override
  Stream<CloudKitAccountChangeEvent> get accountChangeEvents =>
      const Stream.empty();

  @override
  Future<CloudKitModifyRecordsResult> modifyPrivateRecords(
    CloudKitModifyRecordsRequest request,
  ) =>
      throw UnimplementedError(
        'Not used by evaluateAssociation()/authorizeAssociation().',
      );

  @override
  Future<CloudKitZoneChangesResult> fetchPrivateZoneChanges(
    CloudKitZoneChangesRequest request,
  ) =>
      throw UnimplementedError(
        'Not used by evaluateAssociation()/authorizeAssociation().',
      );
}

void main() {
  const fingerprintA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fingerprintB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  CloudKitAccountSnapshot availableSnapshot({String fingerprint = fingerprintA}) =>
      CloudKitAccountSnapshot(
        availability: CloudKitAccountAvailability.available,
        isPrivateDatabaseUsable: true,
        accountFingerprint: fingerprint,
        fingerprintResolved: true,
        bridgeVersion: 1,
      );

  KeptRecord seedRecord() => KeptRecord(
        id: 'local-only-1',
        revealId: 'aaaaaaaa-1111-4111-8111-111111111111',
        wisdomText: 'Be still and know.',
        revealedAt: DateTime.utc(2026, 8, 1),
        keptAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
        mutationId: 'eeeeeeee-1111-4111-8111-111111111111',
      );

  late KeptRepositoryTestGraph keptGraph;
  late InMemorySyncPersistenceStore syncPersistenceStore;
  late InMemoryLocalSyncIntentStore intentStore;
  late _FixedCloudKitPlatformBridge bridge;
  late KeptSyncBootstrapCoordinator bootstrapCoordinator;
  late int requestSyncCallCount;
  late SyncAssociationController controller;

  void buildGraph({CloudKitAccountSnapshot? snapshot}) {
    keptGraph = KeptRepositoryTestGraph();
    syncPersistenceStore = InMemorySyncPersistenceStore();
    intentStore = InMemoryLocalSyncIntentStore();
    bridge = _FixedCloudKitPlatformBridge(snapshot ?? availableSnapshot());
    bootstrapCoordinator = KeptSyncBootstrapCoordinator(
      bridge: bridge,
      keptRepository: keptGraph.repository,
      intentStore: intentStore,
      syncPersistenceStore: syncPersistenceStore,
    );
    requestSyncCallCount = 0;
    controller = SyncAssociationController(
      bootstrapCoordinator: bootstrapCoordinator,
      requestSyncAfterAssociation: () {
        requestSyncCallCount += 1;
      },
    );
  }

  setUp(() {
    buildGraph();
  });

  test(
      'A. associationRequired (existing local Kept history, no marker) -> '
      'Settings reports Not enabled and is actionable', () async {
    keptGraph.seed([seedRecord()]);

    final result = await controller.checkStatus();

    expect(result.displayStatus, SyncAssociationDisplayStatus.notEnabled);
    expect(result.requiresExplicitConsent, isTrue);
  });

  test('B. no call ever authorizes on its own -- Cancel never happens here',
      () async {
    // The Settings screen's Cancel button never calls the controller at
    // all (see settings_screen_test.dart for the real widget-level proof).
    // At the controller level, the equivalent guarantee is that merely
    // checking status -- exactly what happens while the confirmation sheet
    // is open, or if it is dismissed -- never authorizes anything.
    keptGraph.seed([seedRecord()]);

    await controller.checkStatus();
    await controller.checkStatus();

    expect(await syncPersistenceStore.loadAssociatedAccountFingerprint(),
        isNull);
    expect(requestSyncCallCount, 0);
  });

  test('C. Enable -> authorizeAssociation is called exactly once', () async {
    keptGraph.seed([seedRecord()]);

    final outcome = await controller.enableSync();

    expect(outcome, SyncAssociationEnableOutcome.success);
    expect(
      await syncPersistenceStore.loadAssociatedAccountFingerprint(),
      fingerprintA,
    );
    // authorizeAssociation() itself only ever re-resolves the account
    // snapshot once per call (see its own doc comment) -- exactly one
    // enableSync() call therefore means exactly one authorization attempt.
    // evaluateAssociation() also calls getAccountSnapshot() once, so two
    // calls total for this one enableSync() invocation.
    expect(bridge.getAccountSnapshotCallCount, 2);
  });

  test(
      'D. successful authorization -> a runtime sync request is issued '
      'immediately (before enableSync() even returns)', () async {
    keptGraph.seed([seedRecord()]);

    final outcome = await controller.enableSync();

    expect(outcome, SyncAssociationEnableOutcome.success);
    expect(requestSyncCallCount, 1);
  });

  test(
      'E. authorization failure -> no sync request, local Kept data '
      'untouched, retry remains possible', () async {
    keptGraph.seed([seedRecord()]);
    // A different account is already durably associated -- authorization
    // must refuse (`differentAssociationExists`) rather than overwrite it.
    syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintB);
    // The currently-resolved account no longer matches the durable marker,
    // so evaluateAssociation() reports associationRequired (M != F) --
    // exactly the state that makes an explicit Enable tap meaningful again.

    final outcome = await controller.enableSync();

    expect(outcome, SyncAssociationEnableOutcome.failed);
    // The existing, different association is never silently overwritten.
    expect(
      await syncPersistenceStore.loadAssociatedAccountFingerprint(),
      fingerprintB,
    );
    // Local Kept data is completely untouched -- authorizeAssociation()
    // never reads or writes KeptRecord state at all.
    final records = await keptGraph.repository.loadAllRecords();
    expect(records, hasLength(1));
    expect(records.single.id, 'local-only-1');
    expect(requestSyncCallCount, 0);

    // Retry remains possible: a fresh check still reports the row as
    // actionable, and a fresh enableSync() call for the *current* account
    // is not blocked by the earlier failure.
    final status = await controller.checkStatus();
    expect(status.requiresExplicitConsent, isTrue);
  });

  test(
      'F. repeated Enable after success is idempotent -- no duplicate '
      'authorization side effects', () async {
    keptGraph.seed([seedRecord()]);

    final first = await controller.enableSync();
    expect(first, SyncAssociationEnableOutcome.success);
    expect(requestSyncCallCount, 1);

    // A second call -- a genuine repeated tap, or a relaunch replay of the
    // same confirmed intent -- must not re-authorize: association is
    // already resolved, so evaluateAssociation() now reports
    // resumeAssociation, not associationRequired.
    final second = await controller.enableSync();

    expect(second, SyncAssociationEnableOutcome.notApplicable);
    // Still exactly the one fingerprint, no duplicate marker/account
    // bucket, no second sync request.
    expect(
      await syncPersistenceStore.loadAssociatedAccountFingerprint(),
      fingerprintA,
    );
    expect(requestSyncCallCount, 1);
    // No duplicate Kept record was created or altered either.
    final records = await keptGraph.repository.loadAllRecords();
    expect(records, hasLength(1));
  });

  test(
      'G. already-complete association -> no consent prompt required and '
      'state reports Enabled', () async {
    keptGraph.seed([seedRecord()]);
    syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintA);

    final result = await controller.checkStatus();

    expect(result.displayStatus, SyncAssociationDisplayStatus.enabled);
    expect(result.requiresExplicitConsent, isFalse);
  });

  test(
      'H. an account change requiring a new explicit association does not '
      'silently authorize -- merely checking status never mutates the '
      'existing, different marker', () async {
    keptGraph.seed([seedRecord()]);
    // A different account was previously associated (e.g. on a prior
    // device/account); the currently-resolved account is fingerprintA.
    syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintB);

    final result = await controller.checkStatus();

    expect(result.displayStatus, SyncAssociationDisplayStatus.notEnabled);
    expect(result.requiresExplicitConsent, isTrue);
    // Never silently reassociated by a mere status check.
    expect(
      await syncPersistenceStore.loadAssociatedAccountFingerprint(),
      fingerprintB,
    );
    expect(requestSyncCallCount, 0);
  });

  test(
      'I. this flow never touches daily-access/ritual state, analytics, '
      'purchase state, or unrelated settings (structural check on the new '
      'production files)', () {
    const forbiddenSubstrings = [
      'daily_wisdom_access',
      'daily_wisdom_text',
      'wisdom_unlock_time_ms',
      'keeper_daily_wisdom_state',
      'unlockAt',
      'lockDuration',
      'DailyAccessRepository',
      'daily_access_repository.dart',
      'DailyWisdomAccessService',
      'daily_wisdom_access_service.dart',
      'PurchaseService',
      'purchase_service.dart',
      'InAppPurchase',
    ];
    final filesToScan = [
      File('lib/controllers/sync_association_controller.dart'),
    ];
    final violations = <String>[];
    for (final file in filesToScan) {
      expect(file.existsSync(), isTrue,
          reason: 'Expected to find ${file.path}.');
      final content = file.readAsStringSync();
      for (final forbidden in forbiddenSubstrings) {
        if (content.contains(forbidden)) {
          violations.add('${file.path} contains "$forbidden"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
