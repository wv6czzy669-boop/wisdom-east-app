import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/controllers/appearance_preference_controller.dart';
import 'package:wisdom_app/controllers/locale_preference_controller.dart';
import 'package:wisdom_app/models/daily_wisdom_selection.dart';
import 'package:wisdom_app/persistence/wisdom_selection_history_store.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/keeper_ritual_widget_coordinator.dart';
import 'package:wisdom_app/services/keeper_ritual_widget_service.dart';
import 'package:wisdom_app/services/purchase_service.dart';
import 'package:wisdom_app/services/wisdom_localization_resolver.dart';
import 'package:wisdom_app/services/wisdom_selector.dart';

import '../persistence_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late DailyAccessTestGraph graph;
  late AppearancePreferenceController appearance;
  late LocalePreferenceController locale;
  late _TestPurchaseService purchase;
  late _RecordingKeeperWidgetService widgetService;
  late KeeperRitualWidgetCoordinator coordinator;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      InAppPurchase.instance;
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    InAppPurchasePlatform.instance = _NoopInAppPurchasePlatform();
    now = DateTime.utc(2026, 8, 28, 10);
    graph = DailyAccessTestGraph(clock: () => now);
    appearance = AppearancePreferenceController();
    locale = LocalePreferenceController();
    purchase = _TestPurchaseService(keeper: true);
    widgetService = _RecordingKeeperWidgetService();
    coordinator = KeeperRitualWidgetCoordinator(
      appearanceController: appearance,
      localeController: locale,
      purchaseService: purchase,
      dailyWisdomAccessService: graph.service,
      dailyWisdomAccessServiceFactory: ({clock}) => DailyWisdomAccessService(
        repository: graph.repository,
        clock: clock,
      ),
      widgetService: widgetService,
      wisdomSelector: _selector(<Map<String, dynamic>>[
        _wisdom('east_wisdom_0001', 'First.'),
        _wisdom('east_wisdom_0002', 'Second.'),
      ]),
      wisdomPresentation: const WisdomLocalizationResolver(
        localizedCatalog: <String, Map<String, String>>{
          'tr': <String, String>{
            'east_wisdom_0001': 'Birinci.',
            'east_wisdom_0002': 'İkinci.',
          },
        },
      ),
      clock: () => now,
    );
  });

  tearDown(() {
    coordinator.dispose();
    purchase.dispose();
    appearance.dispose();
    locale.dispose();
  });

  test('a provisional widget reveal becomes the exact daily occurrence',
      () async {
    final revealedAt = now.subtract(const Duration(minutes: 2));
    final provisional = KeeperRitualWidgetReveal(
      candidateId: 'east_wisdom_0002:${revealedAt.millisecondsSinceEpoch}',
      canonicalText: 'Second.',
      displayText: 'Second.',
      wisdomId: 'east_wisdom_0002',
      revealedAt: revealedAt,
      unlockAt: revealedAt.add(const Duration(hours: 24)),
      needsAppCommit: true,
    );
    widgetService.snapshot = KeeperRitualWidgetSnapshot(
      isKeeper: true,
      state: 'revealed',
      reveal: provisional,
    );
    // Native StoreKit 2 already verified this AppIntent action, so the exact
    // reveal is committed even before Flutter's Keeper cache catches up.
    purchase.keeper = false;

    await coordinator.reconcileBeforeHome();
    final status = await graph.service.status();

    expect(status.isReady, isFalse);
    expect(status.wisdomId, 'east_wisdom_0002');
    expect(status.lockedText, 'Second.');
    expect(status.revealedAt!.isAtSameMomentAs(revealedAt), isTrue);
    expect(
      status.unlockAt!.isAtSameMomentAs(
        revealedAt.add(const Duration(hours: 24)),
      ),
      isTrue,
    );
    expect(status.revealId, isNotNull);
    expect(widgetService.entitlements, <bool>[false]);
  });

  test('a ready Keeper occurrence stages one canonical candidate', () async {
    await coordinator.reconcileBeforeHome();

    expect(widgetService.entitlements, <bool>[true]);
    expect(widgetService.prepared, hasLength(1));
    final candidate = widgetService.prepared.single;
    expect(
      candidate.wisdomId,
      anyOf('east_wisdom_0001', 'east_wisdom_0002'),
    );
    expect(candidate.activationAt, now);
    expect(candidate.preparedAt, now);
    expect(
      candidate.candidateId,
      '${candidate.wisdomId}:${now.millisecondsSinceEpoch}',
    );

    final pending = await graph.repository.loadPendingDailyWisdomReveal();
    expect(pending, isNotNull);
    expect(pending!.wisdomId, candidate.wisdomId);
    expect(pending.text, candidate.canonicalText);
  });

  test('a locked occurrence mirrors active identity and stages the next one',
      () async {
    final access = await graph.service.reveal(
      selectWisdom: () => 'First.',
      selectWisdomWithIdentity: () => DailyWisdomSelection(
        text: 'First.',
        wisdomId: 'east_wisdom_0001',
      ),
    );
    widgetService.clearCalls();

    await coordinator.reconcileBeforeHome();

    expect(widgetService.active, hasLength(1));
    final active = widgetService.active.single;
    expect(active.wisdomId, 'east_wisdom_0001');
    expect(active.revealId, access.revealId);
    expect(
      active.revealedAt.isAtSameMomentAs(access.revealedAt!),
      isTrue,
    );
    expect(active.unlockAt.isAtSameMomentAs(access.unlockAt!), isTrue);
    expect(active.needsAppCommit, isFalse);

    expect(widgetService.prepared, hasLength(1));
    final next = widgetService.prepared.single;
    expect(next.wisdomId, 'east_wisdom_0002');
    expect(next.activationAt.isAtSameMomentAs(access.unlockAt!), isTrue);
  });

  test('non-Keeper access never stages or selects a candidate', () async {
    purchase.keeper = false;

    await coordinator.reconcileBeforeHome();

    expect(widgetService.entitlements, <bool>[false]);
    expect(widgetService.prepared, isEmpty);
    expect(widgetService.active, isEmpty);
    expect(await graph.repository.loadPendingDailyWisdomReveal(), isNull);
  });

  test('unresolved StoreKit never publishes a temporary Free widget', () async {
    purchase.resolved = false;

    await coordinator.reconcileBeforeHome();

    expect(widgetService.entitlements, isEmpty);
    expect(widgetService.prepared, isEmpty);
    expect(widgetService.active, isEmpty);
    expect(await graph.repository.loadPendingDailyWisdomReveal(), isNull);
  });

  test('locale and appearance republish presentation, not identity', () async {
    await coordinator.reconcileBeforeHome();
    final first = widgetService.prepared.single;
    widgetService.clearCalls();

    await locale.setExplicitLocale(const Locale('tr'));
    await appearance.setMode(EastAppearanceMode.dark);
    await coordinator.reconcileBeforeHome();

    expect(widgetService.prepared, isNotEmpty);
    final latest = widgetService.prepared.last;
    expect(latest.candidateId, first.candidateId);
    expect(latest.wisdomId, first.wisdomId);
    expect(latest.canonicalText, first.canonicalText);
    expect(
      latest.displayText,
      first.wisdomId == 'east_wisdom_0001' ? 'Birinci.' : 'İkinci.',
    );
    expect(widgetService.lastAppearance, EastAppearanceMode.dark);
    expect(widgetService.lastLocaleOverrideTag, 'tr');
  });
}

Map<String, dynamic> _wisdom(String id, String text) => <String, dynamic>{
      'id': id,
      'text': text,
      'tags': <String>['stillness'],
      'tone': 'calm',
    };

WisdomSelectorService _selector(List<Map<String, dynamic>> catalog) =>
    WisdomSelectorService(
      catalog: catalog,
      random: Random(7),
      historyStore: _MemoryWisdomHistoryStore(),
    );

class _MemoryWisdomHistoryStore implements WisdomSelectionHistoryStore {
  List<String> ids = <String>[];

  @override
  Future<List<String>> loadRecentWisdomIds() async => List<String>.from(ids);

  @override
  Future<void> replaceRecentWisdomIds(List<String> wisdomIds) async {
    ids = List<String>.from(wisdomIds);
  }
}

class _TestPurchaseService extends PurchaseService {
  _TestPurchaseService({required this.keeper});

  bool keeper;
  bool resolved = true;

  @override
  bool get isKeeper => keeper;

  @override
  KeeperEntitlementState get entitlementState => !resolved
      ? KeeperEntitlementState.unresolved
      : keeper
          ? KeeperEntitlementState.keeper
          : KeeperEntitlementState.free;
}

class _RecordingKeeperWidgetService implements KeeperRitualWidgetService {
  KeeperRitualWidgetSnapshot? snapshot;
  final List<bool> entitlements = <bool>[];
  final List<KeeperRitualWidgetCandidate> prepared =
      <KeeperRitualWidgetCandidate>[];
  final List<KeeperRitualWidgetReveal> active = <KeeperRitualWidgetReveal>[];
  EastAppearanceMode? lastAppearance;
  String? lastLocaleOverrideTag;

  void clearCalls() {
    entitlements.clear();
    prepared.clear();
    active.clear();
  }

  @override
  Future<KeeperRitualWidgetSnapshot?> readSnapshot() async => snapshot;

  @override
  Future<bool> setKeeperEntitlement(bool isKeeper) async {
    entitlements.add(isKeeper);
    return true;
  }

  @override
  Future<bool> publishPrepared({
    required KeeperRitualWidgetCandidate candidate,
    required EastAppearanceMode appearanceMode,
    required String? localeOverrideTag,
  }) async {
    prepared.add(candidate);
    lastAppearance = appearanceMode;
    lastLocaleOverrideTag = localeOverrideTag;
    snapshot = KeeperRitualWidgetSnapshot(
      isKeeper: true,
      state: 'pause',
      candidate: candidate,
      reveal: snapshot?.reveal,
    );
    return true;
  }

  @override
  Future<bool> publishActive({
    required KeeperRitualWidgetReveal reveal,
    required EastAppearanceMode appearanceMode,
    required String? localeOverrideTag,
  }) async {
    active.add(reveal);
    lastAppearance = appearanceMode;
    lastLocaleOverrideTag = localeOverrideTag;
    snapshot = KeeperRitualWidgetSnapshot(
      isKeeper: true,
      state: 'revealed',
      reveal: reveal,
      nextCandidate: snapshot?.nextCandidate,
    );
    return true;
  }
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
  ) async =>
      ProductDetailsResponse(
        productDetails: const <ProductDetails>[],
        notFoundIDs: const <String>[PurchaseService.keeperProductId],
      );

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async =>
      false;

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}
}
