import 'package:flutter/material.dart';

import '../services/app_services.dart';

class KeeperScreen extends StatefulWidget {
  const KeeperScreen({super.key});

  @override
  State<KeeperScreen> createState() => _KeeperScreenState();
}

class _KeeperScreenState extends State<KeeperScreen> {
  bool _persistenceErrorShown = false;

  @override
  void initState() {
    super.initState();
    purchaseService.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) {
      final showPersistenceError =
          purchaseService.entitlementPersistenceFailed &&
              !_persistenceErrorShown;
      if (!purchaseService.entitlementPersistenceFailed) {
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
    purchaseService.removeListener(_refresh);
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
    if (purchaseService.isLoading) return;

    bool started = false;

    try {
      started = await purchaseService.buyKeeper();
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
            purchaseService.purchaseNeedsRecovery
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
    final isKeeper = purchaseService.isKeeper;
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
                      child: GestureDetector(
                        onTap: isKeeper || purchaseService.isLoading
                            ? null
                            : buyKeeper,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          opacity: purchaseService.isLoading ? 0.72 : 1.0,
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
                    const SizedBox(height: 108),
                    Text(
                      "Preserve what stays with you.",
                      textAlign: TextAlign.center,
                      style: keeperStyle(
                        15,
                        color: const Color(0xFFF4F0E8).withValues(alpha: 0.57),
                      ).copyWith(letterSpacing: 0.75),
                    ),
                    const SizedBox(height: 11),
                    Text(
                      "Keep EAST. alive.",
                      textAlign: TextAlign.center,
                      style: keeperStyle(
                        13,
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
