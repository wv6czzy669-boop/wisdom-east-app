import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  TextStyle eastStyle(
    double size, {
    Color color = const Color(0xFFF4F0E8),
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontFamily: GoogleFonts.cormorantGaramond().fontFamily,
      height: 1.35,
      letterSpacing: 0.4,
    );
  }

  Widget settingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white10,
      highlightColor: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 17,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: Colors.white60,
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: eastStyle(21),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: eastStyle(
                      15,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF111111),
        content: Text(
          "This will be connected before launch.",
          style: eastStyle(17),
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
        title: Text(
          "East",
          style: eastStyle(26),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          24,
          16,
          24,
          36,
        ),
        children: [
          Text(
            "Daily Wisdom",
            style: eastStyle(34),
          ),
          const SizedBox(height: 10),
          Text(
            "A quiet space for reflection, stillness, and timeless Eastern wisdom.",
            style: eastStyle(
              20,
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: 34),
          const Divider(
            color: Colors.white24,
            thickness: 0.5,
          ),
          settingsItem(
            icon: Icons.workspace_premium_outlined,
            title: "Premium",
            subtitle: "Unlimited reveals, unlimited favorites, and no ads.",
            onTap: () => comingSoon(context),
          ),
          const Divider(
            color: Colors.white24,
            thickness: 0.5,
          ),
          settingsItem(
            icon: Icons.restore,
            title: "Restore Purchases",
            subtitle: "Restore your Premium access on this device.",
            onTap: () => comingSoon(context),
          ),
          const Divider(
            color: Colors.white24,
            thickness: 0.5,
          ),
          settingsItem(
            icon: Icons.privacy_tip_outlined,
            title: "Privacy Policy",
            subtitle: "Required for App Store release.",
            onTap: () => comingSoon(context),
          ),
          const Divider(
            color: Colors.white24,
            thickness: 0.5,
          ),
          settingsItem(
            icon: Icons.mail_outline,
            title: "Contact",
            subtitle: "Support and feedback.",
            onTap: () => comingSoon(context),
          ),
          const Divider(
            color: Colors.white24,
            thickness: 0.5,
          ),
          const SizedBox(height: 34),
          Center(
            child: Text(
              "Version 1.0.0",
              style: eastStyle(
                15,
                color: Colors.white38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}