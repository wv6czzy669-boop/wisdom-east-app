import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/east_localizations.dart';
import '../services/app_services.dart' as app_services;
import '../services/purchase_service.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';
import '../widgets/east_back_button.dart';
import '../widgets/keeper_experience_preview.dart';

class KeeperScreen extends StatefulWidget {
  const KeeperScreen({
    super.key,
    this.purchaseService,
    this.supportsInteractiveKeeperWidget,
  });

  final PurchaseService? purchaseService;
  final bool? supportsInteractiveKeeperWidget;

  @override
  State<KeeperScreen> createState() => _KeeperScreenState();
}

class _KeeperScreenState extends State<KeeperScreen> {
  bool _persistenceErrorShown = false;

  PurchaseService get _purchaseService =>
      widget.purchaseService ?? app_services.purchaseService;

  bool get _supportsInteractiveKeeperWidget {
    final override = widget.supportsInteractiveKeeperWidget;
    if (override != null) return override;
    if (!Platform.isIOS) return false;
    final match = RegExp(r'(?:Version\s+)?(\d+)')
        .firstMatch(Platform.operatingSystemVersion);
    final major = int.tryParse(match?.group(1) ?? '');
    return major != null && major >= 17;
  }

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
    final isKeeper = _purchaseService.resolveKeeperAccess();
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.keeper,
                          textAlign: TextAlign.center,
                          style: keeperStyle(48).copyWith(letterSpacing: 0.8),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.keepWhatStays,
                          textAlign: TextAlign.center,
                          style: keeperStyle(
                            25,
                            color: eastMutedTextColor(context),
                          ).copyWith(letterSpacing: 1.55),
                        ),
                        const SizedBox(height: 28),
                        const KeeperExperiencePreview(),
                        const SizedBox(height: 22),
                        Text(
                          l10n.keeperDailyRitual,
                          key: const ValueKey('keeper-daily-ritual'),
                          textAlign: TextAlign.center,
                          style: keeperStyle(14).copyWith(
                            color: eastMutedTextColor(context),
                          ),
                        ),
                        const SizedBox(height: 28),
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
                                opacity:
                                    _purchaseService.isLoading ? 0.72 : 1.0,
                                child: Container(
                                  width: isKeeper ? 168 : 190,
                                  height: isKeeper ? 168 : 190,
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
                                    padding: EdgeInsets.symmetric(
                                        horizontal: isKeeper ? 14 : 22),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: SizedBox(
                                        width: isKeeper ? 140 : 146,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              isKeeper
                                                  ? l10n.withinTheCircle
                                                  : l10n.enterTheCircle,
                                              textAlign: TextAlign.center,
                                              style: keeperStyle(22).copyWith(
                                                  letterSpacing: 0.85),
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
                                                  color: eastMutedTextColor(
                                                      context),
                                                ).copyWith(letterSpacing: 0.75),
                                              ),
                                            ] else if (keeperProduct !=
                                                null) ...[
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
                                                  color: eastMutedTextColor(
                                                      context),
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
                        const SizedBox(height: 26),
                        if (isKeeper) ...[
                          _widgetGuide(),
                          const SizedBox(height: 32),
                        ] else ...[
                          Text(
                            l10n.keepWithoutLimit,
                            textAlign: TextAlign.center,
                            style: keeperStyle(16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.reflectWithoutLimit,
                            textAlign: TextAlign.center,
                            style: keeperStyle(16),
                          ),
                          const SizedBox(height: 28),
                        ],
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
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _widgetGuide() {
    final l10n = eastLocalizations(context);
    final steps = [
      l10n.keeperWidgetStepOne,
      l10n.keeperWidgetStepTwo,
      l10n.keeperWidgetStepThree
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.addKeeperWidget,
              key: const ValueKey('keeper-widget-guide-title'),
              style: keeperStyle(23)),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < steps.length; index++)
          Padding(
            key: ValueKey('keeper-widget-guide-step-${index + 1}'),
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                      width: 30,
                      child: Text(
                          MaterialLocalizations.of(context)
                              .formatDecimal(index + 1),
                          style: keeperStyle(17)
                              .copyWith(color: eastMutedTextColor(context)))),
                ),
                Expanded(child: Text(steps[index], style: keeperStyle(17))),
              ],
            ),
          ),
        Text(
          _supportsInteractiveKeeperWidget
              ? l10n.keeperWidgetInteractive
              : l10n.keeperWidgetOpensApp,
          key: const ValueKey('keeper-widget-guide-detail'),
          style: keeperStyle(14).copyWith(color: eastMutedTextColor(context)),
        ),
      ],
    );
  }
}
