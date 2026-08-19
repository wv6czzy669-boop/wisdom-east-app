// Build 26 Phase 4H-6: live incoming Kept UI refresh -- proves a mounted
// SavedReflectionsScreen picks up an incoming CloudKit-applied Kept change
// without navigation or relaunch, via the real
// `app_services.keptStateRevisionNotifier` signal `IncomingKeptSyncCoordinator`
// fires after a durable, content-differing `KeptRepository.replaceAllRecords`
// call. This is the one focused widget test for this feature -- every other
// scenario is covered at the coordinator/service level
// (`test/sync_integration/incoming_kept_sync_coordinator_test.dart`,
// `test/services/kept_state_revision_notifier_test.dart`), per the
// instruction to prefer controller/service-level tests over fragile widget
// tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/services/app_services.dart' as app_services;
import 'package:wisdom_app/services/purchase_service.dart';

import '../persistence_test_helpers.dart';

void main() {
  final t0 = DateTime.utc(2026, 8, 1, 10);

  KeptRecord buildRecord({
    required String id,
    required String revealId,
    required String wisdomText,
  }) {
    return KeptRecord(
      id: id,
      revealId: revealId,
      wisdomText: wisdomText,
      revealedAt: t0,
      keptAt: t0.add(const Duration(minutes: 5)),
      updatedAt: t0.add(const Duration(minutes: 5)),
      // A valid canonical UUID v4/v5 is required by KeptRecord's own
      // validation; its exact value is otherwise irrelevant to this test.
      mutationId: '${revealId.substring(0, 8)}-${revealId.substring(9)}',
    );
  }

  setUp(() {
    // Build 26 Phase 4H-6: `app_services.keptStateRevisionNotifier` is a
    // real, eagerly-constructed global shared across the whole test binary
    // (mirroring `app_services.purchaseService`) -- clear its listeners
    // between tests so a previous test's disposed screen can never leak a
    // stale listener into this one.
    app_services.keptStateRevisionNotifier.clearListenersForTest();
  });

  testWidgets(
      'a mounted SavedReflectionsScreen silently reflects an incoming Kept '
      'content change signaled via keptStateRevisionNotifier, with no '
      'navigation and no relaunch', (tester) async {
    const revealIdA = 'aaaaaaaa-1111-4111-8111-111111111111';
    const revealIdB = 'bbbbbbbb-2222-4222-8222-222222222222';
    const originalText = 'Be still and know.';
    const incomingText = 'A new wisdom arrived from another device.';

    final graph = KeptRepositoryTestGraph();
    graph.seed([
      buildRecord(id: 'local-a', revealId: revealIdA, wisdomText: originalText),
    ]);
    final initialItems = await graph.service.load();

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: initialItems,
          savedReflectionsService: graph.service,
          purchaseService: PurchaseService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(originalText), findsOneWidget);
    expect(find.text(incomingText), findsNothing);

    // Simulate exactly what IncomingKeptSyncCoordinator does in production:
    // a durable, content-differing KeptRepository.replaceAllRecords call,
    // followed by the neutral keptStateRevisionNotifier signal -- never a
    // second widget push, never a rebuild of the screen itself.
    await graph.repository.replaceAllRecords([
      buildRecord(id: 'local-a', revealId: revealIdA, wisdomText: originalText),
      buildRecord(id: 'local-b', revealId: revealIdB, wisdomText: incomingText),
    ]);
    app_services.keptStateRevisionNotifier.notify();
    await tester.pumpAndSettle();

    expect(find.text(originalText), findsOneWidget);
    expect(find.text(incomingText), findsOneWidget);
  });

  testWidgets(
      'disposing a SavedReflectionsScreen and then signaling '
      'keptStateRevisionNotifier never throws (no setState-after-dispose)',
      (tester) async {
    const revealIdA = 'aaaaaaaa-1111-4111-8111-111111111111';
    const originalText = 'Be still and know.';

    final graph = KeptRepositoryTestGraph();
    graph.seed([
      buildRecord(id: 'local-a', revealId: revealIdA, wisdomText: originalText),
    ]);
    final initialItems = await graph.service.load();

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: initialItems,
          savedReflectionsService: graph.service,
          purchaseService: PurchaseService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Unmount the screen (navigate to an unrelated widget in its place).
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    // A stray notification after disposal must be silently ignored --
    // FlutterError would fail this test if a disposed State's setState was
    // ever reached.
    expect(
        () => app_services.keptStateRevisionNotifier.notify(), returnsNormally);
    await tester.pumpAndSettle();
  });
}
