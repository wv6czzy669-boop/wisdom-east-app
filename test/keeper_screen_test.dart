import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:wisdom_app/screens/keeper_screen.dart';
import 'package:wisdom_app/services/purchase_service.dart';
import 'package:wisdom_app/theme/muted_text_color.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _StaticPurchaseService service;

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
      InAppPurchase.instance;
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    InAppPurchasePlatform.instance = _NoopInAppPurchasePlatform();
    service = _StaticPurchaseService();
  });

  tearDown(() {
    service.dispose();
  });

  testWidgets('Keeper screen preserves restrained product message',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: KeeperScreen(purchaseService: service)),
    );

    const lockedCopy = [
      'Keeper',
      'Keep what stays.',
      'Enter the Circle',
      'Keep without limit.',
      'Reflect without limit.',
      'Take your Journal with you.',
      'Keep EAST. alive.',
    ];

    for (final line in lockedCopy) {
      expect(find.text(line), findsOneWidget);
    }

    expect(find.text(removedThreeRevealCopy), findsNothing);
    expect(find.text('Temporarily unavailable'), findsNothing);
    expect(find.text('Support EAST.'), findsNothing);
    expect(find.text('One-time offering.'), findsNothing);
    expect(find.text('Keep reflections without limit.'), findsNothing);
    expect(find.text('Preserve what stays with you.'), findsNothing);
    expect(find.text('Preserve what stay with you.'), findsNothing);
    expect(find.text('Three reflections each day.'), findsNothing);

    final renderedCopy = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toSet();
    expect(renderedCopy, lockedCopy.toSet());

    expect(
      tester.widget<Text>(find.text('Keep what stays.')).style?.color,
      eastMutedTextColor,
    );
    expect(
      tester.widget<Text>(find.text('Keep EAST. alive.')).style?.color,
      eastMutedTextColor,
    );
    expect(
      tester.widget<Text>(find.text('Keep without limit.')).style?.color,
      isNot(eastMutedTextColor),
    );
    expect(
      tester.widget<Text>(find.text('Reflect without limit.')).style?.color,
      isNot(eastMutedTextColor),
    );
    expect(
      tester
          .widget<Text>(find.text('Take your Journal with you.'))
          .style
          ?.color,
      isNot(eastMutedTextColor),
    );
  });

  testWidgets(
      'Build 25 Item 1: Enter the Circle ring and the feature lines resolve '
      'to the exact same colors as Keep what stays. and KEEPER',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: KeeperScreen(purchaseService: service)),
    );

    // 1A: the ring's outline color must be exactly the same resolved color
    // as "Keep what stays." — the same `eastMutedTextColor` token, not an
    // approximated near-duplicate raw color.
    final ringContainer = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const ValueKey('keeper-purchase-action')),
        matching: find.byType(Container),
      ),
    );
    final ringDecoration = ringContainer.decoration! as BoxDecoration;
    expect(ringDecoration.border!.top.color, eastMutedTextColor);
    expect(
      ringDecoration.border!.top.color,
      tester.widget<Text>(find.text('Keep what stays.')).style!.color,
    );
    // Ring geometry/stroke width are untouched by the color change.
    expect(ringDecoration.border!.top.width, 0.7);
    final ringBox = tester.getSize(
      find.byKey(const ValueKey('keeper-purchase-action')),
    );
    expect(ringBox, const Size(238, 238));

    // 1B: the value-copy lines must resolve to the exact same color as the
    // "Keeper" heading — only color changes; font, size, and copy are
    // untouched.
    final keeperHeadingStyle = tester.widget<Text>(find.text('Keeper')).style!;
    final keptWisdomsStyle =
        tester.widget<Text>(find.text('Keep without limit.')).style!;
    final reflectionsStyle =
        tester.widget<Text>(find.text('Reflect without limit.')).style!;

    expect(keptWisdomsStyle.color, keeperHeadingStyle.color);
    expect(reflectionsStyle.color, keeperHeadingStyle.color);
    expect(keptWisdomsStyle.fontSize, 16);
    expect(reflectionsStyle.fontSize, 16);
    expect(keptWisdomsStyle.fontFamily, keeperHeadingStyle.fontFamily);

    // Secondary description colors (muted lines) are unaffected.
    expect(
      tester.widget<Text>(find.text('Keep what stays.')).style?.color,
      eastMutedTextColor,
    );
    expect(
      tester.widget<Text>(find.text('Keep EAST. alive.')).style?.color,
      eastMutedTextColor,
    );
  });

  testWidgets('Keeper keeps StoreKit price semantic but not visible',
      (tester) async {
    service = _StaticPurchaseService(
      product: ProductDetails(
        id: PurchaseService.keeperProductId,
        title: 'Keeper',
        description: 'Support EAST.',
        price: 'CA\$6.99',
        rawPrice: 6.99,
        currencyCode: 'CAD',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: KeeperScreen(purchaseService: service)),
    );

    expect(find.text('CA\$6.99'), findsNothing);
    expect(find.text('One-time offering.'), findsNothing);
    expect(find.text('Temporarily unavailable'), findsNothing);
  });

  testWidgets('Keeper purchase action is blocked when product is unavailable',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: KeeperScreen(purchaseService: service)),
    );

    final action = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('keeper-purchase-action')),
    );
    expect(action.onTap, isNull);

    await tester.tap(find.text('Enter the Circle'));
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(service.isLoading, isFalse);
  });

  testWidgets('Keeper purchase action is blocked while a purchase is pending',
      (tester) async {
    service = _StaticPurchaseService(
      loading: true,
      product: ProductDetails(
        id: PurchaseService.keeperProductId,
        title: 'Keeper',
        description: 'Support EAST.',
        price: '£59.99',
        rawPrice: 59.99,
        currencyCode: 'GBP',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: KeeperScreen(purchaseService: service)),
    );

    final action = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('keeper-purchase-action')),
    );
    expect(action.onTap, isNull);
    expect(find.text('£59.99'), findsNothing);
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
      MaterialApp(home: KeeperScreen(purchaseService: service)),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('Keeper'), findsOneWidget);
    expect(find.text(removedThreeRevealCopy), findsNothing);
    expect(find.text('Keep without limit.'), findsOneWidget);
    expect(find.text('Reflect without limit.'), findsOneWidget);
    expect(find.text('Take your Journal with you.'), findsOneWidget);
    expect(find.text('Preserve what stays with you.'), findsNothing);
    expect(find.text('Keep EAST. alive.'), findsOneWidget);
    expect(find.text('Support EAST.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Keeper purchase semantics expose action and localized price',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      service = _StaticPurchaseService(
        product: ProductDetails(
          id: PurchaseService.keeperProductId,
          title: 'Keeper',
          description: 'Support EAST.',
          price: 'CA\$6.99',
          rawPrice: 6.99,
          currencyCode: 'CAD',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: KeeperScreen(purchaseService: service)),
      );

      final purchaseNode = find.semantics
          .byLabel('Enter the Circle, CA\$6.99, one-time offering')
          .evaluate()
          .single;
      expect(
        purchaseNode.getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      expect(
        purchaseNode.getSemanticsData().flagsCollection.isEnabled,
        Tristate.isTrue,
      );
      expect(
        purchaseNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Keeper loading and unavailable states are not enabled actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      service = _StaticPurchaseService(
        loading: true,
        product: ProductDetails(
          id: PurchaseService.keeperProductId,
          title: 'Keeper',
          description: 'Support EAST.',
          price: '£59.99',
          rawPrice: 59.99,
          currencyCode: 'GBP',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: KeeperScreen(purchaseService: service)),
      );

      final loadingNode = find.semantics
          .byLabel('Enter the Circle, £59.99. Purchase in progress.')
          .evaluate()
          .single;
      expect(
        loadingNode.getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      expect(
        loadingNode.getSemanticsData().flagsCollection.isEnabled,
        Tristate.isFalse,
      );
      expect(
        loadingNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );

      service = _StaticPurchaseService();
      await tester.pumpWidget(
        MaterialApp(home: KeeperScreen(purchaseService: service)),
      );

      final unavailableNode = find.semantics
          .byLabel('Enter the Circle, temporarily unavailable')
          .evaluate()
          .single;
      expect(
        unavailableNode.getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      expect(
        unavailableNode.getSemanticsData().flagsCollection.isEnabled,
        Tristate.isFalse,
      );
      expect(
        unavailableNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Existing Keeper state has non-actionable semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      service = _StaticPurchaseService(keeper: true);

      await tester.pumpWidget(
        MaterialApp(home: KeeperScreen(purchaseService: service)),
      );

      final keeperNode =
          find.semantics.byLabel('Keeper access active').evaluate().single;
      expect(
        keeperNode.getSemanticsData().flagsCollection.isButton,
        isFalse,
      );
      expect(
        keeperNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
    } finally {
      semantics.dispose();
    }
  });
}

class _StaticPurchaseService extends PurchaseService {
  _StaticPurchaseService({
    this.loading = false,
    this.product,
    this.keeper = false,
  });

  final bool loading;
  final ProductDetails? product;
  final bool keeper;

  @override
  bool get isInitialized => false;

  @override
  bool get isAvailable => product != null;

  @override
  ProductDetails? get keeperProduct => product;

  @override
  bool get isKeeper => keeper;

  @override
  bool get isLoading => loading;

  @override
  Future<bool> buyKeeper() async => false;

  @override
  Future<bool> refreshStoreIfNeeded({bool force = false}) async =>
      product != null;
}

class _NoopInAppPurchasePlatform extends InAppPurchasePlatform {
  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      Stream<List<PurchaseDetails>>.empty();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(
      productDetails: const [],
      notFoundIDs: const [PurchaseService.keeperProductId],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) {
    return Future<bool>.value(false);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}
}
