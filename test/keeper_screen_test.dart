import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/screens/keeper_screen.dart';
import 'package:wisdom_app/services/purchase_service.dart';
import 'package:wisdom_app/theme/east_design.dart';
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
      'The ritual, within your widget.',
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

    final mutedColor =
        eastMutedTextColor(tester.element(find.text('Keep what stays.')));
    expect(
      tester.widget<Text>(find.text('Keep what stays.')).style?.color,
      mutedColor,
    );
    expect(
      tester.widget<Text>(find.text('Keep EAST. alive.')).style?.color,
      mutedColor,
    );
    expect(
      tester.widget<Text>(find.text('Keep without limit.')).style?.color,
      isNot(mutedColor),
    );
    expect(
      tester.widget<Text>(find.text('Reflect without limit.')).style?.color,
      isNot(mutedColor),
    );
    expect(
      tester
          .widget<Text>(find.text('Take your Journal with you.'))
          .style
          ?.color,
      isNot(mutedColor),
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
    final mutedColor =
        eastMutedTextColor(tester.element(find.text('Keep what stays.')));
    expect(ringDecoration.border!.top.color, mutedColor);
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
      mutedColor,
    );
    expect(
      tester.widget<Text>(find.text('Keep EAST. alive.')).style?.color,
      mutedColor,
    );
  });

  testWidgets('Keeper shows the exact StoreKit price and purchase type',
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

    expect(find.text('CA\$6.99'), findsOneWidget);
    expect(find.text('One-time purchase'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('keeper-localized-price')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('keeper-one-time-purchase')),
      findsOneWidget,
    );
    expect(find.text('Temporarily unavailable'), findsNothing);
  });

  testWidgets('new Keeper value copy renders in all 15 product locales',
      (tester) async {
    service = _StaticPurchaseService(
      product: ProductDetails(
        id: PurchaseService.keeperProductId,
        title: 'Keeper',
        description: 'Support EAST.',
        price: r'$2.99',
        rawPrice: 2.99,
        currencyCode: 'USD',
      ),
    );

    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: eastTheme(locale: locale),
          home: KeeperScreen(purchaseService: service),
        ),
      );
      await tester.pump();

      expect(find.text(l10n.enterTheCircle), findsOneWidget, reason: '$locale');
      expect(find.text(l10n.oneTimePurchase), findsOneWidget,
          reason: '$locale');
      expect(find.text(l10n.keeperWidgetRitual), findsOneWidget,
          reason: '$locale');
      expect(find.text(r'$2.99'), findsOneWidget, reason: '$locale');
      expect(tester.takeException(), isNull, reason: '$locale');
    }
  });

  testWidgets('Keeper purchase and active states render in Light and Dark',
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

    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: eastTheme(brightness: brightness),
          home: KeeperScreen(purchaseService: service),
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(KeeperScreen));
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        EastColors.of(context).background,
      );
      expect(find.text('CA\$6.99'), findsOneWidget);
      expect(find.text('One-time purchase'), findsOneWidget);

      service.update(keeper: true);
      await tester.pump();
      expect(find.text('Within the Circle'), findsOneWidget);
      expect(find.text('Keeper active'), findsOneWidget);

      service.update(keeper: false);
    }
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
    expect(find.text('£59.99'), findsOneWidget);
    expect(find.text('One-time purchase'), findsOneWidget);
  });

  testWidgets('purchase failure guidance follows the active locale',
      (tester) async {
    service = _StaticPurchaseService(
      product: ProductDetails(
        id: PurchaseService.keeperProductId,
        title: 'Keeper',
        description: 'Support EAST.',
        price: r'$4.99',
        rawPrice: 4.99,
        currencyCode: 'USD',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: KeeperScreen(purchaseService: service),
      ),
    );

    await tester.tap(find.text('Çembere katıl.'));
    await tester.pump();

    expect(
      find.text(
          'Satın alma henüz hazır değil. Lütfen kısa süre sonra yeniden dene.'),
      findsOneWidget,
    );
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

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Keeper'), findsOneWidget);
    expect(find.text(removedThreeRevealCopy), findsNothing);
    expect(find.text('Keep without limit.'), findsOneWidget);
    expect(find.text('Reflect without limit.'), findsOneWidget);
    expect(find.text('Take your Journal with you.'), findsOneWidget);
    expect(find.text('The ritual, within your widget.'), findsOneWidget);
    expect(find.text('Preserve what stays with you.'), findsNothing);
    expect(find.text('Keep EAST. alive.'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('keeper-scroll-view')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byKey(const ValueKey('keeper-scroll-view')),
      const Offset(0, -300),
    );
    await tester.pump();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(find.text('Support EAST.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Keeper stays usable at 100/135/160/200% text scale '
      '(Build 33 accessibility repair)', (tester) async {
    for (final scale in [1.0, 1.35, 1.6, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(home: KeeperScreen(purchaseService: service)),
      );
      await tester.pump();

      expect(find.text('Keeper'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('keeper-purchase-action')),
        findsOneWidget,
        reason: 'the purchase action must remain reachable at ${scale}x.',
      );
      expect(tester.takeException(), isNull, reason: '${scale}x');
    }
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
          .byLabel('Enter the Circle, CA\$6.99, one-time purchase')
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
      expect(find.text('Within the Circle'), findsOneWidget);
      expect(find.text('Keeper active'), findsOneWidget);
      expect(find.text('Add the Keeper Widget'), findsOneWidget);
      expect(
        find.text('On iOS 15 and 16, the widget opens EAST.'),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('keeper-purchase-action'))),
        const Size(168, 168),
      );
      expect(
        find.byKey(const ValueKey('keeper-active-status')),
        findsOneWidget,
      );
      expect(find.text('Enter the Circle'), findsNothing);
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

  testWidgets('active Keeper explains the interactive iOS 17 widget',
      (tester) async {
    service = _StaticPurchaseService(keeper: true);

    await tester.pumpWidget(
      MaterialApp(
        home: KeeperScreen(
          purchaseService: service,
          supportsInteractiveKeeperWidget: true,
        ),
      ),
    );

    expect(find.text('Add the Keeper Widget'), findsOneWidget);
    expect(
      find.text('On iOS 17 or later, begin the ritual in the widget.'),
      findsOneWidget,
    );
    expect(find.text('Keep without limit.'), findsNothing);
    expect(find.text('Take your Journal with you.'), findsNothing);
  });

  testWidgets(
      'verified purchase and restore updates enter the active Keeper state',
      (tester) async {
    service = _StaticPurchaseService(
      product: ProductDetails(
        id: PurchaseService.keeperProductId,
        title: 'Keeper',
        description: 'Support EAST.',
        price: r'$2.99',
        rawPrice: 2.99,
        currencyCode: 'USD',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: KeeperScreen(purchaseService: service)),
    );

    expect(find.text('Enter the Circle'), findsOneWidget);
    expect(find.text(r'$2.99'), findsOneWidget);

    // A verified purchase stream update and a verified restore both reach
    // the screen through the same authoritative isKeeper state.
    service.update(keeper: true);
    await tester.pump();

    expect(find.text('Within the Circle'), findsOneWidget);
    expect(find.text('Keeper active'), findsOneWidget);
    expect(find.text(r'$2.99'), findsNothing);

    service.update(keeper: false);
    await tester.pump();
    expect(find.text('Enter the Circle'), findsOneWidget);

    service.update(keeper: true);
    await tester.pump();
    expect(find.text('Within the Circle'), findsOneWidget);
    expect(find.text('Keeper active'), findsOneWidget);
  });

  testWidgets('pending blocks taps and cancel restores the purchase action',
      (tester) async {
    service = _StaticPurchaseService(
      loading: true,
      product: ProductDetails(
        id: PurchaseService.keeperProductId,
        title: 'Keeper',
        description: 'Support EAST.',
        price: '€3.49',
        rawPrice: 3.49,
        currencyCode: 'EUR',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: KeeperScreen(purchaseService: service)),
    );

    expect(
      tester
          .widget<GestureDetector>(
            find.byKey(const ValueKey('keeper-purchase-action')),
          )
          .onTap,
      isNull,
    );
    expect(find.text('€3.49'), findsOneWidget);

    // StoreKit cancellation is non-entitling and clears the pending guard.
    service.update(loading: false, keeper: false);
    await tester.pump();

    expect(
      tester
          .widget<GestureDetector>(
            find.byKey(const ValueKey('keeper-purchase-action')),
          )
          .onTap,
      isNotNull,
    );
    expect(find.text('Enter the Circle'), findsOneWidget);
    expect(find.text('Keeper active'), findsNothing);
  });
}

class _StaticPurchaseService extends PurchaseService {
  _StaticPurchaseService({
    this.loading = false,
    this.product,
    this.keeper = false,
  });

  bool loading;
  final ProductDetails? product;
  bool keeper;

  void update({bool? loading, bool? keeper}) {
    if (loading != null) this.loading = loading;
    if (keeper != null) this.keeper = keeper;
    notifyListeners();
  }

  @override
  bool get isInitialized => false;

  @override
  bool get isAvailable => product != null;

  @override
  ProductDetails? get keeperProduct => product;

  @override
  bool get isKeeper => keeper;

  @override
  KeeperEntitlementState get entitlementState =>
      keeper ? KeeperEntitlementState.keeper : KeeperEntitlementState.free;

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
