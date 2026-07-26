import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wisdom_app/data/objects_catalog.dart';
import 'package:wisdom_app/screens/objects_screen.dart';

void main() {
  testWidgets('Objects screen has an exact, centered "Objects" title',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ObjectsScreen()),
    );

    expect(find.text('Objects'), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.centerTitle, isTrue);
  });

  testWidgets('Objects screen has no hamburger/menu control of its own',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ObjectsScreen()),
    );

    expect(
      find.byKey(const ValueKey('settings-menu-control')),
      findsNothing,
    );
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.byTooltip('Objects'), findsNothing);
    expect(find.byTooltip('Kept'), findsNothing);
  });

  testWidgets('back returns to the previous route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ObjectsScreen(),
                    ),
                  );
                },
                child: const Text('Open Objects'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Objects'));
    await tester.pumpAndSettle();
    expect(find.text('Objects'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Objects'), findsNothing);
    expect(find.text('Open Objects'), findsOneWidget);
  });

  testWidgets(
      'shows EAST. T-Shirt before EAST. Tote Bag, with no price or description',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ObjectsScreen()),
    );

    expect(find.text(ObjectsCatalog.tshirtName), findsOneWidget);
    expect(find.text(ObjectsCatalog.toteName), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(ObjectsCatalog.tshirtName)).dy,
      lessThan(tester.getTopLeft(find.text(ObjectsCatalog.toteName)).dy),
    );

    // No price, currency, description, or commerce copy of any kind.
    for (final forbidden in [
      r'$',
      '£',
      '€',
      'USD',
      'Price',
      'Add to',
      'Buy',
      'Cart',
      'Checkout',
      'In stock',
      'Out of stock',
      'Sold out',
      'Material',
      'Fit',
      'Size',
      'Shipping',
      'Espresso',
      'Khaki',
    ]) {
      expect(
        find.textContaining(forbidden),
        findsNothing,
        reason: '"$forbidden" should not appear anywhere on the Objects screen',
      );
    }
  });

  testWidgets('shows no page-indicator dots, arrows, or counters',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ObjectsScreen()),
    );

    // Exactly two galleries (T-Shirt, Tote), each a single PageView with no
    // decorative indicator widgets alongside it.
    expect(find.byType(PageView), findsNWidgets(2));
    expect(find.textContaining('of 2'), findsNothing);
    expect(find.textContaining('of 3'), findsNothing);
    expect(find.textContaining('of 4'), findsNothing);
    expect(find.byIcon(Icons.arrow_back_ios), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_ios), findsNothing);
    expect(find.byIcon(Icons.circle), findsNothing);
  });

  testWidgets(
      'exactly one DISCOVER THE OBJECTS action, targeting the approved URL',
      (tester) async {
    final calls = <_LaunchCall>[];

    await tester.pumpWidget(
      MaterialApp(
        home: ObjectsScreen(
          urlLauncher: (uri, {required mode}) async {
            calls.add(_LaunchCall(uri: uri, mode: mode));
            return true;
          },
        ),
      ),
    );

    final discoverAction =
        find.byKey(const ValueKey('objects-discover-action'));
    expect(discoverAction, findsOneWidget);

    await tester.ensureVisible(discoverAction);
    await tester.pumpAndSettle();

    await tester.tap(discoverAction);
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.uri.toString(), 'https://east.productions/objects');
    expect(calls.single.mode, LaunchMode.externalApplication);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Discover launch failure shows restrained feedback and no crash',
      (tester) async {
    final discoverAction =
        find.byKey(const ValueKey('objects-discover-action'));

    await tester.pumpWidget(
      MaterialApp(
        home: ObjectsScreen(
          urlLauncher: (uri, {required mode}) async => false,
        ),
      ),
    );

    await tester.ensureVisible(discoverAction);
    await tester.pumpAndSettle();
    await tester.tap(discoverAction);
    await tester.pump();

    expect(
      find.text('The Objects page could not be opened.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: ObjectsScreen(
          urlLauncher: (uri, {required mode}) async {
            throw StateError('blocked');
          },
        ),
      ),
    );

    await tester.ensureVisible(discoverAction);
    await tester.pumpAndSettle();
    await tester.tap(discoverAction);
    await tester.pump();

    expect(
      find.text('The Objects page could not be opened.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Objects screen does not open a new route from a product tap',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ObjectsScreen()),
    );

    await tester.tap(find.text(ObjectsCatalog.tshirtName));
    await tester.pumpAndSettle();
    expect(find.text('Objects'), findsOneWidget);
    expect(find.text(ObjectsCatalog.tshirtName), findsOneWidget);
  });
}

class _LaunchCall {
  const _LaunchCall({
    required this.uri,
    required this.mode,
  });

  final Uri uri;
  final LaunchMode mode;
}
