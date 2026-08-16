import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/screens/reflection_screen.dart';
import 'package:wisdom_app/services/analytics_event.dart';
import 'package:wisdom_app/services/analytics_service.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';
import 'package:wisdom_app/sync_integration/kept_sync_integration_coordinator.dart';
import 'package:wisdom_app/utils/reflection_prompt.dart';

import 'persistence_test_helpers.dart';
import 'sync_integration/in_memory_sync_test_doubles.dart';

void main() {
  late KeptRepositoryTestGraph graph;
  late SavedReflectionsService service;
  late FavoriteItem item;

  setUp(() async {
    graph = KeptRepositoryTestGraph(
      clock: () => DateTime.utc(2026, 7, 23),
    );
    service = graph.service;
    final result = await service.toggle(
      revealId: 'a5f3c111-1111-4111-8111-111111111111',
      text: 'The associated wisdom remains visible.',
      date: 'July 23, 2026',
      revealedAt: DateTime.utc(2026, 7, 23),
      isKeeper: false,
    );
    item = result.items.single;
  });

  /// A harness with its own repository/coordinator (never the shared
  /// [graph]/[service] above), so each test can observe exactly how many
  /// times a fresh, durably-written mutation would have nudged CloudKit
  /// sync ([onMutationCommitted]) and/or force a genuine local write
  /// failure -- without affecting any other test's persisted state.
  SavedReflectionsService buildHarness({void Function()? onMutationCommitted}) {
    final store = InMemoryKeptStateStore();
    final repository = KeptRepository(
      store: store,
      bootstrap: const KeptBootstrapResult.ready(),
      operationCoordinator: PersistenceOperationCoordinator(),
      clock: () => DateTime.utc(2026, 7, 23),
    );
    final coordinator = KeptSyncIntegrationCoordinator(
      keptRepository: repository,
      intentStore: InMemoryLocalSyncIntentStore(),
      syncPersistenceStore: InMemorySyncPersistenceStore(),
      clock: () => DateTime.utc(2026, 7, 23),
      onMutationCommitted: onMutationCommitted,
    );
    return SavedReflectionsService(
      keptRepository: repository,
      syncCoordinator: coordinator,
    );
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

  Widget openable(FavoriteItem target, {SavedReflectionsService? withService}) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          return TextButton(
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => ReflectionScreen(
                    item: target,
                    isKeeper: false,
                    savedReflectionsService: withService ?? service,
                    autosaveDebounce: const Duration(milliseconds: 200),
                  ),
                ),
              );
            },
            child: const Text('Open'),
          );
        },
      ),
    );
  }

  testWidgets(
      'the dedicated Reflection screen still exists and opening a '
      'Reflection still enters it', (tester) async {
    await tester.pumpWidget(openable(item));

    expect(find.byType(ReflectionScreen), findsNothing);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(ReflectionScreen), findsOneWidget);
    expect(find.text('Reflection'), findsOneWidget);
    expect(find.text(item.text), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reflection-writing-area')),
      findsOneWidget,
    );
  });

  testWidgets('"Hey." is gone', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
          home: ReflectionScreen(
              item: item, isKeeper: false, savedReflectionsService: service)),
    );

    expect(find.text('Hey.'), findsNothing);
    final field = find.byKey(const ValueKey('reflection-writing-area'));
    expect(tester.widget<TextField>(field).decoration?.hintText, isNot('Hey.'));
  });

  testWidgets('no explicit Save button exists', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
          home: ReflectionScreen(
              item: item, isKeeper: false, savedReflectionsService: service)),
    );

    expect(find.text('Keep Reflection'), findsNothing);
    expect(find.byKey(const ValueKey('keep-reflection-action')), findsNothing);
  });

  testWidgets(
      'no separate Edit mode is required -- a fresh and an already-'
      'reflected item both open straight into the same editable field',
      (tester) async {
    await service.saveReflection(
      itemId: item.id,
      reflection: 'Already written',
      isKeeper: false,
    );
    final reflected = (await service.load()).single;

    await tester.pumpWidget(
      MaterialApp(
        home: ReflectionScreen(
          item: reflected,
          isKeeper: false,
          savedReflectionsService: service,
        ),
      ),
    );

    final field = find.byKey(const ValueKey('reflection-writing-area'));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).enabled, isTrue);
    expect(tester.widget<TextField>(field).controller!.text, 'Already written');
    // No mode-toggle affordance of any kind exists anywhere on screen.
    expect(find.text('Edit'), findsNothing);
  });

  group('prompt selection', () {
    testWidgets(
        'each revealId resolves to exactly one of the six approved '
        'prompts', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            home: ReflectionScreen(
                item: item, isKeeper: false, savedReflectionsService: service)),
      );

      final expected = reflectionPromptFor(item.revealId!);
      expect(reflectionPrompts, contains(expected));
      expect(find.text(expected), findsOneWidget);
      final field = find.byKey(const ValueKey('reflection-writing-area'));
      expect(tester.widget<TextField>(field).decoration?.hintText, expected);
    });

    testWidgets(
        'the same revealId always resolves to the same prompt across '
        'rebuild, relaunch (fresh widget instance), and reopen',
        (tester) async {
      final expected = reflectionPromptFor(item.revealId!);

      await tester.pumpWidget(
        MaterialApp(
            home: ReflectionScreen(
                item: item, isKeeper: false, savedReflectionsService: service)),
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('reflection-writing-area')),
            )
            .decoration
            ?.hintText,
        expected,
      );

      // Rebuild in place.
      await tester.pumpWidget(
        MaterialApp(
            home: ReflectionScreen(
                item: item, isKeeper: false, savedReflectionsService: service)),
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('reflection-writing-area')),
            )
            .decoration
            ?.hintText,
        expected,
      );

      // A wholly fresh widget instance (simulating relaunch/reopen), backed
      // by an independently-read copy of the exact same persisted item.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final reopened = (await service.load()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: reopened,
            isKeeper: false,
            savedReflectionsService: service,
          ),
        ),
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('reflection-writing-area')),
            )
            .decoration
            ?.hintText,
        expected,
      );
    });

    testWidgets(
        'writing, saving, and reopening a Reflection never changes its '
        'prompt', (tester) async {
      final expected = reflectionPromptFor(item.revealId!);

      await tester.pumpWidget(openable(item));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('reflection-writing-area')),
        'Some private words.',
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pageBack();
      await tester.pumpAndSettle();

      final reflected = (await service.load()).single;
      expect(reflected.reflection, 'Some private words.');

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: reflected,
            isKeeper: false,
            savedReflectionsService: service,
          ),
        ),
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('reflection-writing-area')),
            )
            .decoration
            ?.hintText,
        expected,
      );
    });

    testWidgets('different revealIds can resolve independently',
        (tester) async {
      final second = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-222222222222',
        text: 'A second wisdom',
        date: 'July 24, 2026',
        revealedAt: DateTime.utc(2026, 7, 24),
        isKeeper: false,
      );
      final secondItem = second.items.last;

      await tester.pumpWidget(
        MaterialApp(
            home: ReflectionScreen(
                item: item, isKeeper: false, savedReflectionsService: service)),
      );
      final firstPrompt = tester
          .widget<TextField>(
            find.byKey(const ValueKey('reflection-writing-area')),
          )
          .decoration
          ?.hintText;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: secondItem,
            isKeeper: false,
            savedReflectionsService: service,
          ),
        ),
      );
      final secondPrompt = tester
          .widget<TextField>(
            find.byKey(const ValueKey('reflection-writing-area')),
          )
          .decoration
          ?.hintText;

      expect(firstPrompt, reflectionPromptFor(item.revealId!));
      expect(secondPrompt, reflectionPromptFor(secondItem.revealId!));
    });

    testWidgets(
        'a pre-existing legacy record with no revealId still resolves to '
        'exactly one of the six prompts, using its stable id instead',
        (tester) async {
      const legacyItem = FavoriteItem(
        id: 'legacy-id-no-reveal',
        text: 'A Build 25 wisdom',
        date: 'July 1, 2026',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: legacyItem,
            isKeeper: false,
            savedReflectionsService: service,
          ),
        ),
      );

      final expected = reflectionPromptFor(legacyItem.id);
      expect(reflectionPrompts, contains(expected));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('reflection-writing-area')),
            )
            .decoration
            ?.hintText,
        expected,
      );
    });
  });

  group('autosave', () {
    testWidgets(
        'typing persists the Reflection locally without any manual '
        'Save action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: item,
            isKeeper: false,
            savedReflectionsService: service,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('reflection-writing-area')),
        'Autosaved without a button.',
      );
      expect((await service.load()).single.hasReflection, isFalse);

      await tester.pump(const Duration(milliseconds: 250));

      final persisted = await service.load();
      expect(persisted.single.reflection, 'Autosaved without a button.');
    });

    testWidgets(
        'rapid edits leave only the latest text persisted, with a single '
        'coalesced write -- not one per keystroke', (tester) async {
      var mutationCount = 0;
      final harness = buildHarness(onMutationCommitted: () => mutationCount++);
      await harness.toggle(
        revealId: 'a5f3c111-1111-4111-8111-333333333333',
        text: 'Rapid typing wisdom',
        date: 'July 23, 2026',
        revealedAt: DateTime.utc(2026, 7, 23),
        isKeeper: false,
      );
      final rapidItem = (await harness.load()).single;
      // Reset: the seeding `toggle()` call above is itself a durable
      // mutation and already notified `onMutationCommitted` once -- only
      // mutations from typing in the screen below are under test here.
      mutationCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: rapidItem,
            isKeeper: false,
            savedReflectionsService: harness,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      final field = find.byKey(const ValueKey('reflection-writing-area'));
      for (final text in ['R', 'Ra', 'Rap', 'Rapi', 'Rapid', 'Rapid t']) {
        await tester.enterText(field, text);
        await tester.pump(const Duration(milliseconds: 40));
      }
      // Nothing has settled yet -- still within the debounce window.
      expect((await harness.load()).single.hasReflection, isFalse);
      expect(mutationCount, 0);

      await tester.pump(const Duration(milliseconds: 250));

      final persisted = await harness.load();
      expect(persisted.single.reflection, 'Rapid t');
      expect(mutationCount, 1);
    });

    testWidgets(
        'leaving immediately after typing does not lose the latest text',
        (tester) async {
      await tester.pumpWidget(openable(item));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('reflection-writing-area')),
        'Written and left at once.',
      );
      // No time advanced past the debounce -- leave right away.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(ReflectionScreen), findsNothing);
      final persisted = await service.load();
      expect(persisted.single.reflection, 'Written and left at once.');
    });

    testWidgets(
        'backgrounding the app immediately after typing does not lose the '
        'latest text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: item,
            isKeeper: false,
            savedReflectionsService: service,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('reflection-writing-area')),
        'Backgrounded right after typing.',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump();

      final persisted = await service.load();
      expect(persisted.single.reflection, 'Backgrounded right after typing.');
    });

    testWidgets(
        'editing an existing Reflection updates the same revealId '
        'occurrence and creates no duplicate', (tester) async {
      await service.saveReflection(
        itemId: item.id,
        reflection: 'Original text',
        isKeeper: false,
      );
      final reflected = (await service.load()).single;

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: reflected,
            isKeeper: false,
            savedReflectionsService: service,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('reflection-writing-area')),
        'Edited text',
      );
      await tester.pump(const Duration(milliseconds: 250));

      final persisted = await service.load();
      expect(persisted, hasLength(1));
      expect(persisted.single.id, item.id);
      expect(persisted.single.revealId, item.revealId);
      expect(persisted.single.reflection, 'Edited text');
    });

    testWidgets('the wisdom remains visible throughout typing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: item,
            isKeeper: false,
            savedReflectionsService: service,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      expect(find.text(item.text), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('reflection-writing-area')),
        'Writing while the wisdom stays put.',
      );
      await tester.pump();
      expect(find.text(item.text), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(item.text), findsOneWidget);
    });

    testWidgets('no constant "Saving..." indicator is ever shown',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: item,
            isKeeper: false,
            savedReflectionsService: service,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('reflection-writing-area')),
        'No saving indicator please.',
      );
      await tester.pump();
      expect(find.textContaining('Saving'), findsNothing);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.textContaining('Saving'), findsNothing);
    });
  });

  group('sync coalescing and failure containment', () {
    testWidgets(
        'a local write failure shows a message but never loses the typed '
        'text from the field', (tester) async {
      final failingService = failingWritesService();

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: item,
            isKeeper: false,
            savedReflectionsService: failingService,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      final field = find.byKey(const ValueKey('reflection-writing-area'));
      await tester.enterText(field, 'Do not lose this.');
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.text(
          'Reflection could not be saved. It will try again as you keep '
          'writing.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(field).controller!.text,
          'Do not lose this.');
    });

    testWidgets(
        'a sync/network failure (the CloudKit-nudge callback throwing) '
        'never loses or blocks the locally saved text', (tester) async {
      final harness = buildHarness(
        onMutationCommitted: () => throw StateError('network unavailable'),
      );
      await harness.toggle(
        revealId: 'a5f3c111-1111-4111-8111-444444444444',
        text: 'Sync failure wisdom',
        date: 'July 23, 2026',
        revealedAt: DateTime.utc(2026, 7, 23),
        isKeeper: false,
      );
      final syncItem = (await harness.load()).single;

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: syncItem,
            isKeeper: false,
            savedReflectionsService: harness,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('reflection-writing-area')),
        'Saved locally despite sync failure.',
      );
      await tester.pump(const Duration(milliseconds: 250));

      final persisted = await harness.load();
      expect(
          persisted.single.reflection, 'Saved locally despite sync failure.');
      // The local save is authoritative -- no failure feedback for a
      // sync-layer problem that never touched the local write itself.
      expect(find.textContaining('could not be saved'), findsNothing);
    });

    testWidgets(
        'coalesced sync eventually carries the latest Reflection state, '
        'across two separate pauses in typing', (tester) async {
      var mutationCount = 0;
      final harness = buildHarness(onMutationCommitted: () => mutationCount++);
      await harness.toggle(
        revealId: 'a5f3c111-1111-4111-8111-555555555555',
        text: 'Two-pause wisdom',
        date: 'July 23, 2026',
        revealedAt: DateTime.utc(2026, 7, 23),
        isKeeper: false,
      );
      final twoPauseItem = (await harness.load()).single;
      // Reset: the seeding `toggle()` call above already notified
      // `onMutationCommitted` once for the Keep itself.
      mutationCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: twoPauseItem,
            isKeeper: false,
            savedReflectionsService: harness,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      final field = find.byKey(const ValueKey('reflection-writing-area'));
      await tester.enterText(field, 'First pause');
      await tester.pump(const Duration(milliseconds: 250));
      expect(mutationCount, 1);

      await tester.enterText(field, 'First pause, then more');
      await tester.pump(const Duration(milliseconds: 250));
      expect(mutationCount, 2);

      final persisted = await harness.load();
      expect(persisted.single.reflection, 'First pause, then more');
    });

    testWidgets(
        'a transient local-write failure at the flush-triggered (leaving) '
        'moment self-heals via retry, so leaving right after typing never '
        'silently drops the save', (tester) async {
      final harness = buildHarness();
      await harness.toggle(
        revealId: 'a5f3c111-1111-4111-8111-666666666666',
        text: 'Flush retry wisdom',
        date: 'July 23, 2026',
        revealedAt: DateTime.utc(2026, 7, 23),
        isKeeper: false,
      );
      final flushItem = (await harness.load()).single;
      final flaky = _FlakyOnceSavedReflectionsService(delegate: harness);

      await tester.pumpWidget(openable(flushItem, withService: flaky));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('reflection-writing-area')),
        'Typed right before a flaky first save attempt.',
      );
      // No time advanced past the debounce -- leave right away, so the
      // pop-triggered flush is the one and only attempt path exercised.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(flaky.callCount, greaterThan(1));
      expect(find.textContaining('could not be saved'), findsNothing);
      final persisted = await harness.load();
      expect(
        persisted.single.reflection,
        'Typed right before a flaky first save attempt.',
      );
    });

    testWidgets(
        'an ordinary typing-triggered autosave failure (never a flush) '
        'still surfaces immediately, with no retry delay', (tester) async {
      final failingService = failingWritesService();

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: item,
            isKeeper: false,
            savedReflectionsService: failingService,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('reflection-writing-area')),
        'Ordinary typing failure, not a flush.',
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.text(
          'Reflection could not be saved. It will try again as you keep '
          'writing.',
        ),
        findsOneWidget,
      );
    });
  });

  group('unaffected surrounding behavior', () {
    testWidgets(
        'Kept/revealId identity is unchanged: the reflected item '
        'keeps its original id and revealId after autosave', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: item,
            isKeeper: false,
            savedReflectionsService: service,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('reflection-writing-area')),
        'Identity must not move.',
      );
      await tester.pump(const Duration(milliseconds: 250));

      final persisted = await service.load();
      expect(persisted.single.id, item.id);
      expect(persisted.single.revealId, item.revealId);
      expect(persisted.single.text, item.text);
    });

    testWidgets(
        'reflection deletion still requires confirmation and keeps '
        'the wisdom', (tester) async {
      await service.saveReflection(
        itemId: item.id,
        reflection: 'Private memory',
        isKeeper: false,
      );
      final reflected = (await service.load()).single;

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: reflected,
            isKeeper: false,
            savedReflectionsService: service,
          ),
        ),
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Reflection?'), findsOneWidget);

      // Approved Ritual direction: the confirmation is a full-field
      // takeover in the ritual voice, not a system AlertDialog -- Cancel/
      // Delete are the tracked "CANCEL"/"DELETE" labels inside it.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('reflection-delete-decision')),
          matching: find.text('DELETE'),
        ),
      );
      await tester.pumpAndSettle();

      final persisted = await service.load();
      expect(persisted, hasLength(1));
      expect(persisted.single.text, item.text);
      expect(persisted.single.hasReflection, isFalse);
    });

    testWidgets(
        'the delete decision can be cancelled, leaving the '
        'reflection untouched', (tester) async {
      await service.saveReflection(
        itemId: item.id,
        reflection: 'Private memory',
        isKeeper: false,
      );
      final reflected = (await service.load()).single;

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: reflected,
            isKeeper: false,
            savedReflectionsService: service,
          ),
        ),
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Reflection?'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('reflection-delete-decision')),
          matching: find.text('CANCEL'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete Reflection?'), findsNothing);
      final persisted = await service.load();
      expect(persisted.single.reflection, 'Private memory');
    });

    testWidgets('failed reflection deletion keeps the reflected state intact',
        (tester) async {
      await service.saveReflection(
        itemId: item.id,
        reflection: 'Keep this on failure',
        isKeeper: false,
      );
      final reflected = (await service.load()).single;
      final failingService = failingWritesService();

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: reflected,
            isKeeper: false,
            savedReflectionsService: failingService,
          ),
        ),
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('reflection-delete-decision')),
          matching: find.text('DELETE'),
        ),
      );
      await tester.pump();

      expect(
        find.text('Reflection could not be deleted. Please try again.'),
        findsOneWidget,
      );
      expect((await service.load()).single.reflection, 'Keep this on failure');
    });

    testWidgets('counter appears only near the enforced 250 character limit',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: item,
            isKeeper: false,
            savedReflectionsService: service,
          ),
        ),
      );

      final field = find.byKey(const ValueKey('reflection-writing-area'));
      await tester.enterText(field, List.filled(219, 'a').join());
      await tester.pump();
      expect(find.text('219/250'), findsNothing);

      await tester.enterText(field, List.filled(220, 'a').join());
      await tester.pump();
      expect(find.text('220/250'), findsOneWidget);

      await tester.enterText(field, List.filled(260, 'a').join());
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, hasLength(250));
      expect(find.text('250/250'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('analytics', () {
    testWidgets(
        'reflection_saved does not fire once per keystroke -- only once '
        'per coalesced autosave settle -- and never carries Reflection '
        'text or a private identifier', (tester) async {
      final transport = _FakeAnalyticsTransport();
      final store = InMemoryKeptStateStore();
      final repository = KeptRepository(
        store: store,
        bootstrap: const KeptBootstrapResult.ready(),
        operationCoordinator: PersistenceOperationCoordinator(),
        clock: () => DateTime.utc(2026, 7, 23),
      );
      final coordinator = KeptSyncIntegrationCoordinator(
        keptRepository: repository,
        intentStore: InMemoryLocalSyncIntentStore(),
        syncPersistenceStore: InMemorySyncPersistenceStore(),
        clock: () => DateTime.utc(2026, 7, 23),
      );
      final analyticsAwareService = SavedReflectionsService(
        keptRepository: repository,
        syncCoordinator: coordinator,
        analyticsService: AnalyticsService(transport: transport),
      );
      await analyticsAwareService.toggle(
        revealId: 'a5f3c111-1111-4111-8111-666666666666',
        text: 'Analytics wisdom',
        date: 'July 23, 2026',
        revealedAt: DateTime.utc(2026, 7, 23),
        isKeeper: false,
      );
      final analyticsItem = (await analyticsAwareService.load()).single;
      // Reset: the seeding `toggle()` call above already fired its own
      // `kept_saved` event for the Keep itself.
      transport.tracked.clear();

      await tester.pumpWidget(
        MaterialApp(
          home: ReflectionScreen(
            item: analyticsItem,
            isKeeper: false,
            savedReflectionsService: analyticsAwareService,
            autosaveDebounce: const Duration(milliseconds: 200),
          ),
        ),
      );

      final field = find.byKey(const ValueKey('reflection-writing-area'));
      for (final text in ['P', 'Pr', 'Pri', 'Priv', 'Priva', 'Private']) {
        await tester.enterText(field, text);
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(transport.tracked, isEmpty);

      await tester.pump(const Duration(milliseconds: 250));

      expect(transport.tracked, [AnalyticsEvent.reflectionSaved]);
      // AnalyticsEvent carries only its fixed `eventName` -- there is no
      // second field any Reflection text or identifier could travel
      // through.
      for (final event in transport.tracked) {
        expect(event.eventName, isNot(contains('Private')));
        expect(event.eventName, isNot(contains(analyticsItem.id)));
        expect(event.eventName, isNot(contains(analyticsItem.revealId!)));
      }
    });
  });
}

class _FakeAnalyticsTransport implements AnalyticsTransport {
  final List<AnalyticsEvent> tracked = [];

  @override
  void track(AnalyticsEvent event) {
    tracked.add(event);
  }
}

/// Wraps a real [SavedReflectionsService] and makes its very first
/// [saveReflection] call throw -- simulating a genuine, transient
/// real-device local-write failure (momentary disk/lock contention) that no
/// in-memory test double would otherwise ever produce. Every call after the
/// first delegates normally.
class _FlakyOnceSavedReflectionsService implements SavedReflectionsService {
  _FlakyOnceSavedReflectionsService({required SavedReflectionsService delegate})
      : _delegate = delegate;

  final SavedReflectionsService _delegate;
  int callCount = 0;
  bool _hasThrown = false;

  @override
  Future<SavedReflectionsResult> saveReflection({
    required String itemId,
    required String reflection,
    required bool isKeeper,
    DateTime? reflectedAt,
  }) async {
    callCount += 1;
    if (!_hasThrown) {
      _hasThrown = true;
      throw StateError('transient local-write failure');
    }
    return _delegate.saveReflection(
      itemId: itemId,
      reflection: reflection,
      isKeeper: isKeeper,
      reflectedAt: reflectedAt,
    );
  }

  @override
  Future<List<FavoriteItem>> load() => _delegate.load();

  @override
  Future<SavedReflectionsResult> toggle({
    required String text,
    required String date,
    required bool isKeeper,
    required String revealId,
    required DateTime revealedAt,
    String? existingId,
  }) =>
      _delegate.toggle(
        text: text,
        date: date,
        isKeeper: isKeeper,
        revealId: revealId,
        revealedAt: revealedAt,
        existingId: existingId,
      );

  @override
  Future<List<FavoriteItem>> deleteReflection({required String itemId}) =>
      _delegate.deleteReflection(itemId: itemId);

  @override
  Future<RemovedSavedReflection?> remove({required String itemId}) =>
      _delegate.remove(itemId: itemId);

  @override
  Future<List<FavoriteItem>> restore(RemovedSavedReflection removed) =>
      _delegate.restore(removed);

  @override
  Future<String?> resolveLegacyMigratedRevealIdForOccurrence({
    required String wisdomText,
    required DateTime committedRevealedAt,
    required DateTime committedUnlockAt,
  }) =>
      _delegate.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: wisdomText,
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );
}
