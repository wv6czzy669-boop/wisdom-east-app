import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/screens/reflection_screen.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';

void main() {
  late SavedReflectionsService service;
  late FavoriteItem item;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = SavedReflectionsService();
    final result = await service.toggle(
      text: 'The associated wisdom remains visible.',
      date: 'July 23, 2026',
      isKeeper: false,
    );
    item = result.items.single;
  });

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
    await tester.tap(find.byKey(const ValueKey('keep-reflection-action')));
    await tester.pumpAndSettle();

    final persisted = await SavedReflectionsService().load();
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
      text: 'Second kept wisdom',
      date: 'July 24, 2026',
      isKeeper: true,
    );
    await service.saveReflection(
      itemId: second.items.last.id,
      reflection: 'Historical second reflection',
      isKeeper: true,
    );
    final reflected = (await service.load()).first;

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
    final failingService = SavedReflectionsService(
      preferencesAdapter: _FailingWritesAdapter(),
    );

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
    final failingService = SavedReflectionsService(
      preferencesAdapter: _FailingWritesAdapter(),
    );

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

class _FailingWritesAdapter extends StoragePreferencesAdapter {
  @override
  Future<void> setStringList(String key, List<String> value) {
    throw StateError('write failed');
  }
}
