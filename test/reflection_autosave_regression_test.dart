// Reflection autosave root-cause regression suite.
//
// This exercises the REAL production navigation flow -- Kept
// (`SavedReflectionsScreen`) -> tap "ADD REFLECTION"/"REFLECTED" -> real
// `Navigator.push` -> `ReflectionScreen` -> type -> immediately trigger
// back -- through the REAL `SavedReflectionsService` /
// `KeptSyncIntegrationCoordinator` / `KeptRepository` /
// `PersistenceOperationCoordinator` chain. The only thing ever faked is the
// storage boundary itself ([KeptStateStore]), and only to simulate real
// device conditions (write latency, a genuinely failing write) that the
// existing purely-synchronous [InMemoryKeptStateStore] cannot reproduce --
// never to shortcut past the layer where the real bug lives.
//
// Timing note: `flutter test` runs every `testWidgets` body inside a
// `FakeAsync` zone (see `AutomatedTestWidgetsFlutterBinding`), so a real
// `Future.delayed`/`Timer` -- including the artificial store latency below,
// and `ReflectionScreen`'s own debounce/retry timers -- only ever resolves
// once the test explicitly elapses fake time via `tester.pump(duration)`.
// Any such delayed operation triggered *before* the first `pumpWidget`
// call (e.g. inside test setup) can never resolve at all. Seeding is
// therefore always done through a store with no artificial delay.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';
import 'package:wisdom_app/persistence/kept_state_store.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/screens/reflection_screen.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';
import 'package:wisdom_app/sync_integration/kept_sync_integration_coordinator.dart';

import 'persistence_test_helpers.dart' show InMemoryKeptStateStore;
import 'sync_integration/in_memory_sync_test_doubles.dart';

/// Wraps a real [KeptStateStore] and adds artificial async latency to both
/// operations -- simulating genuine on-device file I/O (temp write +
/// protect + verify + atomic rename + re-verify, each a real `await`),
/// which the existing in-memory test double resolves in effectively zero
/// time. Correctness must not depend on how fast the store happens to be.
class _DelayedKeptStateStore implements KeptStateStore {
  _DelayedKeptStateStore(this._inner);

  static const Duration _loadDelay = Duration(milliseconds: 30);
  static const Duration _replaceDelay = Duration(milliseconds: 90);

  final KeptStateStore _inner;

  @override
  Future<KeptStateEnvelope?> load() async {
    await Future<void>.delayed(_loadDelay);
    return _inner.load();
  }

  @override
  Future<void> replace(KeptStateEnvelope envelope) async {
    await Future<void>.delayed(_replaceDelay);
    return _inner.replace(envelope);
  }
}

/// Simulates a genuinely PERSISTENT local-write failure (every `replace()`
/// call fails while [failing] is `true`, not just the next one) -- the
/// real-device condition this suite's core failing case targets: a real
/// iOS file-protection/disk hiccup that does not resolve itself within the
/// retry window (see `ReflectionScreen._attemptPersist`'s own retry
/// budget). Starts non-failing so setup/seeding writes succeed normally;
/// each test flips [failing] on only once its own seed data is in place.
class _ToggleFailReplaceStore implements KeptStateStore {
  _ToggleFailReplaceStore(this._inner);

  final KeptStateStore _inner;
  bool failing = false;

  @override
  Future<KeptStateEnvelope?> load() => _inner.load();

  @override
  Future<void> replace(KeptStateEnvelope envelope) async {
    if (failing) {
      throw const _SimulatedPersistentWriteFailure();
    }
    return _inner.replace(envelope);
  }
}

class _SimulatedPersistentWriteFailure implements Exception {
  const _SimulatedPersistentWriteFailure();

  @override
  String toString() => 'Simulated persistent local-write failure';
}

/// Fails the next [failuresRemaining] `replace()` calls, then succeeds --
/// simulating a genuinely TRANSIENT real-device write hiccup that resolves
/// itself within `ReflectionScreen`'s own retry budget
/// ([ReflectionScreen]'s `_maxPersistAttempts` is 3), distinct from
/// [_ToggleFailReplaceStore]'s permanent failure above.
class _FailNTimesThenSucceedStore implements KeptStateStore {
  _FailNTimesThenSucceedStore(this._inner, {required this.failuresRemaining});

  final KeptStateStore _inner;
  int failuresRemaining;

  @override
  Future<KeptStateEnvelope?> load() => _inner.load();

  @override
  Future<void> replace(KeptStateEnvelope envelope) async {
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const _SimulatedPersistentWriteFailure();
    }
    return _inner.replace(envelope);
  }
}

/// A `replace()` whose completion is entirely under the TEST's manual
/// control -- it does not resolve on its own via any timer or delay, real
/// or fake. The test decides the exact instant the write becomes durable
/// by calling [releaseNextWrite]. This is the only way to deterministically
/// put a write "in flight, genuinely unresolved" at a precise point in a
/// scripted interaction (typing, waiting past the debounce, THEN tapping
/// back while that write is still pending) -- an artificial fixed delay
/// cannot guarantee the write is still unresolved at the exact moment the
/// test taps back.
class _GatedKeptStateStore implements KeptStateStore {
  _GatedKeptStateStore(this._inner);

  final KeptStateStore _inner;
  Completer<void>? _gate;

  /// Call before the write you want to gate is triggered.
  void armGate() {
    _gate = Completer<void>();
  }

  /// Lets the currently gated write (if any) actually reach the inner
  /// store now.
  void releaseNextWrite() {
    _gate?.complete();
  }

  @override
  Future<KeptStateEnvelope?> load() => _inner.load();

  @override
  Future<void> replace(KeptStateEnvelope envelope) async {
    // Deliberately does NOT clear `_gate` here: `releaseNextWrite` must
    // still be able to find and complete the exact same `Completer` this
    // call is awaiting, whenever the test calls it -- clearing the field
    // as soon as `replace()` is entered would make `releaseNextWrite` a
    // silent no-op for any release requested after that point.
    final gate = _gate;
    if (gate != null) {
      await gate.future;
    }
    return _inner.replace(envelope);
  }
}

/// Mirrors `test/persistence_test_helpers.dart`'s `KeptRepositoryTestGraph`
/// wiring exactly (real `KeptRepository`, real
/// `KeptSyncIntegrationCoordinator`, real `SavedReflectionsService`) but
/// lets the underlying [KeptStateStore] be swapped, so each test can choose
/// exactly which boundary condition it is proving.
class _Graph {
  _Graph({KeptStateStore? store, DateTime Function()? clock})
      : store = store ?? InMemoryKeptStateStore() {
    repository = KeptRepository(
      store: this.store,
      bootstrap: const KeptBootstrapResult.ready(),
      operationCoordinator: PersistenceOperationCoordinator(),
      clock: clock,
    );
    intentStore = InMemoryLocalSyncIntentStore();
    syncPersistenceStore = InMemorySyncPersistenceStore();
    syncCoordinator = KeptSyncIntegrationCoordinator(
      keptRepository: repository,
      intentStore: intentStore,
      syncPersistenceStore: syncPersistenceStore,
      clock: clock,
    );
    service = SavedReflectionsService(
      keptRepository: repository,
      syncCoordinator: syncCoordinator,
    );
  }

  final KeptStateStore store;
  late final KeptRepository repository;
  late final InMemoryLocalSyncIntentStore intentStore;
  late final InMemorySyncPersistenceStore syncPersistenceStore;
  late final KeptSyncIntegrationCoordinator syncCoordinator;
  late final SavedReflectionsService service;
}

Future<FavoriteItem> _keepItem(
  SavedReflectionsService service, {
  required String text,
  required DateTime date,
  String? revealId,
}) async {
  final result = await service.toggle(
    revealId: revealId ?? 'a5f3c111-1111-4111-8111-000000000001',
    text: text,
    date: 'display date',
    revealedAt: date,
    isKeeper: true,
  );
  return result.items.single;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'CASE A -- NORMAL AUTOSAVE WITHOUT LEAVING: type, wait well past the '
      'debounce, do NOT pop -- the authoritative repository must already '
      'contain the exact reflection text', (tester) async {
    final graph = _Graph();
    final item = await _keepItem(
      graph.service,
      text: 'A wisdom to reflect on without ever leaving the screen',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: graph.service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      'It doesnt work.',
    );

    // Wait well past the 600ms debounce -- over 2 real/fake seconds, never
    // popping, never tapping back, never leaving the screen in any way.
    await tester.pump(const Duration(seconds: 2, milliseconds: 200));

    // Still on Reflection the whole time.
    expect(find.byType(ReflectionScreen), findsOneWidget);
    expect(find.byType(SavedReflectionsScreen), findsNothing);

    // Directly inspect the AUTHORITATIVE repository/service state -- not
    // the widget's own controller/UI -- while still mounted.
    final authoritative = await graph.service.load();
    expect(
      authoritative,
      hasLength(1),
      reason: 'Exactly one record for this revealId -- no duplicate.',
    );
    expect(
      authoritative.single.reflection,
      'It doesnt work.',
      reason: 'Ordinary debounce autosave must have already committed the '
          'exact text to authoritative storage without any navigation at '
          'all.',
    );
    expect(authoritative.single.id, item.id);
  });

  testWidgets(
      'CASE B -- VIDEO TIMELINE: type, wait ~2 seconds (well past the '
      'debounce), THEN back -- Kept must show Reflected, and reopening '
      'must show the exact text', (tester) async {
    final graph = _Graph();
    final item = await _keepItem(
      graph.service,
      text: 'A wisdom matching the real-device video timeline',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: graph.service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      'It doesnt work.',
    );

    // Matches the video's Attempt 1: typing finishes, then the user simply
    // remains on the screen for ~2 seconds -- long past the 600ms
    // debounce -- before ever tapping back.
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const ValueKey('east-back-button')));
    await tester.pumpAndSettle();

    expect(find.byType(SavedReflectionsScreen), findsOneWidget);
    expect(
      find.text('REFLECTED'),
      findsOneWidget,
      reason: 'Kept must show Reflected immediately after returning.',
    );
    expect(find.text('ADD REFLECTION'), findsNothing);

    await tester.tap(find.text('REFLECTED'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('reflection-writing-area')),
    );
    expect(field.controller!.text, 'It doesnt work.');

    final authoritative = await graph.service.load();
    expect(authoritative, hasLength(1));
    expect(authoritative.single.reflection, 'It doesnt work.');
  });

  testWidgets(
      'CORE FAILURE MODE: a genuinely persistent local-write failure must '
      'not let the pop proceed and silently discard the typed text -- the '
      'user must remain on Reflection with the text intact', (tester) async {
    final backing = InMemoryKeptStateStore();
    final toggle = _ToggleFailReplaceStore(backing);
    final graph = _Graph(store: toggle);
    // Seed while the store is still healthy -- only the reflection save
    // itself is meant to fail.
    final item = await _keepItem(
      graph.service,
      text: 'A wisdom whose reflection cannot be saved right now',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: graph.service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      'This must not vanish.',
    );

    // Now make every local write fail, exactly as a real, persistent
    // on-device disk/file-protection failure would while the user is
    // leaving the screen.
    toggle.failing = true;

    // Immediately back out -- well before the 600ms debounce would ever
    // fire on its own.
    await tester.tap(find.byKey(const ValueKey('east-back-button')));
    // Elapse enough fake time for the flush's full retry budget (3
    // attempts, 120ms apart) to genuinely exhaust.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // The write is genuinely, persistently failing -- the screen must NOT
    // have popped, and the typed text must still be right there in the
    // field, recoverable.
    expect(
      find.byType(ReflectionScreen),
      findsOneWidget,
      reason: 'A persistently failing local write must keep the user on '
          'Reflection rather than silently popping and losing the text.',
    );
    expect(find.byType(SavedReflectionsScreen), findsNothing);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('reflection-writing-area')),
    );
    expect(field.controller!.text, 'This must not vanish.');
  });

  testWidgets(
      'CORE: type text, immediately tap back before the debounce fires -- '
      'Kept immediately shows Reflected, and reopening shows the exact '
      'text', (tester) async {
    final graph = _Graph();
    final item = await _keepItem(
      graph.service,
      text: 'A wisdom worth reflecting on',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: graph.service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      'Typed and left immediately.',
    );
    await tester.tap(find.byKey(const ValueKey('east-back-button')));
    await tester.pumpAndSettle();

    expect(find.byType(SavedReflectionsScreen), findsOneWidget);
    expect(find.text('REFLECTED'), findsOneWidget);
    expect(find.text('ADD REFLECTION'), findsNothing);

    await tester.tap(find.text('REFLECTED'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('reflection-writing-area')),
    );
    expect(field.controller!.text, 'Typed and left immediately.');

    // Persisted state survives a fresh service/repository reload (simulated
    // relaunch): a brand-new repository/service pointed at the exact same
    // durable store must see the exact same text -- and only one record.
    final freshGraph = _Graph(store: graph.store);
    final reloaded = await freshGraph.service.load();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.reflection, 'Typed and left immediately.');
  });

  testWidgets(
      'SLOW STORE (simulated real disk latency): immediate back genuinely '
      'waits on the durable local commit -- the screen does not pop until '
      'the write lands, and the exact text survives', (tester) async {
    // Seed through an undelayed graph first (no pumpWidget has happened
    // yet, so there is no way to elapse fake time for a delayed write) --
    // then hand the SAME backing store to a delayed-wrapped graph for the
    // actual widget interaction below.
    final backing = InMemoryKeptStateStore();
    final seedGraph = _Graph(store: backing);
    final item = await _keepItem(
      seedGraph.service,
      text: 'Slow-store wisdom',
      date: DateTime.utc(2026, 7, 23),
    );

    final slow = _DelayedKeptStateStore(backing);
    final graph = _Graph(store: slow);

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: graph.service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      'Slow write should still land.',
    );
    await tester.tap(find.byKey(const ValueKey('east-back-button')));

    // Elapse a small amount of fake time -- well under the store's 90ms
    // replace latency -- to prove the screen does NOT pop before the write
    // has actually landed.
    await tester.pump(const Duration(milliseconds: 15));
    expect(
      find.byType(ReflectionScreen),
      findsOneWidget,
      reason: 'Must still be on Reflection while the flush is in flight.',
    );

    // Now elapse comfortably past the store's latency so the write (and
    // the resulting pop/navigation) can actually complete.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.byType(SavedReflectionsScreen), findsOneWidget);
    expect(find.text('REFLECTED'), findsOneWidget);

    final reloaded = await backing.load();
    expect(reloaded!.activeRecords.single.reflectionText,
        'Slow write should still land.');
  });

  testWidgets(
      'TRANSIENT FAILURE: the first local write fails, the retry inside '
      'the same flush succeeds -- the route pops only after that '
      'successful commit, and no duplicate record is ever created',
      (tester) async {
    final backing = InMemoryKeptStateStore();
    // Seed while healthy.
    final seedGraph = _Graph(store: backing);
    final item = await _keepItem(
      seedGraph.service,
      text: 'Wisdom whose first reflection write hiccups once',
      date: DateTime.utc(2026, 7, 23),
    );

    // Exactly one failure -- resolves itself on the flush's own retry
    // (`ReflectionScreen._maxPersistAttempts` is 3), well before the
    // retries would exhaust.
    final flaky = _FailNTimesThenSucceedStore(backing, failuresRemaining: 1);
    final graph = _Graph(store: flaky);

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: graph.service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      'Typed right before a flaky first attempt.',
    );
    await tester.tap(find.byKey(const ValueKey('east-back-button')));

    // Still mid-retry immediately after the tap -- the first attempt has
    // already failed, but the retry delay (120ms) has not yet elapsed, so
    // the route must not have popped yet.
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      find.byType(ReflectionScreen),
      findsOneWidget,
      reason: 'Must still be on Reflection between the failed first '
          'attempt and the successful retry.',
    );

    // Elapse comfortably past the retry delay so the second (successful)
    // attempt can complete and the pop can proceed.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byType(SavedReflectionsScreen), findsOneWidget);
    expect(find.text('REFLECTED'), findsOneWidget);
    expect(find.textContaining('could not be saved'), findsNothing);

    final reloaded = await backing.load();
    expect(reloaded!.activeRecords, hasLength(1));
    expect(
      reloaded.activeRecords.single.reflectionText,
      'Typed right before a flaky first attempt.',
    );
    expect(reloaded.activeRecords.single.id, item.id);
  });

  testWidgets(
      'rapid back while the keyboard is still open (no unfocus) loses '
      'nothing', (tester) async {
    final graph = _Graph();
    final item = await _keepItem(
      graph.service,
      text: 'Keyboard-open wisdom',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: graph.service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      'Written with the keyboard still up.',
    );
    expect(
      FocusManager.instance.primaryFocus?.hasFocus,
      isTrue,
      reason: 'The writing area still has focus -- the keyboard is up.',
    );
    await tester.tap(find.byKey(const ValueKey('east-back-button')));
    await tester.pumpAndSettle();

    expect(find.text('REFLECTED'), findsOneWidget);
    final reloaded = await graph.store.load();
    expect(reloaded!.activeRecords.single.reflectionText,
        'Written with the keyboard still up.');
  });

  testWidgets(
      'editing an existing Reflection then immediately backing out '
      'persists the NEW text, not the old one, and creates no duplicate',
      (tester) async {
    final graph = _Graph();
    final item = await _keepItem(
      graph.service,
      text: 'Wisdom with an existing reflection',
      date: DateTime.utc(2026, 7, 23),
    );
    await graph.service.saveReflection(
      itemId: item.id,
      reflection: 'The original reflection.',
      isKeeper: true,
    );
    final reflected = (await graph.service.load()).single;

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [reflected],
          savedReflectionsService: graph.service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('REFLECTED'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      'The edited reflection, typed just before leaving.',
    );
    await tester.tap(find.byKey(const ValueKey('east-back-button')));
    await tester.pumpAndSettle();

    expect(find.text('REFLECTED'), findsOneWidget);

    final reloaded = await graph.service.load();
    expect(reloaded, hasLength(1));
    expect(
      reloaded.single.reflection,
      'The edited reflection, typed just before leaving.',
    );
    expect(reloaded.single.id, item.id);
  });

  testWidgets(
      'CASE D -- IN-FLIGHT SAVE AT BACK (critical): the debounce fires and '
      'a real local write is genuinely UNRESOLVED (deliberately held open) '
      'at the exact moment the user taps back -- the route must stay open '
      'and only pop once that in-flight write is authoritatively '
      'committed, never merely because no new dirty text exists',
      (tester) async {
    final backing = InMemoryKeptStateStore();
    final seedGraph = _Graph(store: backing);
    final item = await _keepItem(
      seedGraph.service,
      text: 'A wisdom whose autosave write is deliberately held open',
      date: DateTime.utc(2026, 7, 23),
    );

    final gated = _GatedKeptStateStore(backing);
    final graph = _Graph(store: gated);

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: graph.service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    // Arm the gate BEFORE typing, so the very write the debounce is about
    // to trigger is the one held open.
    gated.armGate();
    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      'Typed, then the write itself hangs open.',
    );

    // Elapse past the 600ms debounce -- the ordinary (non-flush,
    // non-retrying) autosave now starts and calls the gated store's
    // replace(), which does not resolve until the test explicitly
    // releases it. `_inFlightPersist` is non-null for the whole time this
    // pump is executing.
    await tester.pump(const Duration(milliseconds: 650));

    // The write is genuinely in flight -- confirm no premature success/
    // completion happened, and the write has not landed yet.
    final midFlightRead = await backing.load();
    expect(
      midFlightRead!.activeRecords.single.reflectionText,
      isNull,
      reason: 'The gated write has not been released yet -- it must not '
          'have reached the underlying store.',
    );

    // Now tap back WHILE that write is still unresolved. This must join
    // (not ignore) the exact in-flight Future -- never report "flushed"
    // merely because `_controller.text` already equals the text that
    // write is FOR (i.e. "nothing new to persist" must not be conflated
    // with "the in-flight write for that exact text has landed").
    await tester.tap(find.byKey(const ValueKey('east-back-button')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byType(ReflectionScreen),
      findsOneWidget,
      reason: 'Must still be on Reflection -- the write this back attempt '
          'depends on has not committed yet.',
    );
    expect(find.byType(SavedReflectionsScreen), findsNothing);

    // Only now let the held-open write actually land.
    gated.releaseNextWrite();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(
      find.byType(SavedReflectionsScreen),
      findsOneWidget,
      reason: 'Pops only once the in-flight write is authoritatively '
          'committed.',
    );
    expect(find.text('REFLECTED'), findsOneWidget);

    final authoritative = await backing.load();
    expect(authoritative!.activeRecords, hasLength(1));
    expect(
      authoritative.activeRecords.single.reflectionText,
      'Typed, then the write itself hangs open.',
    );
    expect(authoritative.activeRecords.single.id, item.id);
  });

  testWidgets(
      'FALSE SUCCESS ROOT CAUSE: an early no-op persist pass (debounce '
      'firing while the field is genuinely empty, e.g. type-then-delete) '
      'must never permanently poison in-flight persistence for the rest '
      'of the screen\'s lifetime -- later real, multi-revision edits must '
      'still be genuinely, durably persisted before the route is allowed '
      'to pop', (tester) async {
    final graph = _Graph();
    final item = await _keepItem(
      graph.service,
      text: 'A wisdom whose reflection field starts, and briefly returns '
          'to, empty',
      date: DateTime.utc(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: graph.service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ADD REFLECTION'));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('reflection-writing-area'));

    // The exact poisoning trigger: a real keystroke, then a real delete,
    // then enough pause for the debounce to fire while `_controller.text`
    // is genuinely empty again -- an entirely ordinary, plausible
    // real-device interaction (also reachable via an app-lifecycle blip
    // mid-typing; the underlying code defect is identical either way).
    await tester.enterText(field, 'a');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, '');
    // Past the 600ms debounce -- this fires as a genuine no-op (nothing to
    // persist), which is the exact call whose drain loop used to leave
    // `_inFlightPersist` permanently non-null afterward.
    await tester.pump(const Duration(milliseconds: 700));

    // Now the user actually writes a reflection, across several rapid,
    // overlapping revisions -- exactly like real continuous typing, each
    // one arriving before the previous revision's own debounce would have
    // fired.
    await tester.enterText(field, 'I');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'It');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'It doesnt');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'It doesnt work.');

    // Immediately back -- well before the 600ms debounce would fire on its
    // own for this final revision, exactly matching the real-device
    // repro's "immediate-ish back" timing.
    await tester.tap(find.byKey(const ValueKey('east-back-button')));
    await tester.pumpAndSettle();

    expect(find.byType(SavedReflectionsScreen), findsOneWidget);
    expect(
      find.text('REFLECTED'),
      findsOneWidget,
      reason: 'An earlier no-op persist pass must never leave later real '
          'edits silently unpersisted.',
    );
    expect(find.text('ADD REFLECTION'), findsNothing);

    final authoritative = await graph.service.load();
    expect(authoritative, hasLength(1));
    expect(
      authoritative.single.reflection,
      'It doesnt work.',
      reason: 'The exact final text must be durably committed, not merely '
          'reported as already-persisted by a stale completed Future.',
    );
  });
}
