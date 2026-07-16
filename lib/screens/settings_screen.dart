import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_services.dart' as app_services;
import '../services/purchase_service.dart';
import 'keeper_screen.dart';

typedef SettingsUrlLauncher = Future<bool> Function(
  Uri uri, {
  required LaunchMode mode,
});

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.urlLauncher,
    this.purchaseService,
  });

  final SettingsUrlLauncher? urlLauncher;
  final PurchaseService? purchaseService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _keeperNavigationInProgress = false;
  bool _privacyPolicyLaunchInProgress = false;
  bool _reachOutLaunchInProgress = false;
  bool _restoreInProgress = false;

  PurchaseService get _purchaseService =>
      widget.purchaseService ?? app_services.purchaseService;

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
    String? semanticLabel,
  }) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel ?? '$title. $subtitle',
      onTap: onTap,
      child: ExcludeSemantics(
        child: SizedBox(
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
        ),
      ),
    );
  }

  Future<bool> _launchExternal(
    Uri uri, {
    required LaunchMode mode,
  }) {
    final launcher = widget.urlLauncher;
    if (launcher != null) {
      return launcher(uri, mode: mode);
    }

    return launchUrl(uri, mode: mode);
  }

  void showSettingsSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF111111),
        duration: const Duration(milliseconds: 1600),
        content: Text(
          message,
          style: eastStyle(17),
        ),
      ),
    );
  }

  Future<void> _runExternalAction({
    required bool inProgress,
    required void Function(bool value) setInProgress,
    required Uri uri,
    required LaunchMode mode,
    required String failureMessage,
  }) async {
    if (inProgress || !mounted) return;

    setState(() {
      setInProgress(true);
    });

    try {
      final launched = await _launchExternal(uri, mode: mode);
      if (!mounted) return;

      if (!launched) {
        showSettingsSnack(failureMessage);
      }
    } catch (_) {
      if (!mounted) return;

      showSettingsSnack(failureMessage);
    } finally {
      if (mounted) {
        setState(() {
          setInProgress(false);
        });
      }
    }
  }

  Future<void> restorePurchasesFromSettings() async {
    if (_restoreInProgress || _purchaseService.isLoading || !mounted) return;

    setState(() {
      _restoreInProgress = true;
    });

    var restoreStarted = false;
    try {
      restoreStarted = await _purchaseService.restorePurchases();
    } catch (_) {
      restoreStarted = false;
    } finally {
      if (mounted) {
        setState(() {
          _restoreInProgress = false;
        });
      }
    }

    if (!mounted) return;
    showInfoDialog(
      context,
      "Restore Purchases",
      restoreStarted
          ? "Restore request sent. Keeper access will update automatically."
          : _purchaseService.restoreNeedsRecovery
              ? "A previous restore is still being reconciled. Keeper access will update automatically; reopen EAST. before trying again."
              : "Restore is not available right now. Please try again shortly.",
    );
  }

  VoidCallback? get restoreAction {
    if (_restoreInProgress || _purchaseService.isLoading) return null;

    return restorePurchasesFromSettings;
  }

  String get restoreSemanticLabel {
    if (_restoreInProgress || _purchaseService.isLoading) {
      return 'Restore Purchases. Restore in progress.';
    }

    return 'Restore Purchases. Restore what belongs with you.';
  }

  VoidCallback? get privacyPolicyAction {
    if (_privacyPolicyLaunchInProgress) return null;

    return openPrivacyPolicy;
  }

  VoidCallback? get reachOutAction {
    if (_reachOutLaunchInProgress) return null;

    return sendEmail;
  }

  String get privacyPolicySemanticLabel {
    if (_privacyPolicyLaunchInProgress) {
      return 'Privacy Policy. Opening.';
    }

    return 'Privacy Policy. What stays private.';
  }

  String get reachOutSemanticLabel {
    if (_reachOutLaunchInProgress) {
      return 'Reach Out. Opening.';
    }

    return 'Reach Out. For thoughts and questions.';
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

    await _runExternalAction(
      inProgress: _privacyPolicyLaunchInProgress,
      setInProgress: (value) {
        _privacyPolicyLaunchInProgress = value;
      },
      uri: uri,
      mode: LaunchMode.externalApplication,
      failureMessage: "Privacy Policy could not be opened.",
    );
  }

  Future<void> sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'dailywisdomeast@gmail.com',
      query: 'subject=EAST. Support',
    );

    await _runExternalAction(
      inProgress: _reachOutLaunchInProgress,
      setInProgress: (value) {
        _reachOutLaunchInProgress = value;
      },
      uri: uri,
      mode: LaunchMode.platformDefault,
      failureMessage: "Reach Out could not be opened.",
    );
  }

  Future<void> _openKeeper() async {
    if (_keeperNavigationInProgress || !mounted) return;

    _keeperNavigationInProgress = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const KeeperScreen(),
        ),
      );
    } finally {
      _keeperNavigationInProgress = false;
    }
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
                        onTap: _openKeeper,
                      ),
                      const Divider(
                        color: Colors.white24,
                        thickness: 0.5,
                      ),
                      settingsItem(
                        title: "Restore Purchases",
                        subtitle: "Restore what belongs with you.",
                        semanticLabel: restoreSemanticLabel,
                        onTap: restoreAction,
                      ),
                      const Divider(
                        color: Colors.white24,
                        thickness: 0.5,
                      ),
                      settingsItem(
                        title: "Privacy Policy",
                        subtitle: "What stays private.",
                        semanticLabel: privacyPolicySemanticLabel,
                        onTap: privacyPolicyAction,
                      ),
                      const Divider(
                        color: Colors.white24,
                        thickness: 0.5,
                      ),
                      settingsItem(
                        title: "Reach Out",
                        subtitle: "For thoughts and questions.",
                        semanticLabel: reachOutSemanticLabel,
                        onTap: reachOutAction,
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
