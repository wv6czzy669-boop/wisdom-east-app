import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:wisdom_app/screens/keeper_screen.dart';
import 'package:wisdom_app/services/app_services.dart';
import 'package:wisdom_app/services/purchase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final removedThreeRevealCopy = [
    'Three',
    'wisdom',
    'reveals',
    'each',
    'day.',
  ].join(' ');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      purchaseService.isAvailable = false;
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    purchaseService.keeperProduct = null;
    purchaseService.isKeeper = false;
    purchaseService.isLoading = false;
    purchaseService.entitlementPersistenceFailed = false;
  });

  testWidgets('Keeper screen preserves restrained product message',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: KeeperScreen()),
    );

    const lockedCopy = [
      'Keeper',
      'Keep what stays.',
      'Enter the Circle',
      'Keep reflections without limit.',
      'Temporarily unavailable',
      'Support EAST.',
    ];

    for (final line in lockedCopy) {
      expect(find.text(line), findsOneWidget);
    }

    final renderedCopy = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toSet();
    expect(renderedCopy, lockedCopy.toSet());
  });

  testWidgets('Keeper screen renders the localized StoreKit price',
      (tester) async {
    purchaseService.isAvailable = true;
    purchaseService.keeperProduct = ProductDetails(
      id: PurchaseService.keeperProductId,
      title: 'Keeper',
      description: 'Support EAST.',
      price: 'CA\$6.99',
      rawPrice: 6.99,
      currencyCode: 'CAD',
    );

    await tester.pumpWidget(
      const MaterialApp(home: KeeperScreen()),
    );

    expect(find.text('CA\$6.99'), findsOneWidget);
    expect(find.text('One-time offering.'), findsOneWidget);
    expect(find.text('Temporarily unavailable'), findsNothing);
  });

  testWidgets('Keeper purchase action is blocked when product is unavailable',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: KeeperScreen()),
    );

    final action = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('keeper-purchase-action')),
    );
    expect(action.onTap, isNull);

    await tester.tap(find.text('Enter the Circle'));
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(purchaseService.isLoading, isFalse);
  });

  testWidgets('Keeper purchase action is blocked while a purchase is pending',
      (tester) async {
    purchaseService.isAvailable = true;
    purchaseService.keeperProduct = ProductDetails(
      id: PurchaseService.keeperProductId,
      title: 'Keeper',
      description: 'Support EAST.',
      price: '£59.99',
      rawPrice: 59.99,
      currencyCode: 'GBP',
    );
    purchaseService.isLoading = true;

    await tester.pumpWidget(
      const MaterialApp(home: KeeperScreen()),
    );

    final action = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('keeper-purchase-action')),
    );
    expect(action.onTap, isNull);
    expect(find.text('£59.99'), findsOneWidget);
  });

  testWidgets('Keeper screen remains stable on iPhone SE with large text',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(
      const MaterialApp(home: KeeperScreen()),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('Keeper'), findsOneWidget);
    expect(find.text(removedThreeRevealCopy), findsNothing);
    expect(find.text('Keep reflections without limit.'), findsOneWidget);
    expect(find.text('Support EAST.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
