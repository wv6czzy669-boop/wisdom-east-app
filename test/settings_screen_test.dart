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
import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/icloud_removal_controller.dart';
import 'package:wisdom_app/controllers/sync_association_controller.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/screens/settings_screen.dart';
import 'package:wisdom_app/services/data_export_service.dart';
import 'package:wisdom_app/services/purchase_service.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync_integration/kept_sync_bootstrap_coordinator.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/associated_account_fingerprint_commit.dart';
import 'package:wisdom_app/sync_persistence/deletion_transaction_result.dart';
import 'package:wisdom_app/sync_persistence/incoming_batch_checkpoint.dart';
import 'package:wisdom_app/sync_persistence/outbox_mutation_retirement.dart';
import 'package:wisdom_app/sync_persistence/pending_deletion_transaction.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_store.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_change_event.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_snapshot.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_bridge_info.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_delete_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_kept_wisdom_record_names_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_modify_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_platform_bridge.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_sync_state_epoch_contract.dart';
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

  // Build 26 Phase 5 (slice 2): the three deletion-runner-only bridge
  // methods -- never used by evaluateAssociation()/authorizeAssociation()
  // or by this screen's own settings flow.
  @override
  Future<CloudKitSyncStateEpochResult> fetchSyncStateEpoch() =>
      throw UnimplementedError(
        'Not used by evaluateAssociation()/authorizeAssociation().',
      );

  @override
  Future<CloudKitKeptWisdomRecordNamesResult> listKeptWisdomRecordNames() =>
      throw UnimplementedError(
        'Not used by evaluateAssociation()/authorizeAssociation().',
      );

  @override
  Future<CloudKitDeleteKeptWisdomRecordsResult> deleteKeptWisdomRecords(
    CloudKitDeleteKeptWisdomRecordsRequest request,
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

  const removalRowKey = ValueKey('settings-remove-from-icloud-row');

  late KeptRepositoryTestGraph keptGraph;
  late InMemorySyncPersistenceStore syncPersistenceStore;
  late SyncAssociationController controller;
  late int requestSyncCallCount;
  late ICloudRemovalController icloudRemovalController;
  late int requestRemovalSyncCallCount;

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
    requestRemovalSyncCallCount = 0;
    icloudRemovalController = ICloudRemovalController(
      syncPersistenceStore: syncPersistenceStore,
      requestSyncAfterRemoval: () {
        requestRemovalSyncCallCount += 1;
      },
    );
  });

  Future<void> tapExportRow(WidgetTester tester) async {
    final row = find.byKey(const ValueKey('settings-export-data-row'));
    // The row sits below the fold at the default test viewport size --
    // scroll it into view before tapping, exactly as a real user would
    // scroll Settings to reach it.
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
  }

  Future<void> pumpSettings(
    WidgetTester tester, {
    ICloudRemovalController? removalController,
    DataExportService? dataExportService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          purchaseService: PurchaseService(),
          cloudKitAssociationController: controller,
          icloudRemovalController: removalController ?? icloudRemovalController,
          dataExportService: dataExportService,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('associationRequired: the row shows Not enabled and is tappable',
      (tester) async {
    await pumpSettings(tester);

    expect(find.text('iCloud Sync'), findsOneWidget);
    expect(find.text('Not enabled'), findsOneWidget);
  });

  testWidgets(
      'Settings uses the localized centered app-screen heading and no longer '
      'repeats the EAST brand block', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('EAST.'), findsNothing);
    expect(find.text('Where silence speaks.'), findsNothing);
    expect(find.byType(Divider), findsNWidgets(3));

    final title = tester.widget<Text>(find.text('Settings'));
    expect(title.style?.fontSize, 24);
    expect(tester.widget<AppBar>(find.byType(AppBar)).centerTitle, isTrue);

    final semantics = tester.ensureSemantics();
    final titleNode = tester.getSemantics(find.text('Settings'));
    expect(titleNode.getSemanticsData().flagsCollection.isHeader, isTrue);
    semantics.dispose();
  });

  testWidgets(
      'every Settings row title uses the exact iCloud Sync typography while '
      'subtitle hierarchy stays independent', (tester) async {
    await pumpSettings(tester);

    const titles = [
      'Keeper',
      'Restore Purchases',
      'iCloud Sync',
      'Remove from iCloud',
      'Export My Data',
      'Language',
      'Appearance',
      'EAST. Productions',
      'Privacy Policy',
      'Reach Out',
    ];
    final reference = tester.widget<Text>(find.text('iCloud Sync')).style!;
    for (final title in titles) {
      final style = tester.widget<Text>(find.text(title)).style!;
      expect(style.fontSize, reference.fontSize, reason: title);
      expect(style.fontFamily, reference.fontFamily, reason: title);
      expect(style.fontWeight, reference.fontWeight, reason: title);
      expect(style.letterSpacing, reference.letterSpacing, reason: title);
      expect(style.height, reference.height, reason: title);
    }

    expect(reference.fontSize, 21);
    expect(find.text('Support the circle, keep what stays.'), findsOneWidget);
    expect(
      find.text('Take your Kept wisdoms and Reflections with you.'),
      findsOneWidget,
    );
    expect(find.text('The world beyond the ritual.'), findsOneWidget);
  });

  testWidgets('Settings heading resolves in every product locale',
      (tester) async {
    for (final target in EastLocaleRegistry.targets) {
      await tester.pumpWidget(
        MaterialApp(
          locale: target.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: EastLocaleRegistry.runtimeSupported,
          home: const SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final expected = lookupAppLocalizations(target.locale).settings;
      expect(
        find.text(expected),
        findsOneWidget,
        reason: 'locale=${target.tag}',
      );
    }
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

    await tester.tap(find.text('CANCEL'));
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

    await tester.tap(find.text('ENABLE'));
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

  // ---------------------------------------------------------------------
  // Build 26 Phase 5 (final slice): the "Remove from iCloud" row.
  // ---------------------------------------------------------------------

  const fingerprintB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  group('Remove from iCloud', () {
    testWidgets('1. the row and its action exist', (tester) async {
      syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintA);

      await pumpSettings(tester);

      expect(find.text('Remove from iCloud'), findsOneWidget);
      expect(find.byKey(removalRowKey), findsOneWidget);
      // Actionable: an account is associated and nothing is pending.
      await tester.tap(find.byKey(removalRowKey));
      await tester.pumpAndSettle();
      expect(find.text('Remove from iCloud?'), findsOneWidget);
    });

    testWidgets('2. the confirmation copy is exact', (tester) async {
      syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintA);

      await pumpSettings(tester);
      await tester.tap(find.byKey(removalRowKey));
      await tester.pumpAndSettle();

      expect(find.text('Remove from iCloud?'), findsOneWidget);
      expect(
        find.text(
          'Your Kept wisdoms and Reflections will remain on this iPhone.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Their iCloud copies will be removed, and iCloud Sync will turn '
          'off.',
        ),
        findsOneWidget,
      );
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('REMOVE'), findsOneWidget);
    });

    testWidgets(
        '3. tapping Cancel performs zero deletion mutation and requests no '
        'sync', (tester) async {
      syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintA);

      await pumpSettings(tester);
      await tester.tap(find.byKey(removalRowKey));
      await tester.pumpAndSettle();

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(
          await syncPersistenceStore.loadPendingDeletionTransaction(), isNull);
      expect(await syncPersistenceStore.loadAssociatedAccountFingerprint(),
          fingerprintA,
          reason: 'the association marker is untouched by Cancel.');
      expect(requestRemovalSyncCallCount, 0);
      expect(find.text('Remove your iCloud copies.'), findsNothing);
    });

    testWidgets(
        '4. confirming Remove starts the existing durable deletion flow -- '
        'a real PendingDeletionTransaction for the associated account, and '
        'the sync nudge is requested', (tester) async {
      syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintA);

      await pumpSettings(tester);
      await tester.tap(find.byKey(removalRowKey));
      await tester.pumpAndSettle();

      await tester.tap(find.text('REMOVE'));
      await tester.pumpAndSettle();

      final transaction =
          await syncPersistenceStore.loadPendingDeletionTransaction();
      expect(transaction, isNotNull);
      expect(transaction!.accountFingerprint, fingerprintA);
      expect(transaction.stage, DeletionTransactionStage.prepared);
      expect(requestRemovalSyncCallCount, 1);
      expect(
        find.text('Removal pending. EAST. will finish when iCloud is '
            'available.'),
        findsOneWidget,
      );
    });

    testWidgets(
        '5. a duplicate tap while the begin call is still in flight cannot '
        'start a duplicate deletion -- the underlying begin call fires '
        'exactly once', (tester) async {
      syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintA);
      final gate = Completer<void>();
      final delayedStore = _DelayedBeginSyncPersistenceStore(
        syncPersistenceStore,
        gate: gate,
      );
      var delayedCallbackCount = 0;
      final delayedController = ICloudRemovalController(
        syncPersistenceStore: delayedStore,
        requestSyncAfterRemoval: () => delayedCallbackCount += 1,
      );

      await pumpSettings(tester, removalController: delayedController);
      await tester.tap(find.byKey(removalRowKey));
      await tester.pumpAndSettle();

      await tester.tap(find.text('REMOVE'));
      // Deliberately only `pump()`, not `pumpAndSettle()` -- the begin call
      // is still awaiting `gate.future`, so `_icloudRemovalActionInProgress`
      // is now `true` and must stay `true` until the gate opens.
      await tester.pump();

      // A second tap on the row while the action is in flight: the row's
      // own onTap is already null (see `icloudRemovalAction`), so this is a
      // no-op gesture, never a second `beginRemoval()` call.
      await tester.tap(find.byKey(removalRowKey));
      await tester.pump();
      expect(find.text('Remove from iCloud?'), findsNothing,
          reason: 'a second confirmation prompt must never appear while '
              'starting.');

      expect(delayedStore.beginCallCount, 1,
          reason: 'exactly one beginDeletionTransaction call, despite the '
              'second tap.');

      gate.complete();
      await tester.pumpAndSettle();

      expect(delayedStore.beginCallCount, 1,
          reason: 'still exactly one call after the gate opens and the '
              'pass finishes.');
      expect(delayedCallbackCount, 1);
    });

    testWidgets(
        '6. an already-pending deletion transaction is represented as '
        '"Removal pending" with the offline-safe reassurance copy, and is '
        'never mistaken for idle or completed', (tester) async {
      syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintA);
      syncPersistenceStore.seedPendingDeletionTransaction(
        PendingDeletionTransaction(
          accountFingerprint: fingerprintA,
          originalDataEpoch: null,
          replacementDataEpoch: DataEpoch.generate(),
          stage: DeletionTransactionStage.cloudPurgePending,
        ),
      );

      await pumpSettings(tester);

      expect(
        find.text('Removal pending. EAST. will finish when iCloud is '
            'available.'),
        findsOneWidget,
      );
      expect(find.text('Remove your iCloud copies.'), findsNothing);
      expect(find.text('Removed from iCloud.'), findsNothing);

      // Tapping while pending re-reads state only -- it must never show a
      // second confirmation prompt and must never start a second
      // transaction.
      await tester.tap(find.byKey(removalRowKey));
      await tester.pumpAndSettle();
      expect(find.text('Remove from iCloud?'), findsNothing);
      expect(requestRemovalSyncCallCount, 0);
    });

    testWidgets(
        '7. the completed confirmation is shown only after this screen '
        'itself observes the durable transaction go from pending to gone -- '
        'never fabricated, and never shown on a fresh mount that never '
        'watched the transition happen', (tester) async {
      syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintA);
      syncPersistenceStore.seedPendingDeletionTransaction(
        PendingDeletionTransaction(
          accountFingerprint: fingerprintA,
          originalDataEpoch: null,
          replacementDataEpoch: DataEpoch.generate(),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );

      await pumpSettings(tester);
      expect(
        find.text('Removal pending. EAST. will finish when iCloud is '
            'available.'),
        findsOneWidget,
      );
      expect(find.text('Removed from iCloud.'), findsNothing);

      // Simulate the real Phase 5 slice 2/3 pipeline finishing in the
      // background, completely independent of this screen -- the exact
      // same real `clearDeletionTransaction` call `LocalDeletionFinalizer`
      // itself makes as its own last step, never a test-only shortcut.
      await syncPersistenceStore.clearDeletionTransaction(
        accountFingerprint: fingerprintA,
      );

      // Tapping the still-pending-looking row re-checks state -- this is
      // the only path that can ever observe the transition.
      await tester.tap(find.byKey(removalRowKey));
      await tester.pumpAndSettle();

      expect(find.text('Removed from iCloud.'), findsOneWidget);
      expect(
        find.text('Removal pending. EAST. will finish when iCloud is '
            'available.'),
        findsNothing,
      );

      // A brand-new screen instance mounted now (e.g. the user reopening
      // Settings in a fresh session) never watched that transition happen,
      // so it must never claim "Removed from iCloud." out of nowhere.
      //
      // Deliberately unmount first (rather than pumping a second
      // `SettingsScreen` directly over the first): with no distinguishing
      // `Key`, Flutter's element reconciliation would otherwise treat the
      // second `pumpWidget` call as an *update* to the exact same, still-
      // live `State` object -- `initState` would never re-run, and the
      // session-local "just completed" flag from the first instance would
      // trivially (and wrongly) still be sitting there. Pumping an empty
      // tree first forces a real dispose/remount, so the assertion below
      // genuinely proves a fresh `State` instance, not the same one.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      var freshRequestSyncCallCount = 0;
      final freshController = ICloudRemovalController(
        syncPersistenceStore: syncPersistenceStore,
        requestSyncAfterRemoval: () => freshRequestSyncCallCount += 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            purchaseService: PurchaseService(),
            cloudKitAssociationController: controller,
            icloudRemovalController: freshController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Locked requirement is only this: a fresh `State` that never watched
      // pending -> gone happen must never fabricate "Removed from iCloud."
      // (Which exact non-completed copy this fresh screen shows -- "Remove
      // your iCloud copies." for the still-associated account this fixture
      // seeded, since the transaction really is gone -- is real,
      // `ICloudRemovalController.checkStatus`-driven behavior, not this
      // test's concern to prescribe.)
      expect(find.text('Removed from iCloud.'), findsNothing);
      expect(
        find.text('Removal pending. EAST. will finish when iCloud is '
            'available.'),
        findsNothing,
      );

      // Mounting alone is a pure read -- `checkStatus` never starts or
      // resumes a deletion transaction, so the fire-and-forget sync nudge
      // (only ever fired by a real `beginRemoval` call) must never fire
      // merely because this fresh screen appeared.
      expect(freshRequestSyncCallCount, 0);
    });

    testWidgets(
        '8. a terminal/retryable failure of the begin call itself fails '
        'closed with a calm generic error and never reports success',
        (tester) async {
      final throwingStore = _ThrowingBeginSyncPersistenceStore(
        associatedFingerprint: fingerprintB,
      );
      final throwingController = ICloudRemovalController(
        syncPersistenceStore: throwingStore,
        requestSyncAfterRemoval: () {},
      );

      await pumpSettings(tester, removalController: throwingController);
      await tester.tap(find.byKey(removalRowKey));
      await tester.pumpAndSettle();

      await tester.tap(find.text('REMOVE'));
      await tester.pumpAndSettle();

      expect(
        find.text('This could not be completed. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Removed from iCloud.'), findsNothing);
      expect(
        find.text('Removal pending. EAST. will finish when iCloud is '
            'available.'),
        findsNothing,
        reason: 'a begin-call failure must never be shown as pending -- '
            'nothing was actually started.',
      );
      // The row reverts to its honest, still-actionable idle state -- never
      // silently stuck, never claiming success.
      expect(find.text('Remove your iCloud copies.'), findsNothing);
    });

    testWidgets(
        '9. local Kept/Reflection content and daily-ritual semantics are '
        'never touched by this flow -- structural proof by source '
        'inspection of the very file that implements it', (tester) async {
      final file = File('lib/screens/settings_screen.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      const forbiddenSubstrings = [
        'KeptRepository',
        'SavedReflectionsService',
        'DailyWisdomAccessService',
        'DailyAccessRepository',
        'daily_wisdom_access',
        'wisdom_unlock_time_ms',
        'unlockAt',
        'lockDuration',
      ];
      for (final forbidden in forbiddenSubstrings) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'settings_screen.dart must never reference "$forbidden" -- '
              'the Remove from iCloud flow only ever calls '
              'ICloudRemovalController, which itself only ever touches '
              'SyncPersistenceStore\'s deletion-transaction/association-'
              'marker surface (already independently proven, by Phase 5 '
              'slice 3\'s own tests, to leave Kept/Reflection content and '
              'daily-access state completely untouched).',
        );
      }
    });
  });

  // EAST. Data Ownership / Export -- "Export My Data" Settings row.
  group('Export My Data', () {
    testWidgets(
        'exactly one Export My Data row exists, using the existing '
        'Settings visual language and no Keeper badge', (tester) async {
      await pumpSettings(tester);

      expect(find.text('Export My Data'), findsOneWidget);
      final row = find.byKey(const ValueKey('settings-export-data-row'));
      expect(row, findsOneWidget);
      // Scoped to the export row itself -- the existing, unrelated
      // standalone "Keeper" Settings row is expected to still exist
      // elsewhere on this screen.
      expect(
        find.descendant(of: row, matching: find.textContaining('Keeper')),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.textContaining('Premium')),
        findsNothing,
      );
    });

    testWidgets(
        'tapping the row invokes export -- a Free user (the default '
        'PurchaseService this screen already uses throughout this file) '
        'can export', (tester) async {
      var callCount = 0;
      final fakeExportService = _RecordingDataExportService(
        onExport: () => callCount += 1,
      );

      await pumpSettings(tester, dataExportService: fakeExportService);
      await tapExportRow(tester);
      await tester.pumpAndSettle();

      expect(callCount, 1);
    });

    testWidgets(
        'the export action never opens Keeper and never depends on '
        'entitlement state -- structural proof by source inspection: '
        'unlike Restore Purchases/Keeper, this row never reads '
        'PurchaseService/isKeeper', (tester) async {
      final source =
          File('lib/screens/settings_screen.dart').readAsStringSync();

      // Two separate, precisely bounded export-only sections (this file's
      // unrelated existing rows sit *between* them, so a single combined
      // span would wrongly sweep in Restore Purchases' own legitimate
      // `_purchaseService` usage) -- confirm neither ever mentions purchase/
      // entitlement state, proving Free and Keeper are structurally
      // identical, not merely coincidentally equal in these tests.
      String section(String startMarker, String endMarker) {
        final start = source.indexOf(startMarker);
        final end = source.indexOf(endMarker);
        expect(start, greaterThan(-1), reason: 'missing "$startMarker"');
        expect(end, greaterThan(start),
            reason: 'missing "$endMarker" after "$startMarker"');
        return source.substring(start, end);
      }

      final exportGetter = section(
        'DataExportService get _dataExportService',
        'TextStyle eastStyle(',
      );
      final exportActions = section(
        'Future<void> exportDataFromSettings()',
        'VoidCallback? get privacyPolicyAction',
      );

      for (final exportSection in [exportGetter, exportActions]) {
        expect(exportSection.contains('_purchaseService'), isFalse);
        expect(exportSection.contains('isKeeper'), isFalse);
        expect(exportSection.contains('KeeperScreen'), isFalse);
      }
    });

    testWidgets(
        'a generation/share failure shows one quiet message and '
        'leaves the screen fully usable -- no stack trace, no file path, '
        'no CloudKit terminology', (tester) async {
      final failingExportService = _RecordingDataExportService(
        onExport: () {},
        succeeds: false,
      );

      await pumpSettings(tester, dataExportService: failingExportService);
      await tapExportRow(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('This could not be completed. Please try again.'),
        findsOneWidget,
      );
      // The screen remains fully usable -- every other row is still there.
      expect(find.text('Keeper'), findsOneWidget);
      expect(find.text('Export My Data'), findsOneWidget);
    });

    testWidgets(
        'a second tap while export is already in progress is a '
        'no-op -- never a second concurrent export/share invocation',
        (tester) async {
      final gate = Completer<void>();
      var callCount = 0;
      final fakeExportService = _RecordingDataExportService(
        onExport: () => callCount += 1,
        gate: gate.future,
      );

      await pumpSettings(tester, dataExportService: fakeExportService);
      await tapExportRow(tester);
      await tester.pump();
      await tapExportRow(tester);
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();

      expect(callCount, 1);
    });
  });

  group('Voice Control actionability (Build 33 real-device repair)', () {
    testWidgets(
        'Restore Purchases and Language rows (the reference-quality '
        '`settingsItem` pattern) both have SemanticsAction.tap',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SettingsScreen()),
      );
      await tester.pumpAndSettle();

      final semantics = tester.ensureSemantics();
      final restore = tester.getSemantics(
        find.byKey(const ValueKey('settings-restore-purchases-row')),
      );
      expect(
        restore.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      final language = tester.getSemantics(
        find.byKey(const ValueKey('settings-language-row')),
      );
      expect(
        language.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      semantics.dispose();
    });

    // `_removeFromICloudDecisionLabel`/`_enableSyncDecisionLabel`/the
    // restore-result Close label all previously had an outer `Semantics`
    // with a label and `button: true` but no `onTap` of their own -- the
    // same defect class fixed everywhere else this session (see
    // Reflection's `_deleteDecisionLabel`, Journal's
    // `_nameDecisionLabel`/name-action/export-action, Home's
    // `_favoriteLimitDecisionLabel`, and Kept's Reflection-row actions
    // for the same fix, each independently verified).
    testWidgets(
        'the Remove-from-iCloud decision overlay\'s labels have '
        'SemanticsAction.tap', (tester) async {
      syncPersistenceStore.seedAssociatedAccountFingerprint(fingerprintA);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            purchaseService: PurchaseService(),
            cloudKitAssociationController: controller,
            icloudRemovalController: icloudRemovalController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(removalRowKey));
      await tester.pumpAndSettle();

      final semantics = tester.ensureSemantics();
      final removeLabel = tester.getSemantics(find.text('REMOVE'));
      final cancelLabel = tester.getSemantics(find.text('CANCEL'));
      expect(
        removeLabel.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        cancelLabel.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      semantics.dispose();
    });
  });
}

/// A [SyncPersistenceStore] decorator that delegates every call to a real
/// store, except [beginDeletionTransaction], which awaits [gate] before
/// delegating -- used only to hold one "Remove from iCloud" begin call open
/// long enough to prove a second, concurrent UI tap cannot start a second
/// one (test 5).
class _DelayedBeginSyncPersistenceStore implements SyncPersistenceStore {
  _DelayedBeginSyncPersistenceStore(this._delegate, {required this.gate});

  final SyncPersistenceStore _delegate;
  final Completer<void> gate;
  int beginCallCount = 0;

  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction({
    required String accountFingerprint,
  }) async {
    beginCallCount += 1;
    await gate.future;
    return _delegate.beginDeletionTransaction(
      accountFingerprint: accountFingerprint,
    );
  }

  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) =>
      _delegate.loadAccountState(accountFingerprint);
  @override
  Future<void> replaceAccountState(
          String accountFingerprint, AccountSyncState state) =>
      _delegate.replaceAccountState(accountFingerprint, state);
  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) =>
      _delegate.enqueueMutation(accountFingerprint, change);
  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) =>
      _delegate.applyMutationOutcomes(
        accountFingerprint,
        acknowledgedMutationIds: acknowledgedMutationIds,
        updatedStatusByMutationId: updatedStatusByMutationId,
      );
  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
          String accountFingerprint) =>
      _delegate.readPendingMutations(accountFingerprint);
  @override
  Future<void> replaceRecordSystemFields(
          String accountFingerprint, String recordName, String systemFields) =>
      _delegate.replaceRecordSystemFields(
          accountFingerprint, recordName, systemFields);
  @override
  Future<void> storeServerChangeToken(
          String accountFingerprint, String serverToken) =>
      _delegate.storeServerChangeToken(accountFingerprint, serverToken);
  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      _delegate.clearServerChangeToken(accountFingerprint);
  @override
  Future<void> clearAccountState(String accountFingerprint) =>
      _delegate.clearAccountState(accountFingerprint);
  @override
  Future<void> quarantineAccountState(String accountFingerprint) =>
      _delegate.quarantineAccountState(accountFingerprint);
  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) =>
      _delegate.commitIncomingBatchCheckpoint(request);
  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) =>
      _delegate.retireOutboxMutationIfCurrent(request);
  @override
  Future<String?> loadAssociatedAccountFingerprint() =>
      _delegate.loadAssociatedAccountFingerprint();
  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) =>
          _delegate.commitAssociatedAccountFingerprint(
            fingerprint: fingerprint,
            expectedCurrent: expectedCurrent,
          );
  @override
  Future<ClearAssociatedAccountFingerprintResult>
      clearAssociatedAccountFingerprintIfCurrent({
    required String expectedCurrent,
  }) =>
          _delegate.clearAssociatedAccountFingerprintIfCurrent(
            expectedCurrent: expectedCurrent,
          );
  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      _delegate.loadMeaningfulAccountFingerprints();
  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() =>
      _delegate.loadPendingDeletionTransaction();
  @override
  Future<AdvanceDeletionTransactionResult> advanceDeletionTransactionStage({
    required String accountFingerprint,
    required DeletionTransactionStage expectedCurrentStage,
    required DeletionTransactionStage nextStage,
  }) =>
      _delegate.advanceDeletionTransactionStage(
        accountFingerprint: accountFingerprint,
        expectedCurrentStage: expectedCurrentStage,
        nextStage: nextStage,
      );
  @override
  Future<void> clearDeletionTransaction({
    required String accountFingerprint,
  }) =>
      _delegate.clearDeletionTransaction(
          accountFingerprint: accountFingerprint);
}

/// A [SyncPersistenceStore] fake whose reads report [associatedFingerprint]
/// as currently associated with nothing pending (so the row is actionable),
/// but whose [beginDeletionTransaction] always throws -- used only to prove
/// test 8's fail-closed, never-claims-success requirement without needing a
/// real account-mismatch race.
class _ThrowingBeginSyncPersistenceStore implements SyncPersistenceStore {
  _ThrowingBeginSyncPersistenceStore({required this.associatedFingerprint});

  final String associatedFingerprint;

  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() async =>
      null;
  @override
  Future<String?> loadAssociatedAccountFingerprint() async =>
      associatedFingerprint;
  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction({
    required String accountFingerprint,
  }) async {
    throw Exception('simulated begin failure');
  }

  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) =>
      throw UnimplementedError();
  @override
  Future<void> replaceAccountState(
          String accountFingerprint, AccountSyncState state) =>
      throw UnimplementedError();
  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) =>
      throw UnimplementedError();
  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) =>
      throw UnimplementedError();
  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
          String accountFingerprint) =>
      throw UnimplementedError();
  @override
  Future<void> replaceRecordSystemFields(
          String accountFingerprint, String recordName, String systemFields) =>
      throw UnimplementedError();
  @override
  Future<void> storeServerChangeToken(
          String accountFingerprint, String serverToken) =>
      throw UnimplementedError();
  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      throw UnimplementedError();
  @override
  Future<void> clearAccountState(String accountFingerprint) =>
      throw UnimplementedError();
  @override
  Future<void> quarantineAccountState(String accountFingerprint) =>
      throw UnimplementedError();
  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) =>
      throw UnimplementedError();
  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) =>
      throw UnimplementedError();
  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) =>
          throw UnimplementedError();
  @override
  Future<ClearAssociatedAccountFingerprintResult>
      clearAssociatedAccountFingerprintIfCurrent({
    required String expectedCurrent,
  }) =>
          throw UnimplementedError();
  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      throw UnimplementedError();
  @override
  Future<AdvanceDeletionTransactionResult> advanceDeletionTransactionStage({
    required String accountFingerprint,
    required DeletionTransactionStage expectedCurrentStage,
    required DeletionTransactionStage nextStage,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> clearDeletionTransaction({
    required String accountFingerprint,
  }) =>
      throw UnimplementedError();
}

/// A fake [DataExportService] used only to prove `SettingsScreen`'s own
/// wiring (in-progress guard, failure message) -- the real export
/// content/schema is proven independently by
/// `test/services/data_export_builder_test.dart` and
/// `test/services/data_export_service_test.dart`.
class _RecordingDataExportService implements DataExportService {
  _RecordingDataExportService({
    required this.onExport,
    this.succeeds = true,
    this.gate,
  });

  final void Function() onExport;
  final bool succeeds;
  final Future<void>? gate;

  @override
  Future<bool> exportAndShare() async {
    onExport();
    final wait = gate;
    if (wait != null) await wait;
    return succeeds;
  }
}
