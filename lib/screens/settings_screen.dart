import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_services.dart';
import 'keeper_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.notificationsEnabled = false,
  });

  final bool notificationsEnabled;

  TextStyle eastStyle(
    double size, {
    Color color = const Color(0xFFF4F0E8),
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontFamily: 'CormorantGaramond',
      height: 1.35,
      letterSpacing: 0.4,
    );
  }

  Widget settingsItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
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
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: eastStyle(
                        15,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 16),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  void showInfoDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: Text(
            title,
            style: eastStyle(21),
          ),
          content: Text(
            message,
            style: eastStyle(
              17,
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "Close",
                style: eastStyle(16),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> openPrivacyPolicy() async {
    final uri = Uri.parse(
      'https://wv6czzy669-boop.github.io/daily-wisdom-east-privacy/',
    );

    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  Future<void> sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'dailywisdomeast@gmail.com',
      query: 'subject=EAST. Support',
    );

    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
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
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(
          "EAST.",
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
            "Silence, before meaning.",
            style: eastStyle(34),
          ),
          const SizedBox(height: 34),
          const Divider(
            color: Colors.white24,
            thickness: 0.5,
          ),
          settingsItem(
            icon: Icons.workspace_premium_outlined,
            title: "Keeper",
            subtitle: "Unlimited kept reflections and support for EAST.",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const KeeperScreen(),
                ),
              );
            },
          ),
          const Divider(
            color: Colors.white24,
            thickness: 0.5,
          ),
          settingsItem(
            icon: Icons.notifications_none,
            title: "Notifications",
            trailing: _NotificationStateIndicator(
              isEnabled: notificationsEnabled,
            ),
          ),
          const Divider(
            color: Colors.white24,
            thickness: 0.5,
          ),
          settingsItem(
            icon: Icons.restore,
            title: "Restore Purchases",
            subtitle: "Restore your Keeper access on this device.",
            onTap: () async {
              if (purchaseService.isLoading) return;

              var restoreStarted = false;
              try {
                restoreStarted = await purchaseService.restorePurchases();
              } catch (_) {}

              if (!context.mounted) return;
              showInfoDialog(
                context,
                "Restore Purchases",
                restoreStarted
                    ? "Restore request sent. Keeper access will update automatically."
                    : purchaseService.restoreNeedsRecovery
                        ? "A previous restore is still being reconciled. Keeper access will update automatically; reopen EAST. before trying again."
                        : "Restore is not available right now. Please try again shortly.",
              );
            },
          ),
          const Divider(
            color: Colors.white24,
            thickness: 0.5,
          ),
          settingsItem(
            icon: Icons.privacy_tip_outlined,
            title: "Privacy Policy",
            subtitle: "How EAST. handles your information.",
            onTap: () async {
              await openPrivacyPolicy();

              if (!context.mounted) return;
            },
          ),
          const Divider(
            color: Colors.white24,
            thickness: 0.5,
          ),
          settingsItem(
            icon: Icons.mail_outline,
            title: "Contact",
            subtitle: "Support and feedback.",
            onTap: sendEmail,
          ),
          const Divider(
            color: Colors.white24,
            thickness: 0.5,
          ),
          const SizedBox(height: 34),
          Center(
            child: Text(
              "built quietly.",
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

class _NotificationStateIndicator extends StatelessWidget {
  const _NotificationStateIndicator({required this.isEnabled});

  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: isEnabled ? 'Notifications enabled' : 'Notifications disabled',
      child: ExcludeSemantics(
        child: Text(
          isEnabled ? '●' : '○',
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 24,
            fontWeight: FontWeight.w300,
            fontFamily: 'CormorantGaramond',
            height: 1,
          ),
        ),
      ),
    );
  }
}
