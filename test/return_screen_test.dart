import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/screens/return_screen.dart';

void main() {
  testWidgets('Return shows the original wisdom and original date',
      (tester) async {
    const item = FavoriteItem(
      id: 'id-1',
      revealId: 'a5f3c111-1111-4111-8111-000000000001',
      text: 'A wisdom that stayed with them.',
      date: 'July 1, 2026',
    );

    await tester.pumpWidget(const MaterialApp(home: ReturnScreen(item: item)));

    expect(find.text('Return'), findsOneWidget);
    expect(find.text('JULY 1, 2026'), findsOneWidget);
    expect(find.text('A wisdom that stayed with them.'), findsOneWidget);
  });

  testWidgets(
      'when a Reflection exists for that revealId, the correct original '
      'Reflection is shown', (tester) async {
    const item = FavoriteItem(
      id: 'id-1',
      revealId: 'a5f3c111-1111-4111-8111-000000000001',
      text: 'A wisdom that stayed with them.',
      date: 'July 1, 2026',
      reflection: 'What I wrote about it at the time.',
    );

    await tester.pumpWidget(const MaterialApp(home: ReturnScreen(item: item)));

    expect(
      find.text('What I wrote about it at the time.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'an occurrence with no Reflection renders cleanly with no empty '
      'Reflection UI, no forced prompt, and no edit controls', (tester) async {
    const item = FavoriteItem(
      id: 'id-1',
      revealId: 'a5f3c111-1111-4111-8111-000000000001',
      text: 'A wisdom with nothing written about it.',
      date: 'July 1, 2026',
    );

    await tester.pumpWidget(const MaterialApp(home: ReturnScreen(item: item)));

    expect(
      find.byKey(const ValueKey('return-original-reflection')),
      findsNothing,
    );
    // No writing surface, no prompt manufactured to fill space.
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('reflection-writing-area')), findsNothing);
  });

  testWidgets(
      'no carousel, no next/previous controls, no share feature, and no '
      'reroll affordance of any kind', (tester) async {
    const item = FavoriteItem(
      id: 'id-1',
      revealId: 'a5f3c111-1111-4111-8111-000000000001',
      text: 'A wisdom.',
      date: 'July 1, 2026',
      reflection: 'A reflection.',
    );

    await tester.pumpWidget(const MaterialApp(home: ReturnScreen(item: item)));

    expect(find.byType(PageView), findsNothing);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Previous'), findsNothing);
    expect(find.text('Share'), findsNothing);
    expect(find.byIcon(Icons.share), findsNothing);
    expect(find.text('Keep Reflection'), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets(
      'no Reflection from a different, same-text occurrence can leak into '
      'the display -- only this exact item\'s own reflection field is ever '
      'read', (tester) async {
    const item = FavoriteItem(
      id: 'id-1',
      revealId: 'a5f3c111-1111-4111-8111-000000000001',
      text: 'Shared wisdom text',
      date: 'July 1, 2026',
      // No reflection on this occurrence, even though another occurrence
      // sharing the same wisdom text might have one -- ReturnScreen never
      // sees or has access to any other item.
    );

    await tester.pumpWidget(const MaterialApp(home: ReturnScreen(item: item)));

    expect(
      find.byKey(const ValueKey('return-original-reflection')),
      findsNothing,
    );
  });

  // Visual-polish repair: the quiet pre-eligibility explanation state.
  group('explanation state (no item)', () {
    testWidgets('a null item renders exactly the minimal explanation copy',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ReturnScreen()));

      expect(find.text('Return'), findsOneWidget);
      expect(
        find.text('What you keep may return after 14 days.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'shows no occurrence content, no lock icon, no countdown/progress, '
        'no promotional or upgrade language, and no feature list',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ReturnScreen()));

      expect(find.byKey(const ValueKey('return-original-date')), findsNothing);
      expect(
          find.byKey(const ValueKey('return-original-wisdom')), findsNothing);
      expect(
        find.byKey(const ValueKey('return-original-reflection')),
        findsNothing,
      );
      expect(find.byIcon(Icons.lock), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Upgrade'), findsNothing);
      expect(find.textContaining('upgrade'), findsNothing);
      expect(find.textContaining('Notify'), findsNothing);
      expect(find.textContaining('KEEPER'), findsNothing);
      expect(find.textContaining('Keeper'), findsNothing);
    });

    testWidgets(
        'renders identically regardless of entitlement -- ReturnScreen '
        'itself takes no isKeeper parameter and never gates this state',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ReturnScreen()));
      expect(
        find.text('What you keep may return after 14 days.'),
        findsOneWidget,
      );
      expect(find.byType(TextButton), findsNothing);
    });
  });
}
