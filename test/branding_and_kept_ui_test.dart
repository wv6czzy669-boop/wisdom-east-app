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
    expect(find.text('Where silence speaks.'), findsOneWidget);
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
    expect(
      tester
          .widget<Align>(
            find.byKey(const ValueKey('settings-content')),
          )
          .alignment,
      Alignment.topCenter,
    );
    expect(tester.getTopLeft(find.text('EAST.')).dy, lessThan(120));
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('settings-scroll')),
          )
          .physics,
      isA<ClampingScrollPhysics>(),
    );
    final keeperCircle = find.byKey(
      const ValueKey('keeper-circle-symbol'),
    );
    expect(keeperCircle, findsOneWidget);
    expect(tester.widget(keeperCircle), isA<CustomPaint>());
    expect(tester.getSize(keeperCircle), const Size.square(22));
    expect(find.text('○'), findsNothing);
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

  testWidgets('Settings scroll protects iPhone SE at 3x text scale',
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

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Keeper'), findsOneWidget);
    expect(find.text('Reach Out'), findsOneWidget);

    await tester.ensureVisible(find.text('Reach Out'));
    await tester.pump();

    expect(
      tester.getCenter(find.text('Reach Out')).dy,
      lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio),
    );
    expect(tester.takeException(), isNull);
  });
}
