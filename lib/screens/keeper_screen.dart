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
            "Purchase is not ready yet. Please try again shortly.",
            style: keeperStyle(17),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKeeper = purchaseService.isKeeper;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final circleSize =
        (214 + ((textScale - 1).clamp(0.0, 1.5) * 32)).clamp(214, 260);

    return Scaffold(
      backgroundColor: const Color(0xFF030303),
      appBar: AppBar(
        backgroundColor: const Color(0xFF030303),
        foregroundColor: const Color(0xFFF4F0E8),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(30, 18, 30, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 50,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(flex: 3),
                      Text(
                        "Keeper",
                        textAlign: TextAlign.center,
                        style: keeperStyle(42).copyWith(letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "Keep what stays.",
                        textAlign: TextAlign.center,
                        style: keeperStyle(
                          23,
                          color:
                              const Color(0xFFF4F0E8).withValues(alpha: 0.82),
                        ).copyWith(letterSpacing: 1.35),
                      ),
                      const Spacer(flex: 2),
                      Semantics(
                        button: !isKeeper,
                        child: GestureDetector(
                          onTap: isKeeper || purchaseService.isLoading
                              ? null
                              : buyKeeper,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 500),
                            opacity: purchaseService.isLoading ? 0.72 : 1.0,
                            child: Container(
                              width: circleSize.toDouble(),
                              height: circleSize.toDouble(),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFF4F0E8)
                                    .withValues(alpha: 0.012),
                                border: Border.all(
                                  color: const Color(0xFFF4F0E8)
                                      .withValues(alpha: 0.42),
                                  width: 0.7,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFD9B86F)
                                        .withValues(alpha: 0.055),
                                    blurRadius: 118,
                                    spreadRadius: 5,
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFFF4F0E8)
                                        .withValues(alpha: 0.022),
                                    blurRadius: 72,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  "Enter the Circle",
                                  textAlign: TextAlign.center,
                                  style: keeperStyle(21)
                                      .copyWith(letterSpacing: 0.75),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(flex: 3),
                      Text(
                        "Preserve what stays with you.",
                        textAlign: TextAlign.center,
                        style: keeperStyle(
                          14,
                          color:
                              const Color(0xFFF4F0E8).withValues(alpha: 0.55),
                        ).copyWith(letterSpacing: 0.7),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        "Help keep East alive.",
                        textAlign: TextAlign.center,
                        style: keeperStyle(
                          12,
                          color:
                              const Color(0xFFF4F0E8).withValues(alpha: 0.55),
                        ).copyWith(letterSpacing: 0.75),
                      ),
                      const Spacer(),
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
