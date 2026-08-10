// Build 26 Phase 4G: SettingsScreen's explicit one-time iCloud association
// row. Widget-level tests exercise the exact same real
// KeptSyncBootstrapCoordinator/SyncAssociationController graph the
// controller-level tests do (test/controllers/sync_association_controller_test.dart)
// -- this file exists only to prove the *screen* wiring itself: the
// confirmation sheet's Cancel/Enable buttons, and that the row's displayed
// text reflects the controller's real state after each interaction. Build
// 26 Phase 4G correction (post-Mac-validation): the production controller
// was renamed from its original CloudKit-specific name to the
// platform-neutral SyncAssociationController and moved to
// lib/controllers/sync_association_controller.dart so
// SettingsScreen never contains the substring "CloudKit" (see
// test/sync_platform/cloud_kit_platform_privacy_test.dart's screen/widget
// privacy guard); this test file's own name is unaffected by that guard, so
// it keeps its original path. This file also proves regression-coverage
// item 1: SettingsScreen mounts safely with no association controller
// injected and no composition root initialized.
// Synthetic content only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/sync_association_controller.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/screens/settings_screen.dart';
import 'package:wisdom_app/services/purchase_service.dart';
import 'package:wisdom_app/sync_integration/kept_sync_bootstrap_coordinator.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_change_event.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_snapshot.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_bridge_info.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_modify_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_platform_bridge.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_changes_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_configuration_result.dart';

import 'persistence_test_helpers.dart';
import 'sync_integration/in_memory_sync_test_doubles.dart';

/// See test/controllers/sync_association_controller_test.dart's
/// identical fake for the full rationale -- duplicated here deliberately
/// (mirrors this codebase's own established precedent of a small,
/// per-test-file `CloudKitPlatformBridge` fake, e.g.
/// `kept_sync_bootstrap_coordinator_test.dart`'s and
/// `sync_orchestrator_test.dart`'s own independent copies) rather than
/// shared, since only `getAccountSnapshot` is ever exercised.
class _FixedCloudKitPlatformBridge implements CloudKitPlatformBridge {
  _FixedCloudKitPlatformBridge(this.snapshot);

  final CloudKitAccountSnapshot snapshot;

  @override
  Future<CloudKitAccountSnapshot> getAccountSnapshot() async => snapshot;

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
  TestWidgetsFlutterBinding.ensureInitialized();

  const fingerprintA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const rowKey = ValueKey('settings-icloud-sync-row');

  late KeptRepositoryTestGraph keptGraph;
  late InMemorySyncPersistenceStore syncPersistenceStore;
  late SyncAssociationController controller;
  late int requestSyncCallCount;

  setUp(() {
    keptGraph = KeptRepositoryTestGraph();
    keptGraph.seed([
      KeptRecord(
        id: 'local-only-1',
        revealId: 'aaaaaaaa-1111-4111-8111-111111111111',
        wisdomText: 'Be still and know.',
        revealedAt: DateTime.utc(2026, 8, 1),
        keptAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
        mutationId: 'eeeeeeee-1111-4111-8111-111111111111',
      ),
    ]);
    syncPersistenceStore = InMemorySyncPersistenceStore();
    final bridge = _FixedCloudKitPlatformBridge(
      const CloudKitAccountSnapshot(
        availability: CloudKitAccountAvailability.available,
        isPrivateDatabaseUsable: true,
        accountFingerprint: fingerprintA,
        fingerprintResolved: true,
        bridgeVersion: 1,
      ),
    );
    final bootstrapCoordinator = KeptSyncBootstrapCoordinator(
      bridge: bridge,
      keptRepository: keptGraph.repository,
      intentStore: InMemoryLocalSyncIntentStore(),
      syncPersistenceStore: syncPersistenceStore,
    );
    requestSyncCallCount = 0;
    controller = SyncAssociationController(
      bootstrapCoordinator: bootstrapCoordinator,
      requestSyncAfterAssociation: () {
        requestSyncCallCount += 1;
      },
    );
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          purchaseService: PurchaseService(),
          cloudKitAssociationController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'associationRequired: the row shows Not enabled and is tappable',
      (tester) async {
    await pumpSettings(tester);

    expect(find.text('iCloud Sync'), findsOneWidget);
    expect(find.text('Not enabled'), findsOneWidget);
  });

  testWidgets(
      'B. tapping Cancel in the confirmation sheet never authorizes '
      'association', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(rowKey));
    await tester.pumpAndSettle();

    expect(find.text('Enable iCloud Sync?'), findsOneWidget);
    expect(
      find.text(
        'Your Kept wisdoms and Reflections will be stored in your private '
        'iCloud database and kept in sync across your devices.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Your daily ritual timing stays on this device.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      await syncPersistenceStore.loadAssociatedAccountFingerprint(),
      isNull,
    );
    expect(requestSyncCallCount, 0);
    expect(find.text('Not enabled'), findsOneWidget);
  });

  testWidgets(
      'confirming Enable authorizes association, requests a sync, and the '
      'row updates to Enabled', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(rowKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();

    expect(
      await syncPersistenceStore.loadAssociatedAccountFingerprint(),
      fingerprintA,
    );
    expect(requestSyncCallCount, 1);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Not enabled'), findsNothing);
  });

  testWidgets(
      'G. an already-associated account shows Enabled with no consent '
      'prompt available', (tester) async {
    syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintA);

    await pumpSettings(tester);

    expect(find.text('Enabled'), findsOneWidget);

    await tester.tap(find.byKey(rowKey));
    await tester.pumpAndSettle();

    expect(find.text('Enable iCloud Sync?'), findsNothing);
  });

  testWidgets(
      'regression-coverage item 1: SettingsScreen mounts safely with no '
      'association controller injected and no composition root initialized '
      '-- the row is present but reports Not enabled and is not actionable, '
      'with no LateInitializationError and no CloudKit/native call of any '
      'kind', (tester) async {
    // Deliberately no `cloudKitAssociationController:` override and no
    // `app_services.initializeKeptStorage()` call anywhere in this test --
    // this is exactly the isolated-widget-test shape
    // test/home_screen_test.dart's own Home -> Settings navigation and
    // native edge-swipe Settings route tests already use, which is what
    // previously crashed with `LateInitializationError: Field
    // 'cloudKitAssociationController' has not been initialized.` `null` is
    // now a normal, safe state for that composition-root global (see
    // `app_services.dart`'s own doc comment).
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('iCloud Sync'), findsOneWidget);
    expect(find.text('Not enabled'), findsOneWidget);

    // Not actionable: tapping the row must never surface the confirmation
    // sheet when no controller is available to act on a confirmed Enable.
    await tester.tap(find.byKey(rowKey));
    await tester.pumpAndSettle();

    expect(find.text('Enable iCloud Sync?'), findsNothing);
  });
}
