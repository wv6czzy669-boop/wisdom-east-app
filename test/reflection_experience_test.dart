import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/reflection_autosave_coordinator.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_typography_resolver.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/screens/reflection_screen.dart';
import 'package:wisdom_app/theme/east_design.dart';
import 'persistence_test_helpers.dart';

void main() {
  late KeptRepositoryTestGraph graph;
  late FavoriteItem item;
  var now = DateTime.utc(2026, 9, 1, 10);
  setUpAll(() async {
    for (final font in EastTypographyResolver.productionFonts) {
      await (FontLoader(font.family)..addFont(rootBundle.load(font.asset)))
          .load();
    }
  });
  setUp(() async {
    now = DateTime.utc(2026, 9, 1, 10);
    graph = KeptRepositoryTestGraph(clock: () => now);
    item = (await graph.repository.keepOccurrence(
            revealId: 'aaaaaaaa-0000-4000-8000-000000000001',
            wisdomText: 'Peace enters slowly.',
            revealedAt: now,
            isKeeper: true))
        .items
        .single;
  });
  Widget app(
          {Locale locale = const Locale('en'),
          Brightness brightness = Brightness.light}) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: eastTheme(locale: locale, brightness: brightness),
        home: ReflectionScreen(
            item: item,
            isKeeper: true,
            savedReflectionsService: graph.service,
            autosaveDebounce: const Duration(milliseconds: 100)),
      );
  final field = find.byKey(const ValueKey('reflection-writing-area'));
  testWidgets(
      'saved feedback follows durable writes and adding a thought preserves the first',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.enterText(field, 'My first thought.');
    expect(find.text('Saved'), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
    expect((await graph.service.load()).single.reflection, 'My first thought.');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Saved'), findsNothing);
    now = now.add(const Duration(days: 5));
    final add = find.byKey(const ValueKey('reflection-add-thought'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field).decoration!.hintText,
        'How do I read this today?');
    expect(find.text('My first thought.'), findsOneWidget);
    await tester.enterText(field, 'I understand it differently today.');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    final saved = (await graph.service.load()).single;
    expect(saved.reflection, 'My first thought.');
    expect(saved.reflectionHistory.thoughts.single.text,
        'I understand it differently today.');
    expect(saved.reflectionHistory.thoughts.single.createdAtMs,
        now.millisecondsSinceEpoch);
    await tester.pumpWidget(const SizedBox.shrink());
    item = saved;
    await tester.pumpWidget(app());
    expect(tester.widget<TextField>(field).controller!.text,
        'I understand it differently today.');
    expect(find.text('My first thought.'), findsOneWidget);
  });

  testWidgets(
      'persistent failure keeps the text and offers copy and a working retry above the keyboard',
      (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    tester.view.viewInsets = const FakeViewPadding(bottom: 580);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    graph.store.failReplace = StateError('simulated write failure');
    await tester.pumpWidget(app());
    await tester.enterText(field, 'This is still mine.');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('Saved'), findsNothing);
    final copy = find.byKey(const ValueKey('reflection-copy'));
    expect(tester.getRect(copy).bottom, lessThan(844 - 290));
    await tester.tap(copy);
    await tester.pump();
    expect(clipboard, 'This is still mine.');
    expect(find.text('Copied'), findsOneWidget);
    graph.store.failReplace = null;
    await tester.tap(find.byKey(const ValueKey('reflection-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reflection-recovery')), findsNothing);
    expect(
        (await graph.service.load()).single.reflection, 'This is still mine.');
  });

  testWidgets(
      'all locales keep dated writing and recovery usable at large text on a small screen',
      (tester) async {
    await graph.service.saveReflection(
        itemId: item.id, reflection: 'Earlier writing.', isKeeper: true);
    now = now.add(const Duration(days: 1));
    await graph.service.saveThought(
        itemId: item.id,
        thoughtId: 'bbbbbbbb-0000-4000-8000-000000000001',
        reflection: 'A later thought.',
        isKeeper: true);
    item = (await graph.service.load()).single;
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final locale in AppLocalizations.supportedLocales) {
      for (final scale in [1.0, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(app(
            locale: locale,
            brightness: scale == 1 ? Brightness.light : Brightness.dark));
        expect(tester.takeException(), isNull, reason: '$locale / $scale');
        graph.store.failReplace = StateError('simulated');
        await tester.enterText(field, 'Unsaved words in $locale / $scale.');
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump();
        expect(find.byKey(const ValueKey('reflection-copy')), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '$locale / $scale recovery');
        graph.store.failReplace = null;
      }
    }
  });

  testWidgets(
      'undated legacy writing stays undated and dated writing includes the year',
      (tester) async {
    item = item.copyWith(reflection: 'An undated original.');
    await tester.pumpWidget(app());
    expect(find.text('Earlier'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    item =
        item.copyWith(reflectedAt: DateTime.utc(2020, 1, 2).toIso8601String());
    await tester.pumpWidget(app());
    expect(find.text('Jan 2, 2020'), findsOneWidget);
  });

  testWidgets(
      'reverting a failed edit dismisses recovery without announcing a new save',
      (tester) async {
    await graph.service.saveReflection(
        itemId: item.id, reflection: 'Saved before.', isKeeper: true);
    item = (await graph.service.load()).single;
    await tester.pumpWidget(app());
    graph.store.failReplace = StateError('simulated');
    await tester.enterText(field, 'An unsuccessful change.');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.byKey(const ValueKey('reflection-recovery')), findsOneWidget);
    await tester.enterText(field, 'Saved before.');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.byKey(const ValueKey('reflection-recovery')), findsNothing);
    expect(find.text('Saved'), findsNothing);
    expect((await graph.service.load()).single.reflection, 'Saved before.');
  });

  testWidgets('an older completed write never announces a newer edit as saved',
      (tester) async {
    var text = 'first';
    final firstWrite = Completer<ReflectionPersistResult>();
    final states = <ReflectionSaveState>[];
    var calls = 0;
    final autosave = ReflectionAutosaveCoordinator(
        debounce: const Duration(milliseconds: 50),
        readText: () => text,
        persistText: (_) {
          calls++;
          return calls == 1
              ? firstWrite.future
              : Future.value(ReflectionPersistResult.saved);
        },
        onStateChanged: states.add);
    autosave.handleTextChanged();
    await tester.pump(const Duration(milliseconds: 50));
    text = 'newer';
    autosave.handleTextChanged();
    firstWrite.complete(ReflectionPersistResult.saved);
    await tester.pump();
    expect(states, isNot(contains(ReflectionSaveState.saved)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(states.last, ReflectionSaveState.saved);
    autosave.dispose();
  });
}
