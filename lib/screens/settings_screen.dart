import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_services.dart' as app_services;
import '../services/purchase_service.dart';
import '../services/wisdom_notification_service.dart';
import '../theme/muted_text_color.dart';
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
    this.notificationService,
  });

  final SettingsUrlLauncher? urlLauncher;
  final PurchaseService? purchaseService;

  // Injectable so widget tests can exercise the Daily Reminder row without
  // touching real platform notification/permission APIs.
  final WisdomNotificationService? notificationService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _keeperNavigationInProgress = false;
  bool _privacyPolicyLaunchInProgress = false;
  bool _reachOutLaunchInProgress = false;
  bool _restoreInProgress = false;
  bool _eastProductionsLaunchInProgress = false;
  bool _dailyReminderOn = false;
  bool _dailyReminderBusy = false;

  // Shared by every Settings divider (see requirement: "all Settings
  // dividers use one shared value"). Derived from the approved muted-text
  // token rather than a duplicated raw RGB literal.
  final Color _settingsDividerColor = eastMutedTextColor.withValues(
    alpha: 0.30,
  );

  PurchaseService get _purchaseService =>
      widget.purchaseService ?? app_services.purchaseService;

  WisdomNotificationService get _notificationService =>
      widget.notificationService ?? app_services.wisdomNotificationService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshDailyReminderStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only ever refresh the real, current status here — never request
    // permission automatically on resume. This is what makes returning
    // from the OS notification settings (after a denied-permission
    // redirect) reflect the true authorization without any extra tap, and
    // what makes an externally-revoked permission read as OFF rather than
    // staying stale.
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshDailyReminderStatus());
    }
  }

  Future<void> _refreshDailyReminderStatus() async {
    final on = await _notificationService.isDailyReminderOn();
    if (!mounted) return;
    setState(() {
      _dailyReminderOn = on;
    });
  }

  String get _dailyReminderStatusText => _dailyReminderOn ? 'ON' : 'OFF';

  String get dailyReminderSemanticLabel {
    if (_dailyReminderBusy) {
      return 'Daily Reminder. Updating.';
    }
    return 'Daily Reminder. Return when the silence opens again. '
        'Currently ${_dailyReminderOn ? 'on' : 'off'}.';
  }

  VoidCallback? get dailyReminderAction {
    if (_dailyReminderBusy) return null;
    return _toggleDailyReminder;
  }

  Future<void> _toggleDailyReminder() async {
    if (_dailyReminderBusy || !mounted) return;

    setState(() {
      _dailyReminderBusy = true;
    });

    try {
      if (_dailyReminderOn) {
        await _notificationService.disableDailyReminder();
        if (!mounted) return;
        setState(() {
          _dailyReminderOn = false;
        });
        return;
      }

      final status = await _notificationService.authorizationStatus();
      switch (status) {
        case WisdomNotificationAuthorization.notDetermined:
        case WisdomNotificationAuthorization.authorized:
          final on = await _notificationService.enableDailyReminder();
          if (!mounted) return;
          setState(() {
            _dailyReminderOn = on;
          });
        case WisdomNotificationAuthorization.denied:
        case WisdomNotificationAuthorization.unavailable:
          // Cannot take effect at the OS level from here: express the
          // intent to enable by opening the app's own notification
          // settings page, with no app-owned explanatory dialog. This goes
          // through the notification service's native
          // `openNotificationSettings()` bridge (backed by the official
          // `UIApplication.openNotificationSettingsURLString`), not
          // url_launcher — url_launcher remains reserved for the
          // externally-linked rows (EAST. Productions, Objects, Privacy
          // Policy, Reach Out). The real status is re-read on resume (see
          // `didChangeAppLifecycleState`) once the user returns.
          await _notificationService.openNotificationSettings();
      }
    } finally {
      if (mounted) {
        setState(() {
          _dailyReminderBusy = false;
        });
      }
    }
  }

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

  // Shared by every actionable Settings row so the pressed/hover/focus
  // state never paints a grey overlay: the row background stays black in
  // every interaction state (idle, pressed, focused, hovered, disabled,
  // in-flight). Defined once rather than repeated per row.
  static const WidgetStateProperty<Color?> _noOverlayColor =
      WidgetStatePropertyAll(Colors.transparent);

  Widget settingsItem({
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    String? semanticLabel,
    Key? rowKey,
    Widget? trailing,
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
            key: rowKey,
            onTap: onTap,
            overlayColor: _noOverlayColor,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 17,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing,
                  ],
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

  VoidCallback? get eastProductionsAction {
    if (_eastProductionsLaunchInProgress) return null;

    return openEastProductions;
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

  String get eastProductionsSemanticLabel {
    if (_eastProductionsLaunchInProgress) {
      return 'EAST. Productions. Opening.';
    }

    return 'EAST. Productions. The world beyond the ritual.';
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
      path: 'hello@east.productions',
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

  Future<void> openEastProductions() async {
    final uri = Uri.parse('https://east.productions');

    await _runExternalAction(
      inProgress: _eastProductionsLaunchInProgress,
      setInProgress: (value) {
        _eastProductionsLaunchInProgress = value;
      },
      uri: uri,
      mode: LaunchMode.externalApplication,
      failureMessage: "EAST. Productions could not be opened.",
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
                          color: eastMutedTextColor,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Divider(
                        color: _settingsDividerColor,
                        thickness: 0.5,
                      ),
                      settingsItem(
                        rowKey: const ValueKey('settings-keeper-row'),
                        title: "Keeper",
                        subtitle: "Support the circle, keep what stays.",
                        onTap: _openKeeper,
                      ),
                      Divider(
                        color: _settingsDividerColor,
                        thickness: 0.5,
                      ),
                      settingsItem(
                        rowKey:
                            const ValueKey('settings-restore-purchases-row'),
                        title: "Restore Purchases",
                        subtitle: "Restore what belongs with you.",
                        semanticLabel: restoreSemanticLabel,
                        onTap: restoreAction,
                      ),
                      Divider(
                        color: _settingsDividerColor,
                        thickness: 0.5,
                      ),
                      settingsItem(
                        rowKey: const ValueKey('settings-daily-reminder-row'),
                        title: "Daily Reminder",
                        subtitle: "Return when the silence opens again.",
                        semanticLabel: dailyReminderSemanticLabel,
                        onTap: dailyReminderAction,
                        trailing: Text(
                          _dailyReminderStatusText,
                          style: eastStyle(
                            15,
                            color: _dailyReminderOn
                                ? const Color(0xFFF4F0E8)
                                : eastMutedTextColor,
                          ),
                        ),
                      ),
                      Divider(
                        color: _settingsDividerColor,
                        thickness: 0.5,
                      ),
                      settingsItem(
                        rowKey: const ValueKey('settings-east-productions-row'),
                        title: "EAST. Productions",
                        subtitle: "The world beyond the ritual.",
                        semanticLabel: eastProductionsSemanticLabel,
                        onTap: eastProductionsAction,
                      ),
                      Divider(
                        color: _settingsDividerColor,
                        thickness: 0.5,
                      ),
                      settingsItem(
                        rowKey: const ValueKey('settings-privacy-policy-row'),
                        title: "Privacy Policy",
                        subtitle: "What stays private.",
                        semanticLabel: privacyPolicySemanticLabel,
                        onTap: privacyPolicyAction,
                      ),
                      Divider(
                        color: _settingsDividerColor,
                        thickness: 0.5,
                      ),
                      settingsItem(
                        rowKey: const ValueKey('settings-reach-out-row'),
                        title: "Reach Out",
                        subtitle: "For thoughts and questions.",
                        semanticLabel: reachOutSemanticLabel,
                        onTap: reachOutAction,
                      ),
                      Divider(
                        color: _settingsDividerColor,
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
