import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart' show purchaseService;

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  TextStyle premiumStyle(
    double size, {
    Color color = const Color(0xFFF4F0E8),
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontFamily: GoogleFonts.cormorantGaramond().fontFamily,
      height: 1.32,
      letterSpacing: 0.45,
    );
  }

  Future<void> buyKeeper() async {
  if (purchaseService.isLoading) return;

  final started = await purchaseService.buyKeeper();

  if (!mounted) return;

  if (!started) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF111111),
        content: Text(
          "Purchase is not ready yet. Please try again shortly.",
          style: premiumStyle(17),
        ),
      ),
    );
  }

  if (mounted) {
  setState(() {});
}
}

  Future<void> restorePurchases() async {
    if (purchaseService.isLoading) return;

    await purchaseService.restorePurchases();

    if (!mounted) return;

setState(() {});

ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    backgroundColor: const Color(0xFF111111),
    content: Text(
      purchaseService.isPremium
          ? "Purchases restored."
          : "No previous purchase was found.",
      style: premiumStyle(17),
    ),
  ),
);
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = purchaseService.isPremium;

    return Scaffold(
      backgroundColor: const Color(0xFF030303),
      appBar: AppBar(
        backgroundColor: const Color(0xFF030303),
        foregroundColor: const Color(0xFFF4F0E8),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD9B86F).withValues(alpha: 0.10),
                    blurRadius: 90,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: const Color(0xFFF4F0E8).withValues(alpha: 0.04),
                    blurRadius: 60,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 34),
              child: Column(
                children: [
                  const Spacer(),
                  Text(
                    isPremium
                        ? "Premium Active"
                        : "Become a Keeper of East",
                    textAlign: TextAlign.center,
                    style: premiumStyle(36),
                  ),
                  const SizedBox(height: 34),
                  Text(
                    isPremium
                        ? "Welcome, Keeper of East."
                        : "Unlimited Wisdom",
                    textAlign: TextAlign.center,
                    style: premiumStyle(24),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isPremium
                        ? "The circle is open."
                        : "Unlimited Favorites",
                    textAlign: TextAlign.center,
                    style: premiumStyle(24),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isPremium ? "No interruptions." : "No Interruptions",
                    textAlign: TextAlign.center,
                    style: premiumStyle(24),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    isPremium ? "Thank you for supporting East." : "One-time offering",
                    textAlign: TextAlign.center,
                    style: premiumStyle(
                      19,
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 52),
                  if (!isPremium)
                    GestureDetector(
                      onTap: buyKeeper,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(42),
                          border: Border.all(
                            color: const Color(0xFFF4F0E8),
                            width: 1,
                          ),
                          color:
                              const Color(0xFFF4F0E8).withValues(alpha: 0.04),
                        ),
                        child: Text(
                          purchaseService.isLoading
                              ? "Opening..."
                              : "Enter the Circle",
                          textAlign: TextAlign.center,
                          style: premiumStyle(23),
                        ),
                      ),
                    ),
                  if (!isPremium) const SizedBox(height: 18),
                  if (!isPremium)
                    GestureDetector(
                      onTap: restorePurchases,
                      child: Text(
                        "Restore Purchases",
                        style: premiumStyle(
                          18,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}