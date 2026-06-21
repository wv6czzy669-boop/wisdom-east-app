import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_services.dart';
import 'keeper_screen.dart';

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
      fontFamily: 'CormorantGaramond',
      height: 1.35,
      letterSpacing: 0.4,
    );
  }

  Widget settingsItem({
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white10,
        highlightColor: Colors.white10,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 17,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
                  color: const Color(0x91FFFFFF),
                ),
              ),
            ],
          ),
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
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              key: const ValueKey('settings-scroll'),
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 36,
                ),
                child: Align(
                  key: const ValueKey('settings-content'),
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'EAST.',
                        textAlign: TextAlign.center,
                        style: eastStyle(27),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Where silence speaks.',
                        textAlign: TextAlign.center,
                        style: eastStyle(
                          17,
                          color: const Color(0x91FFFFFF),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Divider(
                        color: Colors.white24,
                        thickness: 0.5,
                      ),
                      settingsItem(
                        title: "Keeper",
                        subtitle: "Support the circle, keep what stays.",
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
                        title: "Restore Purchases",
                        subtitle: "Restore what belongs with you.",
                        onTap: () async {
                          if (purchaseService.isLoading) return;

                          var restoreStarted = false;
                          try {
                            restoreStarted =
                                await purchaseService.restorePurchases();
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
                        title: "Privacy Policy",
                        subtitle: "What stays private.",
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
                        title: "Reach Out",
                        subtitle: "For thoughts and questions.",
                        onTap: sendEmail,
                      ),
                      const Divider(
                        color: Colors.white24,
                        thickness: 0.5,
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
