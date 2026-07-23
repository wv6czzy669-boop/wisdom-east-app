import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_services.dart' as app_services;
import '../services/purchase_service.dart';

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
              backgroundColor: const Color(0xFF111111),
              content: Text(
                "Keeper access could not be saved. Please try Restore Purchases.",
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
    Color color = const Color(0xFFF4F0E8),
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontFamily: 'CormorantGaramond',
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
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF111111),
          content: Text(
            _purchaseService.purchaseNeedsRecovery
                ? "Purchase status is still updating. Please use Restore Purchases in Settings."
                : "Purchase is not ready yet. Please try again shortly.",
            style: keeperStyle(17),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKeeper = _purchaseService.isKeeper;
    final keeperProduct = _purchaseService.keeperProduct;
    final purchaseAvailable =
        _purchaseService.isAvailable && keeperProduct != null;
    final purchaseEnabled =
        !isKeeper && purchaseAvailable && !_purchaseService.isLoading;
    return Scaffold(
      backgroundColor: const Color(0xFF040404),
      appBar: AppBar(
        backgroundColor: const Color(0xFF040404),
        foregroundColor: const Color(0xFFF4F0E8),
        iconTheme: const IconThemeData(
          color: Color(0xFFF4F0E8),
          size: 22,
          weight: 300,
        ),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: SizedBox.expand(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Transform.translate(
                offset: const Offset(0, -8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Keeper",
                      textAlign: TextAlign.center,
                      style: keeperStyle(48).copyWith(letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 34),
                    Text(
                      "Keep what stays.",
                      textAlign: TextAlign.center,
                      style: keeperStyle(
                        25,
                        color: const Color(0xFFF4F0E8).withValues(alpha: 0.82),
                      ).copyWith(letterSpacing: 1.55),
                    ),
                    const SizedBox(height: 92),
                    Semantics(
                      button: !isKeeper,
                      enabled: purchaseEnabled,
                      label: isKeeper
                          ? 'Keeper access active'
                          : _purchaseService.isLoading && purchaseAvailable
                              ? 'Enter the Circle, ${keeperProduct.price}. Purchase in progress.'
                              : purchaseAvailable
                                  ? 'Enter the Circle, ${keeperProduct.price}, one-time offering'
                                  : 'Enter the Circle, temporarily unavailable',
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
                                color: const Color(0xFFF4F0E8)
                                    .withValues(alpha: 0.012),
                                border: Border.all(
                                  color: const Color(0xFFF4F0E8)
                                      .withValues(alpha: 0.38),
                                  width: 0.7,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFD9B86F)
                                        .withValues(alpha: 0.05),
                                    blurRadius: 122,
                                    spreadRadius: 5,
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFFF4F0E8)
                                        .withValues(alpha: 0.02),
                                    blurRadius: 78,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 22),
                                child: Text(
                                  "Enter the Circle",
                                  textAlign: TextAlign.center,
                                  style: keeperStyle(22)
                                      .copyWith(letterSpacing: 0.85),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 108),
                    Text(
                      "Keep reflections without limit.",
                      textAlign: TextAlign.center,
                      style: keeperStyle(
                        16,
                        color: const Color(0xFFF4F0E8).withValues(alpha: 0.57),
                      ).copyWith(letterSpacing: 0.75),
                    ),
                    const SizedBox(height: 11),
                    Text(
                      "Keep EAST. alive.",
                      textAlign: TextAlign.center,
                      style: keeperStyle(
                        14,
                        color: const Color(0xFFF4F0E8).withValues(alpha: 0.57),
                      ).copyWith(letterSpacing: 0.8),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
