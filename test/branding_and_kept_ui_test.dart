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
    expect(find.text('Silence, before meaning.'), findsOneWidget);
    expect(
      find.text('Unlimited kept reflections and support for EAST.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('built quietly.'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('built quietly.'), findsOneWidget);
    expect(find.text('Reach Out'), findsOneWidget);
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

  testWidgets('notification visual state is disabled without interaction',
      (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('○'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Notifications disabled')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(notificationsEnabled: true),
      ),
    );

    expect(find.text('●'), findsOneWidget);
    expect(find.text('○'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Notifications enabled')),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
