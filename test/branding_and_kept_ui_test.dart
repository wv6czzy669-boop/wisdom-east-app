import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/app.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/screens/settings_screen.dart';

void main() {
  testWidgets('application and settings use EAST. branding', (tester) async {
    await tester.pumpWidget(const WisdomApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Daily Wisdom: EAST.');

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 550));

    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );

    expect(find.text('EAST.'), findsOneWidget);
    expect(
      find.text('Support the circle, keep what stays.'),
      findsOneWidget,
    );
    expect(
      find.text('Restore what belongs with you.'),
      findsOneWidget,
    );
    expect(find.text('What stays private.'), findsOneWidget);
    expect(find.text('For thoughts and questions.'), findsOneWidget);
    expect(find.text('Reach Out'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(Scrollable), findsNothing);
    expect(find.text('○'), findsOneWidget);
  });

  testWidgets('Kept omits the stored year without changing its data',
      (tester) async {
    const storedDate = 'June 21, 2026';
    final reflection = FavoriteItem(
      text: 'A quiet reflection.',
      date: storedDate,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [reflection],
        ),
      ),
    );

    expect(find.text('June 21'), findsOneWidget);
    expect(find.text(storedDate), findsNothing);
    final displayedDate = tester.widget<Text>(find.text('June 21'));
    expect(displayedDate.style?.color, const Color(0x91FFFFFF));
    expect(reflection.date, storedDate);
  });

  testWidgets('Kept screen uses the new feature title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SavedReflectionsScreen(reflections: []),
      ),
    );

    expect(find.text('Kept'), findsOneWidget);
    expect(find.text('Nothing kept yet.'), findsOneWidget);
  });

  testWidgets('Settings remains fixed on iPhone SE at 3x text scale',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );

    expect(find.byType(Scrollable), findsNothing);
    expect(find.text('Keeper'), findsOneWidget);
    expect(find.text('Reach Out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
