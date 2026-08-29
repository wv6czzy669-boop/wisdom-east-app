import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/east_localizations.dart';
import '../services/app_services.dart' as app_services;
import '../services/purchase_service.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';
import '../widgets/east_back_button.dart';

class KeeperScreen extends StatefulWidget {
  const KeeperScreen({
    super.key,
    this.purchaseService,
  });

  final PurchaseService? purchaseService;

  @override
  State<KeeperScreen> createState() => _KeeperScreenState();
}

class _KeeperScreenState extends State<KeeperScreen> {
  bool _persistenceErrorShown = false;

  PurchaseService get _purchaseService =>
      widget.purchaseService ?? app_services.purchaseService;

  @override
  void initState() {
    super.initState();
    _purchaseService.addListener(_refresh);
    if (_purchaseService.isInitialized) {
      unawaited(_purchaseService.refreshStoreIfNeeded());
    }
  }

  void _refresh() {
    if (mounted) {
      final showPersistenceError =
          _purchaseService.entitlementPersistenceFailed &&
              !_persistenceErrorShown;
      if (!_purchaseService.entitlementPersistenceFailed) {
        _persistenceErrorShown = false;
      } else if (showPersistenceError) {
        _persistenceErrorShown = true;
      }

      setState(() {});

      if (showPersistenceError) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: EastColors.of(context).surface,
              content: Text(
                eastLocalizations(context).keeperPersistenceError,
                style: keeperStyle(17),
              ),
            ),
          );
        });
      }
    }
  }

  @override
  void dispose() {
    _purchaseService.removeListener(_refresh);
    super.dispose();
  }

  TextStyle keeperStyle(
    double size, {
    Color? color,
  }) {
    return EastTypography.localized(
      context,
      size: size,
      color: color,
      height: 1.32,
      letterSpacing: 0.45,
    );
  }

  Future<void> buyKeeper() async {
    if (_purchaseService.isLoading) return;

    bool started = false;

    try {
      started = await _purchaseService.buyKeeper();
    } catch (_) {
      started = false;
    }

    if (!mounted) return;

    if (!started) {
      final l10n = eastLocalizations(context);
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: EastColors.of(context).surface,
          content: Text(
            _purchaseService.purchaseNeedsRecovery
                ? l10n.purchaseUpdating
                : l10n.purchaseNotReady,
            style: keeperStyle(17),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = eastLocalizations(context);
    final isKeeper = _purchaseService.isKeeper;
    final keeperProduct = _purchaseService.keeperProduct;
    final purchaseAvailable =
        _purchaseService.isAvailable && keeperProduct != null;
    final purchaseEnabled =
        !isKeeper && purchaseAvailable && !_purchaseService.isLoading;
    return Scaffold(
      backgroundColor: EastColors.of(context).background,
      appBar: AppBar(
        backgroundColor: EastColors.of(context).background,
        foregroundColor: EastColors.of(context).ink,
        iconTheme: IconThemeData(
          color: EastColors.of(context).ink,
          size: 22,
          weight: 300,
        ),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.canPop(context) ? const EastBackButton() : null,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minimumContentHeight =
                constraints.maxHeight > 60 ? constraints.maxHeight - 60 : 0.0;
            return SingleChildScrollView(
              key: const ValueKey('keeper-scroll-view'),
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minimumContentHeight),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.keeper,
                        textAlign: TextAlign.center,
                        style: keeperStyle(48).copyWith(letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 34),
                      Text(
                        l10n.keepWhatStays,
                        textAlign: TextAlign.center,
                        style: keeperStyle(
                          25,
                          color: eastMutedTextColor(context),
                        ).copyWith(letterSpacing: 1.55),
                      ),
                      const SizedBox(height: 92),
                      Semantics(
                        button: !isKeeper,
                        enabled: purchaseEnabled,
                        label: isKeeper
                            ? l10n.keeperAccessActive
                            : _purchaseService.isLoading && purchaseAvailable
                                ? l10n.keeperPurchaseInProgress(
                                    keeperProduct.price,
                                  )
                                : purchaseAvailable
                                    ? l10n.keeperPurchaseOffering(
                                        keeperProduct.price,
                                      )
                                    : l10n.keeperUnavailable,
                        onTap: purchaseEnabled ? buyKeeper : null,
                        child: ExcludeSemantics(
                          child: GestureDetector(
                            key: const ValueKey('keeper-purchase-action'),
                            excludeFromSemantics: true,
                            onTap: purchaseEnabled ? buyKeeper : null,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutCubic,
                              opacity: _purchaseService.isLoading ? 0.72 : 1.0,
                              child: Container(
                                width: 238,
                                height: 238,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: EastColors.of(context)
                                      .ink
                                      .withValues(alpha: 0.012),
                                  border: Border.all(
                                    color: eastMutedTextColor(context),
                                    width: 0.7,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: EastColors.of(context)
                                          .accent
                                          .withValues(alpha: 0.05),
                                      blurRadius: 122,
                                      spreadRadius: 5,
                                    ),
                                    BoxShadow(
                                      color: EastColors.of(context)
                                          .ink
                                          .withValues(alpha: 0.02),
                                      blurRadius: 78,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 22),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: SizedBox(
                                      width: 194,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            isKeeper
                                                ? l10n.withinTheCircle
                                                : l10n.enterTheCircle,
                                            textAlign: TextAlign.center,
                                            style: keeperStyle(22)
                                                .copyWith(letterSpacing: 0.85),
                                          ),
                                          if (isKeeper) ...[
                                            const SizedBox(height: 14),
                                            Text(
                                              l10n.keeperActive,
                                              key: const ValueKey(
                                                'keeper-active-status',
                                              ),
                                              textAlign: TextAlign.center,
                                              style: keeperStyle(
                                                14,
                                                color:
                                                    eastMutedTextColor(context),
                                              ).copyWith(letterSpacing: 0.75),
                                            ),
                                          ] else if (keeperProduct != null) ...[
                                            const SizedBox(height: 14),
                                            Text(
                                              keeperProduct.price,
                                              key: const ValueKey(
                                                'keeper-localized-price',
                                              ),
                                              textAlign: TextAlign.center,
                                              style: keeperStyle(17).copyWith(
                                                  letterSpacing: 0.65),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              l10n.oneTimePurchase,
                                              key: const ValueKey(
                                                'keeper-one-time-purchase',
                                              ),
                                              textAlign: TextAlign.center,
                                              style: keeperStyle(
                                                13,
                                                color:
                                                    eastMutedTextColor(context),
                                              ).copyWith(letterSpacing: 0.65),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Lower composition: a quiet editorial close, not a
                      // feature list. Hierarchy comes entirely from spacing
                      // rhythm -- no rules, labels, or graphic dividers. The
                      // core pair is tightly bound, with a wider pause before
                      // the Journal benefit and the closing sentiment.
                      const SizedBox(height: 72),
                      Text(
                        l10n.keepWithoutLimit,
                        textAlign: TextAlign.center,
                        style: keeperStyle(16).copyWith(letterSpacing: 0.75),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.reflectWithoutLimit,
                        textAlign: TextAlign.center,
                        style: keeperStyle(16).copyWith(letterSpacing: 0.75),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        l10n.takeJournalWithYou,
                        textAlign: TextAlign.center,
                        style: keeperStyle(16).copyWith(letterSpacing: 0.75),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.keeperWidgetRitual,
                        textAlign: TextAlign.center,
                        style: keeperStyle(16).copyWith(letterSpacing: 0.75),
                      ),
                      const SizedBox(height: 44),
                      Text(
                        l10n.keepEastAlive,
                        textAlign: TextAlign.center,
                        style: keeperStyle(
                          14,
                          color: eastMutedTextColor(context),
                        ).copyWith(letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
