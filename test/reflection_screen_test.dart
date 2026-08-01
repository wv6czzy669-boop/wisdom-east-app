import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/screens/reflection_screen.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';
import 'package:wisdom_app/theme/muted_text_color.dart';

import 'persistence_test_helpers.dart';

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

  SavedReflectionsService failingWritesService() {
    final store = InMemoryKeptStateStore()
      ..envelope = graph.store.envelope
      ..failReplace = StateError('write failed');
    final repository = KeptRepository(
      store: store,
      bootstrap: const KeptBootstrapResult.ready(),
      operationCoordinator: PersistenceOperationCoordinator(),
    );
    return SavedReflectionsService(keptRepository: repository);
  }

  testWidgets('Reflection screen is dedicated, quiet, and starts disabled',
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

    expect(find.text('Reflection'), findsOneWidget);
    expect(find.text(item.text), findsOneWidget);
    expect(find.text('What stayed with you?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Keep Reflection'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    final action = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Keep Reflection'),
        matching: find.byType(TextButton),
      ),
    );
    expect(action.onPressed, isNull);

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      if (text.data != null && text.data!.isNotEmpty) {
        expect(text.style?.fontFamily, 'CormorantGaramond');
      }
    }
  });

  testWidgets(
      'placeholder reads Hey. with no trace of the old copy, and typing/limit/save still work',
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

    // Reliable while the field is genuinely empty and unfocused.
    expect(find.text('Hey.'), findsOneWidget);
    expect(find.text('Write quietly.'), findsNothing);

    final field = find.byKey(const ValueKey('reflection-writing-area'));
    final decoration = tester.widget<TextField>(field).decoration;
    expect(decoration?.hintText, 'Hey.');
    expect(decoration?.hintText, isNot('Write quietly.'));
    expect(
      tester.widget<TextField>(field).maxLength,
      SavedReflectionsService.maximumReflectionLength,
    );

    await tester.enterText(field, List.filled(260, 'a').join());
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, hasLength(250));
    // The InputDecorator may keep the hint widget instantiated (unpainted)
    // once the field has text, so tree presence is not a reliable signal
    // here. The configured `hintText` on the decoration is the actual
    // source of truth for what the placeholder is, and it must still read
    // `Hey.`.
    expect(
      tester.widget<TextField>(field).decoration?.hintText,
      'Hey.',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('keep-reflection-action')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('keep-reflection-action')));
    await tester.pumpAndSettle();

    final persisted = await service.load();
    expect(persisted, hasLength(1));
    expect(persisted.single.reflection, hasLength(250));
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

  testWidgets('Keep Reflection trims and persists without duplication',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                Navigator.push<bool>(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (context) => ReflectionScreen(
                      item: item,
                      isKeeper: false,
                      savedReflectionsService: service,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      '  A private memory.  ',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('keep-reflection-action')),
    );
    await tester.pump();

    final enabledLabel = tester.widget<Text>(find.text('Keep Reflection'));
    expect(enabledLabel.style?.color, eastMutedTextColor);

    await tester.tap(find.byKey(const ValueKey('keep-reflection-action')));
    await tester.pumpAndSettle();

    final persisted = await service.load();
    expect(persisted, hasLength(1));
    expect(persisted.single.reflection, 'A private memory.');
  });

  testWidgets('existing reflection is editable for an over-limit free user',
      (tester) async {
    await service.saveReflection(
      itemId: item.id,
      reflection: 'Original',
      isKeeper: true,
    );
    final second = await service.toggle(
      revealId: 'a5f3c111-1111-4111-8111-222222222222',
      text: 'Second kept wisdom',
      date: 'July 24, 2026',
      revealedAt: DateTime.utc(2026, 7, 24),
      isKeeper: true,
    );
    await service.saveReflection(
      itemId: second.items.last.id,
      reflection: 'Historical second reflection',
      isKeeper: true,
    );
    final reflected =
        (await service.load()).singleWhere((entry) => entry.id == item.id);

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
          .controller!
          .text,
      'Original',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reflection-writing-area')),
      'Edited',
    );
    await tester.tap(find.text('Keep Reflection'));
    await tester.pump();

    final persisted = await service.load();
    expect(persisted, hasLength(2));
    expect(
      persisted.singleWhere((candidate) => candidate.id == item.id).reflection,
      'Edited',
    );
  });

  testWidgets('reflection deletion requires confirmation and keeps wisdom',
      (tester) async {
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
    expect(
      find.text('The reflection will be removed from this kept wisdom.'),
      findsOneWidget,
    );
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Private memory')),
      findsNothing,
    );

    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect((await service.load()).single.hasReflection, isTrue);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Delete'),
      ),
    );
    await tester.pumpAndSettle();

    final persisted = await service.load();
    expect(persisted, hasLength(1));
    expect(persisted.single.text, item.text);
    expect(persisted.single.hasReflection, isFalse);
  });

  testWidgets('failed save preserves typed reflection for retry',
      (tester) async {
    final failingService = failingWritesService();

    await tester.pumpWidget(
      MaterialApp(
        home: ReflectionScreen(
          item: item,
          isKeeper: false,
          savedReflectionsService: failingService,
        ),
      ),
    );

    final field = find.byKey(const ValueKey('reflection-writing-area'));
    await tester.enterText(field, 'Do not lose this.');
    await tester.ensureVisible(
      find.byKey(const ValueKey('keep-reflection-action')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('keep-reflection-action')));
    await tester.pump();

    expect(find.text('Reflection could not be kept. Please try again.'),
        findsOneWidget);
    expect(
        tester.widget<TextField>(field).controller!.text, 'Do not lose this.');
  });

  testWidgets('failed reflection deletion keeps reflected state intact',
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
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Delete'),
      ),
    );
    await tester.pump();

    expect(
      find.text('Reflection could not be deleted. Please try again.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('reflection-writing-area')),
      findsOneWidget,
    );
    expect((await service.load()).single.reflection, 'Keep this on failure');
  });
}
