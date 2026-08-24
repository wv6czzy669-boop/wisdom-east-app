import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/screens/journal_screen.dart';
import 'package:wisdom_app/screens/keeper_screen.dart';
import 'package:wisdom_app/screens/reflection_screen.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';
import 'package:wisdom_app/sync_integration/kept_sync_integration_coordinator.dart';
import 'package:wisdom_app/theme/east_design.dart';
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

    expect(find.text('July 22, 2026'), findsOneWidget);
    expect(find.text('July 23, 2026'), findsOneWidget);
    expect(find.text('KEPT'), findsNothing);
    expect(find.text('REFLECTED'), findsOneWidget);
    expect(find.text('ADD REFLECTION'), findsOneWidget);
    expect(find.text('This remains private.'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Newer wisdom')).dy,
      lessThan(tester.getTopLeft(find.text('Older wisdom')).dy),
    );
    expect(first.hasReflection, isFalse);

    expect(
      tester.widget<Text>(find.text('REFLECTED')).style?.fontFamily,
      isNotNull,
    );
  });

  testWidgets(
      'Kept sorts newest to oldest by durable keptAt even when sync/list '
      'arrival order is shuffled', (tester) async {
    final oldest = await keep(
      service,
      text: 'Oldest dated wisdom',
      date: DateTime.utc(2026, 8, 19, 8),
    );
    final newest = await keep(
      service,
      text: 'Newest dated wisdom',
      date: DateTime.utc(2026, 8, 22, 8),
    );
    final middle = await keep(
      service,
      text: 'Middle dated wisdom',
      date: DateTime.utc(2026, 8, 21, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          // Deliberately neither ascending nor descending: simulates an
          // envelope whose record order changed during sync reconciliation.
          reflections: [newest, oldest, middle],
          savedReflectionsService: service,
        ),
      ),
    );

    final newestY = tester.getTopLeft(find.text(newest.text)).dy;
    final middleY = tester.getTopLeft(find.text(middle.text)).dy;
    final oldestY = tester.getTopLeft(find.text(oldest.text)).dy;
    expect(newestY, lessThan(middleY));
    expect(middleY, lessThan(oldestY));
  });

  testWidgets(
      'permanent search filters localized wisdom and private Reflection text '
      'without mutating Kept data', (tester) async {
    final doorway = await keep(
      service,
      text: 'A quiet doorway remains open',
      date: DateTime.utc(2026, 7, 20),
    );
    final reflected = await keep(
      service,
      text: 'Listen without reaching',
      date: DateTime.utc(2026, 7, 21),
    );
    final unrelated = await keep(
      service,
      text: 'The river keeps its pace',
      date: DateTime.utc(2026, 7, 22),
    );
    await service.saveReflection(
      itemId: reflected.id,
      reflection: 'A private seed became visible.',
      isKeeper: true,
    );
    final items = await service.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: eastTheme(),
        home: SavedReflectionsScreen(
          reflections: items,
          savedReflectionsService: service,
        ),
      ),
    );

    final searchField = find.byKey(const ValueKey('kept-search-field'));
    expect(searchField, findsOneWidget);
    expect(find.text('Search'), findsOneWidget);

    await tester.enterText(searchField, 'doorway');
    await tester.pump();
    expect(find.text(doorway.text), findsOneWidget);
    expect(find.text(reflected.text), findsNothing);
    expect(find.text(unrelated.text), findsNothing);

    await tester.enterText(searchField, 'private seed');
    await tester.pump();
    expect(find.text(doorway.text), findsNothing);
    expect(find.text(reflected.text), findsOneWidget);
    expect(find.text('A private seed became visible.'), findsNothing);
    expect(find.text(unrelated.text), findsNothing);

    await tester.enterText(searchField, 'missing');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('kept-search-empty-state')),
      findsOneWidget,
    );
    expect(find.text('Nothing found.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('kept-search-clear')));
    await tester.pump();
    expect(find.text(doorway.text), findsOneWidget);
    expect(find.text(reflected.text), findsOneWidget);
    expect(find.text(unrelated.text), findsOneWidget);
    expect(find.byKey(const ValueKey('kept-search-empty-state')), findsNothing);
    expect(await service.load(), hasLength(3));
  });

  testWidgets('search uses EAST light and dark palette tokens', (tester) async {
    final item = await keep(
      service,
      text: 'A searchable wisdom',
      date: DateTime.utc(2026, 7, 23),
    );

    for (final brightness in Brightness.values) {
      final palette = brightness == Brightness.dark
          ? EastColorScheme.dark
          : EastColorScheme.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: eastTheme(brightness: brightness),
          home: SavedReflectionsScreen(
            key: ValueKey(brightness),
            reflections: [item],
            savedReflectionsService: service,
          ),
        ),
      );
      await tester.pump();

      final shellFinder = find.byKey(const ValueKey('kept-search-shell'));
      final fieldFinder = find.byKey(const ValueKey('kept-search-field'));
      final shell = tester.widget<AnimatedContainer>(shellFinder);
      final decoration = shell.decoration! as BoxDecoration;
      final border = decoration.border! as Border;
      final field = tester.widget<TextField>(fieldFinder);
      final searchIcon = tester.widget<Icon>(find.byIcon(Icons.search));

      expect(border.bottom.color, palette.divider);
      expect(field.cursorColor, palette.ink);
      expect(field.decoration!.hintStyle!.color, palette.hint);
      expect(searchIcon.color, palette.secondary);
      expect(
        Theme.of(tester.element(fieldFinder)).scaffoldBackgroundColor,
        palette.background,
      );

      await tester.tap(fieldFinder);
      await tester.pump(const Duration(milliseconds: 160));
      final focusedShell = tester.widget<AnimatedContainer>(shellFinder);
      final focusedDecoration = focusedShell.decoration! as BoxDecoration;
      final focusedBorder = focusedDecoration.border! as Border;
      expect(focusedBorder.bottom.color, palette.ink);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('search and clear expose localized accessible controls',
      (tester) async {
    final item = await keep(
      service,
      text: 'Accessible search',
      date: DateTime.utc(2026, 7, 23),
    );
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: eastTheme(),
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: service,
        ),
      ),
    );

    final searchField = find.byKey(const ValueKey('kept-search-field'));
    final searchSemantics = tester
        .getSemantics(find.byKey(const ValueKey('kept-search-semantics')))
        .getSemanticsData();
    expect(searchSemantics.label, contains('Search'));
    expect(searchSemantics.flagsCollection.isTextField, isTrue);

    await tester.enterText(searchField, 'accessible');
    await tester.pump();
    final clearSemantics = tester
        .getSemantics(
          find.byKey(const ValueKey('kept-search-clear-semantics')),
        )
        .getSemanticsData();
    expect(clearSemantics.label, 'Clear search');
    expect(clearSemantics.hasAction(SemanticsAction.tap), isTrue);

    semantics.dispose();
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

  testWidgets('tapping an unreflected wisdom opens its Reflection editor',
      (tester) async {
    final item = await keep(
      service,
      text: 'The wisdom itself opens reflection',
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

    await tester.tap(find.byKey(ValueKey('kept-${item.id}-wisdom-action')));
    await tester.pumpAndSettle();

    expect(find.byType(ReflectionScreen), findsOneWidget);
    expect(find.text(item.text), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reflection-writing-area')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a reflected wisdom opens its existing Reflection',
      (tester) async {
    final item = await keep(
      service,
      text: 'Open the existing reflection from the wisdom',
      date: DateTime.utc(2026, 7, 23),
    );
    await service.saveReflection(
      itemId: item.id,
      reflection: 'Existing reflection opened from wisdom.',
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

    await tester.tap(
      find.byKey(ValueKey('kept-${reflected.id}-wisdom-action')),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('reflection-writing-area')),
    );
    expect(field.controller!.text, 'Existing reflection opened from wisdom.');
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
    expect(find.text('KEPT'), findsNothing);
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
    // reach it and open the decision overlay — proving the foreground row
    // is no longer covering that region once the row is open. This uses
    // the real widget location (no `warnIfMissed: false`, no arbitrary
    // coordinates, no bypassing the UI).
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('kept-delete-decision')), findsOneWidget);
    expect(find.text(item.text), findsOneWidget);
    expect(await service.load(), hasLength(1));

    final semantics = tester.ensureSemantics();
    final cancel = tester.getSemantics(
      find.descendant(
        of: find.byKey(const ValueKey('kept-delete-decision')),
        matching: find.text('CANCEL'),
      ),
    );
    final delete = tester.getSemantics(
      find.descendant(
        of: find.byKey(const ValueKey('kept-delete-decision')),
        matching: find.text('DELETE'),
      ),
    );
    expect(cancel.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(delete.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('kept-delete-decision')),
        matching: find.text('DELETE'),
      ),
    );
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
    await tester.tap(
      find.byKey(ValueKey('kept-${item.id}-swipe-foreground')),
    );
    await tester.pumpAndSettle();

    expect(find.text(item.text), findsOneWidget);
    expect(find.byType(ReflectionScreen), findsNothing);
    expect(await service.load(), hasLength(1));
  });

  testWidgets(
      'tapping the DELETE action requires the EAST full-field decision and Cancel preserves the item',
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

    final closedWisdomX = tester.getTopLeft(find.text(item.text)).dx;

    await tester.drag(
      find.byKey(ValueKey('kept-${item.id}')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('kept-${item.id}-delete-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('kept-delete-decision')), findsOneWidget);
    expect(find.text('Remove from Kept?'), findsOneWidget);
    expect(
      find.text('This wisdom and its Reflection will be removed.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Removed from Kept.'), findsNothing);
    expect(find.text('Undo'), findsNothing);
    expect(find.text(item.text), findsOneWidget);
    expect(await service.load(), hasLength(1));

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('kept-delete-decision')),
        matching: find.text('CANCEL'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('kept-delete-decision')), findsNothing);
    expect(find.text(item.text), findsOneWidget);
    expect(tester.getTopLeft(find.text(item.text)).dx, closedWisdomX);
    final semantics = tester.ensureSemantics();
    expect(find.semantics.byLabel('DELETE'), findsNothing);
    semantics.dispose();
    expect(await service.load(), hasLength(1));
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
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('kept-delete-decision')),
        matching: find.text('DELETE'),
      ),
    );
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
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('kept-delete-decision')),
        matching: find.text('DELETE'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(item.text), findsOneWidget);
    expect(
      find.text('This wisdom could not be removed. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Undo'), findsNothing);
    expect(await service.load(), hasLength(1));
  });

  testWidgets('Kept delete decision stays usable at 200% text scale',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final item = await keep(
      service,
      text: 'A wisdom protected by confirmation',
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

    expect(find.byKey(const ValueKey('kept-delete-decision')), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets(
      'Kept stays usable at 100/135/160/200% text scale '
      '(Build 33 accessibility repair)', (tester) async {
    final item = await keep(
      service,
      text:
          'A longer wisdom remains readable without turning the page into a card.',
      date: DateTime.utc(2026, 7, 23),
    );

    for (final scale in [1.0, 1.35, 1.6, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [item],
            savedReflectionsService: service,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('kept-journal-control')),
        findsOneWidget,
        reason: 'Journal must remain reachable at ${scale}x.',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'Kept re-check (Build 33 real-device repair): a long Turkish wisdom '
      'renders intact and reachable at 100/135/160/200% text scale',
      (tester) async {
    // Same real-device-reported wisdom (east_wisdom_0195) that broke on
    // Home's revealed-wisdom column ("hikây/enin", "tama/mı de/ğildir").
    // Kept's own wisdom Text has no fixed-fraction width constraint (it
    // wraps to the full row width inside the list, unlike Home's
    // deliberately narrow composition) -- this is a confirmatory
    // regression check, not a fix.
    const turkish = 'Yara hikâyenin tamamı değildir.';
    final item =
        await keep(service, text: turkish, date: DateTime.utc(2026, 7, 23));

    for (final scale in [1.0, 1.35, 1.6, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [item],
            savedReflectionsService: service,
          ),
        ),
      );
      await tester.pump();

      // A single `find.text(turkish)` match with the full, exact string as
      // one Text widget's `data` is only possible if the wisdom rendered
      // intact -- a mid-word break, truncation, or overflow-driven
      // substitution would all break this exact-string match.
      expect(find.text(turkish), findsOneWidget, reason: '${scale}x');
      expect(
        find.byKey(const ValueKey('kept-journal-control')),
        findsOneWidget,
        reason: 'Journal must remain reachable at ${scale}x.',
      );
      expect(tester.takeException(), isNull, reason: '${scale}x');
    }
  });

  group('Voice Control actionability (Build 33 real-device repair): Kept', () {
    testWidgets('Back has SemanticsAction.tap', (tester) async {
      final item = await keep(
        service,
        text: 'A wisdom to open Kept for',
        date: DateTime.utc(2026, 7, 23),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => SavedReflectionsScreen(
                      reflections: [item],
                      savedReflectionsService: service,
                    ),
                  ),
                );
              },
              child: const Text('Open Kept'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Kept'));
      await tester.pumpAndSettle();

      final semantics = tester.ensureSemantics();
      final node = tester.getSemantics(
        find.byKey(const ValueKey('east-back-button')),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    testWidgets('Journal has a label and SemanticsAction.tap', (tester) async {
      final item = await keep(
        service,
        text: 'A wisdom kept for Journal semantics',
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
      await tester.pump();

      final semantics = tester.ensureSemantics();
      final node = tester.getSemantics(
        find.byKey(const ValueKey('kept-journal-control')),
      );
      expect(node.label, 'Journal');
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    // ROOT CAUSE: `_status`/`_keptItem`'s Reflection-action `Semantics`
    // previously used the *identical* generic label
    // (`l10n.addReflection`/`l10n.reflectedEditReflection`) for every row
    // -- Voice Control's "Show Names" could not distinguish "Add
    // Reflection" for item 1 from "Add Reflection" for item 2. Also
    // missing `onTap` on the outer node (same defect class as elsewhere
    // this session). Fixed with a 1-based, screen-order item number baked
    // into the label (`addReflectionNumbered`/`openReflectionNumbered`).
    testWidgets(
        'each unreflected row has a UNIQUE "Add Reflection, item N" label '
        'with SemanticsAction.tap', (tester) async {
      final first = await keep(
        service,
        text: 'The first kept wisdom',
        date: DateTime.utc(2026, 7, 22),
      );
      final second = await keep(
        service,
        text: 'The second kept wisdom',
        date: DateTime.utc(2026, 7, 23),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SavedReflectionsScreen(
            reflections: [first, second],
            savedReflectionsService: service,
          ),
        ),
      );
      await tester.pump();

      final semantics = tester.ensureSemantics();
      // Newest first (`second`) is item 1 on screen; `first` is item 2.
      final item1 = tester.getSemantics(
        find.text('ADD REFLECTION').at(0),
      );
      final item2 = tester.getSemantics(
        find.text('ADD REFLECTION').at(1),
      );
      expect(item1.label, 'Add Reflection, item 1');
      expect(item2.label, 'Add Reflection, item 2');
      expect(item1.label, isNot(item2.label));
      expect(item1.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(item2.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    testWidgets(
        'each already-reflected row has a UNIQUE "Open Reflection, item N" '
        'label with SemanticsAction.tap', (tester) async {
      final first = await keep(
        service,
        text: 'The first reflected wisdom',
        date: DateTime.utc(2026, 7, 22),
      );
      final second = await keep(
        service,
        text: 'The second reflected wisdom',
        date: DateTime.utc(2026, 7, 23),
      );
      await service.saveReflection(
        itemId: first.id,
        reflection: 'A private note on the first.',
        isKeeper: false,
      );
      await service.saveReflection(
        itemId: second.id,
        reflection: 'A private note on the second.',
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
      await tester.pump();

      final semantics = tester.ensureSemantics();
      final item1 = tester.getSemantics(find.text('REFLECTED').at(0));
      final item2 = tester.getSemantics(find.text('REFLECTED').at(1));
      expect(item1.label, 'Open Reflection, item 1');
      expect(item2.label, 'Open Reflection, item 2');
      expect(item1.label, isNot(item2.label));
      expect(item1.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(item2.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    testWidgets(
        'a row-level accessible Delete alternative remains available '
        'alongside the swipe gesture', (tester) async {
      final item = await keep(
        service,
        text: 'A wisdom with an accessible delete alternative',
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
      await tester.pump();

      final semantics = tester.ensureSemantics();
      // `CustomSemanticsAction` is registered on `_keptItem`'s row-level
      // Semantics ancestor -- the row's own key (`kept-${item.id}`, set on
      // `_KeptSwipeToDeleteRow`) is its direct child, so this proves the
      // action is present at the row scope regardless of which specific
      // control (ADD REFLECTION vs REFLECTED) the row happens to show.
      final node = tester.getSemantics(
        find.byKey(ValueKey('kept-${item.id}')),
      );
      expect(
        node.getSemanticsData().customSemanticsActionIds,
        isNotEmpty,
        reason: 'a row-level accessible Delete alternative must remain '
            'available regardless of swipe state.',
      );
      semantics.dispose();
    });
  });

  group('Kept header', () {
    testWidgets(
        'has no Return control or visible Journal row, and the first item '
        'begins directly below the header', (tester) async {
      final item = await keep(
        service,
        text: 'A kept wisdom',
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
      await tester.pumpAndSettle();

      expect(find.text('Return'), findsNothing);
      expect(find.text('Journal'), findsNothing);
      expect(find.byKey(const ValueKey('kept-return-action')), findsNothing);
      expect(find.byKey(const ValueKey('kept-journal-action')), findsNothing);
      final semantics = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('kept-journal-control')),
            )
            .label,
        'Journal',
      );
      semantics.dispose();
      expect(
        tester.getTopLeft(find.text(item.text)).dy,
        lessThan(180),
      );
    });

    testWidgets('back control remains available when Kept is pushed',
        (tester) async {
      final item = await keep(
        service,
        text: 'A kept wisdom',
        date: DateTime.utc(2026, 7, 23),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => SavedReflectionsScreen(
                      reflections: [item],
                      savedReflectionsService: service,
                    ),
                  ),
                );
              },
              child: const Text('Open Kept'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Kept'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('east-back-button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('east-back-button')));
      await tester.pumpAndSettle();
      expect(find.text('Open Kept'), findsOneWidget);
    });
  });

  // Journal is available from Kept's icon-only header action.
  group('Journal', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
        'Journal is offered from the header without disturbing the existing '
        'Kept and Reflection content', (tester) async {
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

      expect(
        find.byKey(const ValueKey('kept-journal-control')),
        findsOneWidget,
      );
      expect(find.textContaining('KEEPER'), findsNothing);
      expect(find.text('Kept'), findsOneWidget);
      expect(find.text('KEPT'), findsNothing);
      expect(find.text('ADD REFLECTION'), findsOneWidget);
      expect(find.text(item.text), findsOneWidget);
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

      await tester.tap(find.byKey(const ValueKey('kept-journal-control')));
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

      await tester.tap(find.byKey(const ValueKey('kept-journal-control')));
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

      await tester.tap(find.byKey(const ValueKey('kept-journal-control')));
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

      await tester.tap(find.byKey(const ValueKey('kept-journal-control')));
      await tester.pumpAndSettle();

      expect(find.byType(JournalScreen), findsOneWidget);
      expect(find.byType(KeeperScreen), findsNothing);
      expect(find.text('Journal'), findsOneWidget);
    });
  });
}
