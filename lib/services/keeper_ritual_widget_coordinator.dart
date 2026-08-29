import 'dart:async';

import 'package:flutter/widgets.dart';

import '../controllers/appearance_preference_controller.dart';
import '../controllers/locale_preference_controller.dart';
import '../localization/east_locale_registry.dart';
import '../models/daily_wisdom_selection.dart';
import 'daily_wisdom_access_service.dart';
import 'keeper_ritual_widget_service.dart';
import 'purchase_service.dart';
import 'wisdom_localization_resolver.dart';
import 'wisdom_selector.dart';

typedef DailyWisdomAccessServiceFactory = DailyWisdomAccessService Function({
  WisdomClock? clock,
});

/// Keeps the optional Keeper ritual widget and EAST.'s existing daily-access
/// record on one occurrence.
///
/// WidgetKit may record a provisional reveal while the Flutter process is
/// absent. This coordinator commits that exact candidate through
/// [DailyWisdomAccessService] before Home reads its status. The repository
/// still mints the revealId and remains the sole authority for the rolling
/// 24-hour lock; the widget never writes either domain directly.
class KeeperRitualWidgetCoordinator {
  KeeperRitualWidgetCoordinator({
    required AppearancePreferenceController appearanceController,
    required LocalePreferenceController localeController,
    required PurchaseService purchaseService,
    required DailyWisdomAccessService dailyWisdomAccessService,
    required DailyWisdomAccessServiceFactory dailyWisdomAccessServiceFactory,
    required KeeperRitualWidgetService widgetService,
    required WisdomSelectorService wisdomSelector,
    WisdomLocalizationResolver wisdomPresentation =
        const WisdomLocalizationResolver(),
    WisdomClock? clock,
  })  : _appearanceController = appearanceController,
        _localeController = localeController,
        _purchaseService = purchaseService,
        _dailyWisdomAccessService = dailyWisdomAccessService,
        _dailyWisdomAccessServiceFactory = dailyWisdomAccessServiceFactory,
        _widgetService = widgetService,
        _wisdomSelector = wisdomSelector,
        _wisdomPresentation = wisdomPresentation,
        _clock = clock ?? DateTime.now;

  final AppearancePreferenceController _appearanceController;
  final LocalePreferenceController _localeController;
  final PurchaseService _purchaseService;
  final DailyWisdomAccessService _dailyWisdomAccessService;
  final DailyWisdomAccessServiceFactory _dailyWisdomAccessServiceFactory;
  final KeeperRitualWidgetService _widgetService;
  final WisdomSelectorService _wisdomSelector;
  final WisdomLocalizationResolver _wisdomPresentation;
  final WisdomClock _clock;

  Future<void> _tail = Future<void>.value();
  late final _KeeperResumeObserver _resumeObserver =
      _KeeperResumeObserver(_scheduleReconciliation);
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _appearanceController.addListener(_scheduleReconciliation);
    _localeController.addListener(_scheduleReconciliation);
    _purchaseService.addListener(_scheduleReconciliation);
    WidgetsBinding.instance.addObserver(_resumeObserver);
    _scheduleReconciliation();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _appearanceController.removeListener(_scheduleReconciliation);
    _localeController.removeListener(_scheduleReconciliation);
    _purchaseService.removeListener(_scheduleReconciliation);
    WidgetsBinding.instance.removeObserver(_resumeObserver);
  }

  /// Home awaits this before its first/resumed daily status read, ensuring a
  /// wisdom revealed in the widget is already the app's current occurrence.
  Future<void> reconcileBeforeHome() => _enqueueReconciliation();

  /// An app-side commit is already authoritative. Reconciliation mirrors it
  /// to the Keeper widget and prepares the following occurrence.
  void notifyAuthoritativeReveal() => _scheduleReconciliation();

  void _scheduleReconciliation() {
    if (_disposed) return;
    unawaited(_enqueueReconciliation());
  }

  Future<void> _enqueueReconciliation() {
    if (_disposed) return Future<void>.value();
    final result = _tail.then((_) async {
      if (_disposed) return;
      try {
        await _reconcileOnce();
      } catch (_) {
        // Widget mirroring can never interrupt daily access or app startup.
      }
    });
    _tail = result.catchError((_) {});
    return result;
  }

  Future<void> _reconcileOnce() async {
    final initialSnapshot = await _widgetService.readSnapshot();

    // A provisional reveal can only be created by the iOS 17 AppIntent after
    // StoreKit 2 verifies Keeper. Reconcile it even if Flutter's entitlement
    // cache has not finished loading yet, so launch never starts a second
    // ritual for the same occurrence.
    final provisional = initialSnapshot?.reveal;
    if (provisional != null && provisional.needsAppCommit) {
      await _commitProvisionalReveal(provisional);
    }

    final isKeeper = _purchaseService.isKeeper;
    await _widgetService.setKeeperEntitlement(isKeeper);
    if (!isKeeper || _disposed) return;

    final snapshot = await _widgetService.readSnapshot() ?? initialSnapshot;
    final status = await _dailyWisdomAccessService.status();
    if (_disposed) return;

    if (!status.isReady) {
      await _publishLockedOccurrence(status);
      if (_disposed) return;
      await _ensureNextCandidate(status, snapshot);
      return;
    }

    await _publishReadyCandidate(snapshot);
  }

  Future<void> _commitProvisionalReveal(
    KeeperRitualWidgetReveal reveal,
  ) async {
    final fixedClockService = _dailyWisdomAccessServiceFactory(
      clock: () => reveal.revealedAt,
    );
    final prepared = await fixedClockService.prepareReveal(
      selectWisdom: () => reveal.canonicalText,
      selectWisdomWithIdentity: () => DailyWisdomSelection(
        text: reveal.canonicalText,
        wisdomId: reveal.wisdomId,
      ),
    );

    // An already-active or pre-existing pending occurrence always wins.
    // The normal case is an exact identity match because the app staged the
    // candidate before WidgetKit displayed it.
    if (prepared.wisdomId != reveal.wisdomId ||
        prepared.text != reveal.canonicalText ||
        prepared.hasAuthoritativeRecord) {
      return;
    }

    await fixedClockService.finalizeVisualReveal(
      text: prepared.text,
      revealBoundary: reveal.revealedAt,
    );
  }

  Future<void> _publishLockedOccurrence(DailyWisdomStatus status) async {
    final canonicalText = status.lockedText;
    final wisdomId = status.wisdomId;
    final revealedAt = status.revealedAt;
    final unlockAt = status.unlockAt;
    if (canonicalText == null ||
        wisdomId == null ||
        revealedAt == null ||
        unlockAt == null) {
      return;
    }
    final presentation = _presentation;
    await _widgetService.publishActive(
      reveal: KeeperRitualWidgetReveal(
        candidateId: _candidateId(wisdomId, revealedAt),
        canonicalText: canonicalText,
        displayText: _localizedText(
          wisdomId: wisdomId,
          canonicalText: canonicalText,
          locale: presentation.locale,
        ),
        wisdomId: wisdomId,
        revealedAt: revealedAt,
        unlockAt: unlockAt,
        revealId: status.revealId,
        needsAppCommit: false,
      ),
      appearanceMode: presentation.appearance,
      localeOverrideTag: presentation.localeOverrideTag,
    );
  }

  Future<void> _ensureNextCandidate(
    DailyWisdomStatus status,
    KeeperRitualWidgetSnapshot? snapshot,
  ) async {
    final unlockAt = status.unlockAt;
    if (unlockAt == null) return;
    final now = _clock();
    final existing = snapshot?.nextCandidate;
    if (existing != null &&
        !existing.activationAt.isBefore(unlockAt) &&
        existing.wisdomId != status.wisdomId) {
      await _publishCandidate(_relocalized(existing));
      return;
    }

    final selection = await _selectDifferentFrom(status.wisdomId);
    if (selection == null) return;
    await _publishCandidate(
      _candidateFromSelection(
        selection,
        preparedAt: now,
        activationAt: unlockAt,
      ),
    );
  }

  Future<void> _publishReadyCandidate(
    KeeperRitualWidgetSnapshot? snapshot,
  ) async {
    final now = _clock();
    final existing = snapshot?.candidate;
    DailyWisdomPreparedReveal prepared;
    if (existing != null && !existing.activationAt.isAfter(now)) {
      prepared = await _dailyWisdomAccessService.prepareReveal(
        selectWisdom: () => existing.canonicalText,
        selectWisdomWithIdentity: () => DailyWisdomSelection(
          text: existing.canonicalText,
          wisdomId: existing.wisdomId,
        ),
      );
    } else {
      prepared = await _dailyWisdomAccessService.prepareReveal(
        selectWisdom: () async =>
            (await _wisdomSelector.select())['text'] as String,
        selectWisdomWithIdentity: _selectWisdomWithIdentity,
      );
    }

    if (prepared.hasAuthoritativeRecord) {
      final status = await _dailyWisdomAccessService.status();
      if (!status.isReady) await _publishLockedOccurrence(status);
      return;
    }
    final wisdomId = prepared.wisdomId;
    if (wisdomId == null) return;

    final matchingExisting = existing != null &&
            existing.wisdomId == wisdomId &&
            existing.canonicalText == prepared.text
        ? existing
        : null;
    await _publishCandidate(
      matchingExisting == null
          ? _candidateFromSelection(
              DailyWisdomSelection(
                text: prepared.text,
                wisdomId: wisdomId,
              ),
              preparedAt: now,
              activationAt: now,
            )
          : _relocalized(matchingExisting),
    );
  }

  Future<DailyWisdomSelection> _selectWisdomWithIdentity() async {
    final wisdom = await _wisdomSelector.select();
    return DailyWisdomSelection(
      text: wisdom['text'] as String,
      wisdomId: wisdom['id'] as String?,
    );
  }

  Future<DailyWisdomSelection?> _selectDifferentFrom(String? wisdomId) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final selection = await _selectWisdomWithIdentity();
      if (selection.wisdomId != null && selection.wisdomId != wisdomId) {
        return selection;
      }
    }
    return null;
  }

  KeeperRitualWidgetCandidate _candidateFromSelection(
    DailyWisdomSelection selection, {
    required DateTime preparedAt,
    required DateTime activationAt,
  }) {
    final wisdomId = selection.wisdomId!;
    final presentation = _presentation;
    return KeeperRitualWidgetCandidate(
      candidateId: _candidateId(wisdomId, activationAt),
      canonicalText: selection.text,
      displayText: _localizedText(
        wisdomId: wisdomId,
        canonicalText: selection.text,
        locale: presentation.locale,
      ),
      wisdomId: wisdomId,
      preparedAt: preparedAt,
      activationAt: activationAt,
    );
  }

  KeeperRitualWidgetCandidate _relocalized(
    KeeperRitualWidgetCandidate candidate,
  ) {
    final presentation = _presentation;
    return KeeperRitualWidgetCandidate(
      candidateId: candidate.candidateId,
      canonicalText: candidate.canonicalText,
      displayText: _localizedText(
        wisdomId: candidate.wisdomId,
        canonicalText: candidate.canonicalText,
        locale: presentation.locale,
      ),
      wisdomId: candidate.wisdomId,
      preparedAt: candidate.preparedAt,
      activationAt: candidate.activationAt,
    );
  }

  Future<void> _publishCandidate(KeeperRitualWidgetCandidate candidate) async {
    final presentation = _presentation;
    await _widgetService.publishPrepared(
      candidate: candidate,
      appearanceMode: presentation.appearance,
      localeOverrideTag: presentation.localeOverrideTag,
    );
  }

  String _localizedText({
    required String wisdomId,
    required String canonicalText,
    required Locale locale,
  }) =>
      _wisdomPresentation.resolve(
        wisdomId: wisdomId,
        locale: locale,
        persistedSnapshot: canonicalText,
      ) ??
      canonicalText;

  String _candidateId(String wisdomId, DateTime activationAt) =>
      '$wisdomId:${activationAt.toUtc().millisecondsSinceEpoch}';

  _KeeperPresentation get _presentation {
    final explicitLocale = _localeController.explicitLocale;
    final effectiveLocale = explicitLocale ??
        EastLocaleRegistry.resolveProductLocale(
          WidgetsBinding.instance.platformDispatcher.locale,
        );
    return _KeeperPresentation(
      appearance: _appearanceController.mode,
      locale: effectiveLocale,
      localeOverrideTag: explicitLocale == null
          ? null
          : LocalePreferenceController.toBcp47Tag(explicitLocale),
    );
  }
}

class _KeeperPresentation {
  const _KeeperPresentation({
    required this.appearance,
    required this.locale,
    required this.localeOverrideTag,
  });

  final EastAppearanceMode appearance;
  final Locale locale;
  final String? localeOverrideTag;
}

class _KeeperResumeObserver extends WidgetsBindingObserver {
  _KeeperResumeObserver(this._onResumed);

  final VoidCallback _onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResumed();
  }
}
