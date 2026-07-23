import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';

void main() {
  late SavedReflectionsService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = SavedReflectionsService();
  });

  testWidgets('Kept shows newest first, full year, and exact states',
      (tester) async {
    final first = await _keep(
      service,
      text: 'Older wisdom',
      date: 'July 22, 2026',
    );
    final second = await _keep(
      service,
      text: 'Newer wisdom',
      date: 'July 23, 2026',
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

  testWidgets('ADD REFLECTION opens dedicated screen with associated wisdom',
      (tester) async {
    final item = await _keep(
      service,
      text: 'Wisdom to reread while writing',
      date: 'July 23, 2026',
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
    expect(find.text('What stayed with you?'), findsOneWidget);
    expect(find.text(item.text), findsOneWidget);
  });

  testWidgets('REFLECTED state opens the existing reflection for editing',
      (tester) async {
    final item = await _keep(
      service,
      text: 'Reflected wisdom',
      date: 'July 23, 2026',
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
    final item = await _keep(
      service,
      text: 'Return to kept state',
      date: 'July 23, 2026',
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
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REFLECTED'), findsNothing);
    expect(find.text('KEPT'), findsOneWidget);
    expect(find.text('ADD REFLECTION'), findsOneWidget);
    expect((await service.load()).single.hasReflection, isFalse);
  });

  testWidgets('free second reflection opens the calm Keeper experience',
      (tester) async {
    final first = await _keep(
      service,
      text: 'Already reflected',
      date: 'July 22, 2026',
    );
    final second = await _keep(
      service,
      text: 'Still kept',
      date: 'July 23, 2026',
    );
    await service.saveReflection(
      itemId: first.id,
      reflection: 'The one active reflection',
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
    expect(find.text('Unlimited Reflections'), findsOneWidget);
    expect(find.text('What stayed with you?'), findsNothing);
    expect(second.hasReflection, isFalse);
  });

  testWidgets('remove requires confirmation and Cancel preserves the item',
      (tester) async {
    final item = await _keep(
      service,
      text: 'Do not remove yet',
      date: 'July 23, 2026',
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

    expect(find.text('Remove from Kept?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text(item.text), findsOneWidget);
    expect(await service.load(), hasLength(1));
  });

  testWidgets('remove and Undo restore wisdom, reflection, and metadata',
      (tester) async {
    final item = await _keep(
      service,
      text: 'Restore every part',
      date: 'July 23, 2026',
    );
    await service.saveReflection(
      itemId: item.id,
      reflection: 'Restore this too',
      isKeeper: false,
      reflectedAt: DateTime.utc(2026, 7, 23, 12),
    );
    final original = (await service.load()).single;

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [original],
          savedReflectionsService: service,
        ),
      ),
    );

    await tester.drag(
      find.byKey(ValueKey('kept-${item.id}')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text(item.text), findsNothing);
    expect(await service.load(), isEmpty);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();

    final restored = await service.load();
    expect(restored, hasLength(1));
    expect(restored.single.encode(), original.encode());
    expect(find.text(item.text), findsOneWidget);
    expect(find.text('REFLECTED'), findsOneWidget);
    expect(find.text('Restore this too'), findsNothing);
  });

  testWidgets('failed kept removal leaves the item visible and persisted',
      (tester) async {
    final item = await _keep(
      service,
      text: 'Remain when storage fails',
      date: 'July 23, 2026',
    );
    final failingService = SavedReflectionsService(
      preferencesAdapter: _AlwaysFailingWritesAdapter(),
    );

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
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text(item.text), findsOneWidget);
    expect(
      find.text('This wisdom could not be removed. Please try again.'),
      findsOneWidget,
    );
    expect(await service.load(), hasLength(1));
  });

  testWidgets('failed Undo reports failure without duplicating state',
      (tester) async {
    final item = await _keep(
      service,
      text: 'Undo may fail safely',
      date: 'July 23, 2026',
    );
    final adapter = _FailSecondWriteAdapter();
    final failOnRestoreService =
        SavedReflectionsService(preferencesAdapter: adapter);

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: failOnRestoreService,
        ),
      ),
    );

    await tester.drag(
      find.byKey(ValueKey('kept-${item.id}')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(adapter.writes, 2);
    expect(find.text('This wisdom could not be restored.'), findsOneWidget);
    expect(find.text(item.text), findsNothing);
    expect(await service.load(), isEmpty);
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
    final item = await _keep(
      service,
      text:
          'A longer wisdom remains readable without turning the page into a card.',
      date: 'July 23, 2026',
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
}

class _AlwaysFailingWritesAdapter extends StoragePreferencesAdapter {
  @override
  Future<void> setStringList(String key, List<String> value) {
    throw StateError('write failed');
  }
}

class _FailSecondWriteAdapter extends StoragePreferencesAdapter {
  var writes = 0;

  @override
  Future<void> setStringList(String key, List<String> value) {
    writes += 1;
    if (writes == 2) {
      throw StateError('restore failed');
    }
    return super.setStringList(key, value);
  }
}

Future<FavoriteItem> _keep(
  SavedReflectionsService service, {
  required String text,
  required String date,
}) async {
  final result = await service.toggle(
    text: text,
    date: date,
    isKeeper: true,
  );
  return result.items.last;
}
