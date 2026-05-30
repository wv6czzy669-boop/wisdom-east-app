import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

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

  void showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF111111),
        content: Text(
          "Apple In-App Purchase will be connected before launch.",
          style: premiumStyle(17),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    "East Premium",
                    textAlign: TextAlign.center,
                    style: premiumStyle(38),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "A quieter path, without interruption.",
                    textAlign: TextAlign.center,
                    style: premiumStyle(
                      21,
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 34),
                  _PremiumFeature(
                    icon: Icons.visibility_outlined,
                    text: "Reveal wisdom without waiting",
                    style: premiumStyle(21),
                  ),
                  _PremiumFeature(
                    icon: Icons.favorite_border,
                    text: "Save unlimited reflections",
                    style: premiumStyle(21),
                  ),
                  _PremiumFeature(
                    icon: Icons.block,
                    text: "Remove all ads",
                    style: premiumStyle(21),
                  ),
                  _PremiumFeature(
                    icon: Icons.spa_outlined,
                    text: "Support the future of East",
                    style: premiumStyle(21),
                  ),
                  const SizedBox(height: 38),
                  GestureDetector(
                    onTap: () => showComingSoon(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(42),
                        border: Border.all(
                          color: const Color(0xFFF4F0E8),
                          width: 1,
                        ),
                        color: const Color(0xFFF4F0E8).withValues(alpha: 0.04),
                      ),
                      child: Text(
                        "Unlock Premium",
                        textAlign: TextAlign.center,
                        style: premiumStyle(23),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => showComingSoon(context),
                    child: Text(
                      "Restore Purchase",
                      style: premiumStyle(
                        18,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Pricing will be finalized before App Store release.",
                    textAlign: TextAlign.center,
                    style: premiumStyle(
                      14,
                      color: Colors.white30,
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

class _PremiumFeature extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextStyle style;

  const _PremiumFeature({
    required this.icon,
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFFF4F0E8).withValues(alpha: 0.78),
            size: 22,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              text,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}