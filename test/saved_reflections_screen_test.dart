import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/screens/journal_screen.dart';
import 'package:wisdom_app/screens/keeper_screen.dart';
import 'package:wisdom_app/screens/return_screen.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/services/return_service.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';
import 'package:wisdom_app/sync_integration/kept_sync_integration_coordinator.dart';
import 'package:wisdom_app/utils/date_formatter.dart';
import 'package:wisdom_app/utils/reflection_prompt.dart';

import 'persistence_test_helpers.dart';
import 'sync_integration/in_memory_sync_test_doubles.dart';

void main() {
  late KeptRepositoryTestGraph graph;
  late SavedReflectionsService service;
  late DateTime keptAtClock;
  var revealCounter = 0;

  setUp(() {
    keptAtClock = DateTime.utc(2026, 7, 1);
    revealCounter = 0;
    graph = KeptRepositoryTestGraph(clock: () => keptAtClock);
    service = graph.service;
  });

  Future<FavoriteItem> keep(
    SavedReflectionsService service, {
    required String text,
    required DateTime date,
  }) async {
    keptAtClock = date;
    revealCounter += 1;
    final revealId =
        'a5f3c111-1111-4111-8111-${revealCounter.toString().padLeft(12, '0')}';
    final result = await service.toggle(
      revealId: revealId,
      text: text,
      // Compatibility-only per the locked Phase 3D-C contract: never parsed,
      // never used to derive `revealedAt`, never part of identity.
      date: formatFavoriteDisplayDate(date),
      revealedAt: date,
      isKeeper: true,
    );
    return result.items.last;
  }

  SavedReflectionsService failingWritesService() {
    final store = InMemoryKeptStateStore()
      ..envelope = graph.store.envelope
      ..failReplace = StateError('write failed');
    final repository = KeptRepository(
      store: store,
      bootstrap: const KeptBootstrapResult.ready(),
      operationCoordinator: PersistenceOperationCoordinator(),
    );
    final coordinator = KeptSyncIntegrationCoordinator(
      keptRepository: repository,
      intentStore: InMemoryLocalSyncIntentStore(),
      syncPersistenceStore: InMemorySyncPersistenceStore(),
    );
    return SavedReflectionsService(
      keptRepository: repository,
      syncCoordinator: coordinator,
    );
  }

  testWidgets('Kept shows newest first, full year, and exact states',
      (tester) async {
    final first = await keep(
      service,
      text: 'Older wisdom',
      date: DateTime.utc(2026, 7, 22),
    );
    final second = await keep(
      service,
      text: 'Newer wisdom',
      date: DateTime.utc(2026, 7, 23),
    );
    await service.saveReflection(
      itemId: second.id,
      reflection: 'This remains private.',
      isKeeper: false,
    );
    final items = await service.load();

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: items,
          savedReflectionsService: service,
        ),
      ),
    );

    expect(find.text('JULY 22, 2026'), findsOneWidget);
    expect(find.text('JULY 23, 2026'), findsOneWidget);
    expect(find.text('KEPT'), findsOneWidget);
    expect(find.text('REFLECTED'), findsOneWidget);
    expect(find.text('ADD REFLECTION'), findsOneWidget);
    expect(find.text('This remains private.'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Newer wisdom')).dy,
      lessThan(tester.getTopLeft(find.text('Older wisdom')).dy),
    );
    expect(first.hasReflection, isFalse);

    final kept = tester.widget<Text>(find.text('KEPT'));
    final reflected = tester.widget<Text>(find.text('REFLECTED'));
    expect(reflected.style?.fontFamily, kept.style?.fontFamily);
    expect(reflected.style?.fontSize, kept.style?.fontSize);
    expect(reflected.style?.fontWeight, kept.style?.fontWeight);
    expect(reflected.style?.letterSpacing, kept.style?.letterSpacing);
    expect(reflected.style?.color, kept.style?.color);
  });

  // EAST. Phase 8 real-device repair: the real production navigation path
  // -- Kept -> ADD REFLECTION -> type -> immediate Back -> Kept -- rather
  // than only ReflectionScreen in isolation (which never exercises
  // SavedReflectionsScreen's own post-pop reload).
  testWidgets(
      'typing a Reflection then immediately backing out of the real Kept '
      'navigation flow shows Reflected on return, with the saved text '
      'intact', (tester) async {
    final item = await keep(
      service,
      text: 'A wisdom worth reflecting on',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: service,
        ),
      ),
    );

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      'Typed and left immediately.',
    );
    // No time advanced past the autosave debounce -- back out right away,
    // exactly like the real-device repro (leave/back before the debounce
    // interval expires).
    await tester.tap(find.byKey(const ValueKey('east-back-button')));
    await tester.pumpAndSettle();

    expect(find.byType(SavedReflectionsScreen), findsOneWidget);
    expect(find.text('REFLECTED'), findsOneWidget);
    expect(find.text('ADD REFLECTION'), findsNothing);

    final persisted = await service.load();
    expect(persisted.single.reflection, 'Typed and left immediately.');

    // Reopening shows the exact saved text.
    await tester.tap(find.text('REFLECTED'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('reflection-writing-area')),
    );
    expect(field.controller!.text, 'Typed and left immediately.');
  });

  testWidgets('ADD REFLECTION opens dedicated screen with associated wisdom',
      (tester) async {
    final item = await keep(
      service,
      text: 'Wisdom to reread while writing',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: service,
        ),
      ),
    );

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    expect(find.text('Reflection'), findsOneWidget);
    expect(
      find.text(reflectionPromptFor(item.revealId ?? item.id)),
      findsOneWidget,
    );
    expect(find.text(item.text), findsOneWidget);
  });

  testWidgets('REFLECTED state opens the existing reflection for editing',
      (tester) async {
    final item = await keep(
      service,
      text: 'Reflected wisdom',
      date: DateTime.utc(2026, 7, 23),
    );
    await service.saveReflection(
      itemId: item.id,
      reflection: 'Existing private reflection',
      isKeeper: false,
    );
    final reflected = (await service.load()).single;

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [reflected],
          savedReflectionsService: service,
        ),
      ),
    );

    await tester.tap(find.text('REFLECTED'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('reflection-writing-area')),
    );
    expect(field.controller!.text, 'Existing private reflection');
    expect(find.text(reflected.text), findsOneWidget);
  });

  testWidgets('deleting a reflection returns REFLECTED wisdom to KEPT',
      (tester) async {
    final item = await keep(
      service,
      text: 'Return to kept state',
      date: DateTime.utc(2026, 7, 23),
    );
    await service.saveReflection(
      itemId: item.id,
      reflection: 'Remove only this reflection',
      isKeeper: false,
    );
    final reflected = (await service.load()).single;

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [reflected],
          savedReflectionsService: service,
        ),
      ),
    );

    await tester.tap(find.text('REFLECTED'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // Approved Ritual direction: the confirmation is a full-field takeover,
    // not a system AlertDialog.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('reflection-delete-decision')),
        matching: find.text('DELETE'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REFLECTED'), findsNothing);
    expect(find.text('KEPT'), findsOneWidget);
    expect(find.text('ADD REFLECTION'), findsOneWidget);
    expect((await service.load()).single.hasReflection, isFalse);
  });

  testWidgets(
      'free fourth reflection opens the calm Keeper experience after three active reflections',
      (tester) async {
    final first = await keep(
      service,
      text: 'Already reflected one',
      date: DateTime.utc(2026, 7, 20),
    );
    final second = await keep(
      service,
      text: 'Already reflected two',
      date: DateTime.utc(2026, 7, 21),
    );
    final third = await keep(
      service,
      text: 'Already reflected three',
      date: DateTime.utc(2026, 7, 22),
    );
    final fourth = await keep(
      service,
      text: 'Still kept',
      date: DateTime.utc(2026, 7, 23),
    );
    await service.saveReflection(
      itemId: first.id,
      reflection: 'First active reflection',
      isKeeper: false,
    );
    await service.saveReflection(
      itemId: second.id,
      reflection: 'Second active reflection',
      isKeeper: false,
    );
    await service.saveReflection(
      itemId: third.id,
      reflection: 'Third active reflection',
      isKeeper: false,
    );
    final items = await service.load();

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: items,
          savedReflectionsService: service,
        ),
      ),
    );

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    expect(find.text('Keeper'), findsOneWidget);
    expect(find.text('Reflect without limit.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reflection-writing-area')),
      findsNothing,
    );
    expect(fourth.hasReflection, isFalse);
  });

  testWidgets(
      'swiping a Kept row alone does not delete it, and reveals no REMOVE label',
      (tester) async {
    final item = await keep(
      service,
      text: 'Do not remove yet',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: service,
        ),
      ),
    );

    await tester.drag(
      find.byKey(ValueKey('kept-${item.id}')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    // The row is still present: swiping only reveals the DELETE action.
    expect(find.text(item.text), findsOneWidget);
    expect(find.text('REMOVE'), findsNothing);
    expect(find.text('Remove from Kept?'), findsNothing);
    expect(await service.load(), hasLength(1));
  });

  testWidgets(
      'the DELETE action is genuinely hit-testable at its rendered location once revealed',
      (tester) async {
    final item = await keep(
      service,
      text: 'DELETE is reachable once open',
      date: DateTime.utc(2026, 7, 23),
    );
    final deleteAction = find.byKey(ValueKey('kept-${item.id}-delete-action'));

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: service,
        ),
      ),
    );

    await tester.drag(
      find.byKey(ValueKey('kept-${item.id}')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    // A tap at the DELETE action's own rendered location must actually
    // reach it and invoke deletion — proving the foreground row is no
    // longer covering that region once the row is open. This uses the
    // real widget location (no `warnIfMissed: false`, no arbitrary
    // coordinates, no bypassing the UI).
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();

    expect(find.text(item.text), findsNothing);
    expect(await service.load(), isEmpty);
  });

  testWidgets(
      'closing an open swipe by tapping the row preserves the item without deleting',
      (tester) async {
    final item = await keep(
      service,
      text: 'Preserved after closing swipe',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: service,
        ),
      ),
    );

    await tester.drag(
      find.byKey(ValueKey('kept-${item.id}')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    // Tap the now-open row (not DELETE) to close the revealed action.
    await tester.tap(find.text(item.text));
    await tester.pumpAndSettle();

    expect(find.text(item.text), findsOneWidget);
    expect(await service.load(), hasLength(1));
  });

  testWidgets(
      'tapping the DELETE action after swiping removes the item immediately with no dialog, snackbar, or Undo',
      (tester) async {
    final item = await keep(
      service,
      text: 'Delete on explicit tap',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: service,
        ),
      ),
    );

    await tester.drag(
      find.byKey(ValueKey('kept-${item.id}')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('kept-${item.id}-delete-action')));
    await tester.pumpAndSettle();

    expect(find.text(item.text), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Removed from Kept.'), findsNothing);
    expect(find.text('Undo'), findsNothing);
    expect(await service.load(), isEmpty);
  });

  testWidgets(
      'deleting a reflected Kept item removes the complete record including its reflection',
      (tester) async {
    final item = await keep(
      service,
      text: 'Carries a reflection',
      date: DateTime.utc(2026, 7, 23),
    );
    await service.saveReflection(
      itemId: item.id,
      reflection: 'This goes with it',
      isKeeper: false,
      reflectedAt: DateTime.utc(2026, 7, 23, 12),
    );
    final reflected = (await service.load()).single;

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [reflected],
          savedReflectionsService: service,
        ),
      ),
    );

    await tester.drag(
      find.byKey(ValueKey('kept-${item.id}')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('kept-${item.id}-delete-action')));
    await tester.pumpAndSettle();

    expect(find.text(item.text), findsNothing);
    expect(find.text('REFLECTED'), findsNothing);
    final remaining = await service.load();
    expect(remaining, isEmpty);
    expect(remaining.any((candidate) => candidate.id == item.id), isFalse);
  });

  testWidgets('failed kept removal leaves the item visible and persisted',
      (tester) async {
    final item = await keep(
      service,
      text: 'Remain when storage fails',
      date: DateTime.utc(2026, 7, 23),
    );
    final failingService = failingWritesService();

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: failingService,
        ),
      ),
    );

    await tester.drag(
      find.byKey(ValueKey('kept-${item.id}')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('kept-${item.id}-delete-action')));
    await tester.pumpAndSettle();

    expect(find.text(item.text), findsOneWidget);
    expect(
      find.text('This wisdom could not be removed. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Undo'), findsNothing);
    expect(await service.load(), hasLength(1));
  });

  testWidgets('Kept remains usable on small iPhone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final item = await keep(
      service,
      text:
          'A longer wisdom remains readable without turning the page into a card.',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: service,
        ),
      ),
    );

    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('ADD REFLECTION'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // EAST. Phase 9 — Return, wired into the Kept header utility region.
  group('Return', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    final now = DateTime.utc(2026, 8, 1);
    ReturnService returnService() => ReturnService(clock: () => now);

    testWidgets(
        'Return is always visible even when no Kept occurrence is at '
        'least 14 days old, showing the exact pre-eligibility copy, and '
        'the existing Basic Wisdoms/Reflected/Make a Reflection UI is '
        'unaffected', (tester) async {
      final item = await keep(
        service,
        text: 'Too new for Return',
        date: now.subtract(const Duration(days: 5)),
      );

      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [item],
            isKeeper: true,
            savedReflectionsService: service,
            returnService: returnService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('kept-return-action')), findsOneWidget);
      expect(find.text('Return'), findsOneWidget);
      // Approved Kept direction: the pre-eligibility explanation belongs
      // only to Return's own empty state (see the ReturnScreen test right
      // below) -- Kept itself shows no supporting copy until a real Return
      // exists, though the full explanation still reaches VoiceOver via the
      // Return action's own semantic label.
      expect(
        find.text('What you keep may return after 14 days.'),
        findsNothing,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('kept-return-action')))
            .label,
        'Return. What you keep may return after 14 days.',
      );
      expect(find.textContaining('KEEPER'), findsNothing);
      // The existing hierarchy is completely untouched.
      expect(find.text('Kept'), findsOneWidget);
      expect(find.text('KEPT'), findsOneWidget);
      expect(find.text('ADD REFLECTION'), findsOneWidget);
      expect(find.text(item.text), findsOneWidget);
      semantics.dispose();
    });

    testWidgets(
        'tapping pre-eligibility Return opens the quiet explanation state '
        'for both Free and Keeper, never a paywall merely to explain '
        'Return', (tester) async {
      for (final isKeeper in [false, true]) {
        final item = await keep(
          service,
          text: 'Too new for Return $isKeeper',
          date: now.subtract(const Duration(days: 5)),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: SavedReflectionsScreen(
              reflections: [item],
              isKeeper: isKeeper,
              savedReflectionsService: service,
              returnService: returnService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('kept-return-action')));
        await tester.pumpAndSettle();

        expect(find.byType(ReturnScreen), findsOneWidget,
            reason: 'isKeeper=$isKeeper');
        expect(find.byType(KeeperScreen), findsNothing,
            reason: 'isKeeper=$isKeeper');
        expect(
          find.text('What you keep may return after 14 days.'),
          findsOneWidget,
          reason: 'isKeeper=$isKeeper',
        );

        await tester.tap(find.byKey(const ValueKey('east-back-button')));
        await tester.pumpAndSettle();
      }
    });

    testWidgets(
        'Return appears once an eligible Kept occurrence exists, '
        'positioned above the existing Basic Wisdoms/Reflected content -- '
        'never inserted into or between it', (tester) async {
      final eligible = await keep(
        service,
        text: 'Eligible for Return',
        date: now.subtract(const Duration(days: 20)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [eligible],
            isKeeper: true,
            savedReflectionsService: service,
            returnService: returnService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final returnAction = find.byKey(const ValueKey('kept-return-action'));
      expect(returnAction, findsOneWidget);
      expect(find.text('Kept'), findsOneWidget); // title still present
      expect(find.text('KEPT'), findsOneWidget); // existing status untouched
      expect(find.text(eligible.text), findsOneWidget);

      // Return sits above the existing Kept content -- smaller dy.
      expect(
        tester.getTopLeft(returnAction).dy,
        lessThan(tester.getTopLeft(find.text(eligible.text)).dy),
      );
    });

    testWidgets(
        'a Free user with eligible content sees no Keeper badge, and '
        'tapping the now-actionable Return uses the existing Keeper/'
        'paywall flow -- never opening ReturnScreen directly', (tester) async {
      final eligible = await keep(
        service,
        text: 'Eligible for Return',
        date: now.subtract(const Duration(days: 20)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [eligible],
            isKeeper: false,
            savedReflectionsService: service,
            returnService: returnService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Return'), findsOneWidget);
      // Visual-polish repair: premium status is communicated through
      // behavior, never a "KEEPER" badge -- neither Return nor Journal
      // shows one anywhere in the Kept utility region.
      expect(find.textContaining('KEEPER'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('kept-return-action')));
      await tester.pumpAndSettle();

      expect(find.byType(KeeperScreen), findsOneWidget);
      expect(find.byType(ReturnScreen), findsNothing);
    });

    testWidgets(
        'a Keeper can open Return normally, seeing the original '
        'wisdom, date, and (if present) Reflection for that exact revealId',
        (tester) async {
      final eligible = await keep(
        service,
        text: 'Eligible for Return',
        date: now.subtract(const Duration(days: 20)),
      );
      await service.saveReflection(
        itemId: eligible.id,
        reflection: 'What I wrote back then.',
        isKeeper: true,
      );
      final reflected = (await service.load()).single;

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [reflected],
            isKeeper: true,
            savedReflectionsService: service,
            returnService: returnService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('KEEPER'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('kept-return-action')));
      await tester.pumpAndSettle();

      expect(find.byType(ReturnScreen), findsOneWidget);
      expect(find.byType(KeeperScreen), findsNothing);
      expect(find.text('Return'), findsOneWidget);
      expect(find.text(eligible.text), findsOneWidget);
      expect(find.text('What I wrote back then.'), findsOneWidget);
    });

    testWidgets(
        'opening and closing Return never creates a new Kept occurrence, '
        'never changes existing item count, and leaves Kept navigation '
        'otherwise unaffected', (tester) async {
      final eligible = await keep(
        service,
        text: 'Eligible for Return',
        date: now.subtract(const Duration(days: 20)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [eligible],
            isKeeper: true,
            savedReflectionsService: service,
            returnService: returnService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final beforeCount = (await service.load()).length;

      await tester.tap(find.byKey(const ValueKey('kept-return-action')));
      await tester.pumpAndSettle();
      expect(find.byType(ReturnScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('east-back-button')));
      await tester.pumpAndSettle();

      final afterItems = await service.load();
      expect(afterItems, hasLength(beforeCount));
      expect(afterItems.single.id, eligible.id);
      expect(afterItems.single.revealId, eligible.revealId);
      // Ordinary Kept navigation (ADD REFLECTION) still reachable and
      // unaffected by Return having just been opened.
      expect(find.text('ADD REFLECTION'), findsOneWidget);
    });

    testWidgets(
        'a freshly selected current Return shows the whole-day cadence '
        'line, with no hour/minute/second countdown anywhere', (tester) async {
      final eligible = await keep(
        service,
        text: 'Eligible for Return',
        date: now.subtract(const Duration(days: 20)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [eligible],
            isKeeper: true,
            savedReflectionsService: service,
            returnService: returnService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Freshly selected -- the full 7-day cadence remains.
      expect(find.text('A new Return in 7 days.'), findsOneWidget);
      expect(find.textContaining('hour'), findsNothing);
      expect(find.textContaining('minute'), findsNothing);
      expect(find.textContaining('second'), findsNothing);
      expect(find.textContaining(':'), findsNothing);
    });

    testWidgets(
        'once the cadence window has fully elapsed with nothing new to '
        'select, the clean active state is shown instead of a nonsensical '
        '"0 days" message', (tester) async {
      final onlyCandidate = await keep(
        service,
        text: 'Only candidate',
        date: now.subtract(const Duration(days: 100)),
      );
      final svc = returnService();
      // Pin it now, then let the cadence fully elapse with no other
      // eligible occurrence available to replace it (90-day repeat
      // protection keeps it the only, already-stale pin).
      await svc.resolveCurrentReturn([onlyCandidate]);

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [onlyCandidate],
            isKeeper: true,
            savedReflectionsService: service,
            returnService: ReturnService(
              clock: () => now.add(const Duration(days: 7)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Return to what stayed.'), findsOneWidget);
      expect(find.textContaining('0 days'), findsNothing);
    });
  });

  // EAST. Phase 10 — Journal, Return's sibling in the same utility region.
  group('Journal', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
        'Journal is always offered as Return\'s sibling without '
        'disturbing the existing Basic Wisdoms/Reflected/Make a Reflection '
        'UI -- even before any Kept occurrence is Return-eligible',
        (tester) async {
      final fixedNow = DateTime.utc(2026, 7, 25);
      final freshItem = await keep(
        service,
        text: 'Too new for Return',
        date: fixedNow.subtract(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [freshItem],
            isKeeper: true,
            savedReflectionsService: service,
            returnService: ReturnService(clock: () => fixedNow),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Visual-polish repair: Return is now always visible too.
      expect(find.byKey(const ValueKey('kept-return-action')), findsOneWidget);
      expect(find.byKey(const ValueKey('kept-journal-action')), findsOneWidget);
      expect(find.textContaining('KEEPER'), findsNothing);
      // Existing hierarchy completely untouched.
      expect(find.text('Kept'), findsOneWidget);
      expect(find.text('KEPT'), findsOneWidget);
      expect(find.text('ADD REFLECTION'), findsOneWidget);
      expect(find.text(freshItem.text), findsOneWidget);
    });

    testWidgets(
        'a Free user tapping Journal enters Journal directly -- no entry '
        'paywall -- with no KEEPER badge beside it', (tester) async {
      final item = await keep(
        service,
        text: 'A kept wisdom',
        date: DateTime.utc(2026, 7, 23),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [item],
            isKeeper: false,
            savedReflectionsService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('KEEPER'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('kept-journal-action')));
      await tester.pumpAndSettle();

      expect(find.byType(JournalScreen), findsOneWidget);
      expect(find.byType(KeeperScreen), findsNothing);
    });

    testWidgets(
        'real-device repair: Kept -> Journal is a clean, stable '
        'transition -- no exception mid-push, and no generic loading '
        'spinner at any point from the tap through the settled preview',
        (tester) async {
      final item = await keep(
        service,
        text: 'A kept wisdom',
        date: DateTime.utc(2026, 7, 23),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [item],
            isKeeper: true,
            savedReflectionsService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('kept-journal-action')));
      // Mid-push and mid-generation -- the exact window where a bleed/tear
      // or a generic spinner would show up on a real device.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();

      expect(find.byType(JournalScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'real-device repair: Kept -> Journal uses the standard '
        'MaterialPageRoute (native platform transition, native iOS '
        'edge-swipe-back eligible), and back navigation still returns '
        'cleanly to Kept', (tester) async {
      final item = await keep(
        service,
        text: 'A kept wisdom',
        date: DateTime.utc(2026, 7, 23),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [item],
            isKeeper: true,
            savedReflectionsService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('kept-journal-action')));
      await tester.pumpAndSettle();

      expect(find.byType(JournalScreen), findsOneWidget);
      expect(find.byType(SavedReflectionsScreen), findsNothing);

      // Back returns cleanly via the platform-default pop.
      await tester.tap(find.byKey(const ValueKey('east-back-button')));
      await tester.pumpAndSettle();
      expect(find.byType(JournalScreen), findsNothing);
      expect(find.byType(SavedReflectionsScreen), findsOneWidget);
    });

    testWidgets('a Keeper can enter Journal normally', (tester) async {
      final item = await keep(
        service,
        text: 'A kept wisdom',
        date: DateTime.utc(2026, 7, 23),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [item],
            isKeeper: true,
            savedReflectionsService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('kept-journal-action')));
      await tester.pumpAndSettle();

      expect(find.byType(JournalScreen), findsOneWidget);
      expect(find.byType(KeeperScreen), findsNothing);
      expect(find.text('Journal'), findsOneWidget);
    });
  });
}
