import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/sync_association_controller.dart';
import '../services/app_services.dart' as app_services;
import '../services/purchase_service.dart';
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
    this.cloudKitAssociationController,
  });

  final SettingsUrlLauncher? urlLauncher;
  final PurchaseService? purchaseService;

  /// Build 26 Phase 4G: injectable only for tests -- production always uses
  /// the single [app_services.cloudKitAssociationController] instance (see
  /// [_cloudKitAssociationController]), never a second, disconnected
  /// controller. Both this field and the production global it falls back to
  /// are nullable: isolated widget tests may mount [SettingsScreen] before
  /// any composition root has run, and this screen must still mount safely
  /// in that case (see [_cloudKitAssociationController]).
  final SyncAssociationController? cloudKitAssociationController;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _keeperNavigationInProgress = false;
  bool _privacyPolicyLaunchInProgress = false;
  bool _reachOutLaunchInProgress = false;
  bool _restoreInProgress = false;
  bool _eastProductionsLaunchInProgress = false;

  // Build 26 Phase 4G: the explicit one-time iCloud association row. `null`
  // until the first [_refreshSyncAssociationStatus] call resolves --
  // rendered as "Not enabled"/non-actionable in the meantime, the same safe
  // fail-closed default [SyncAssociationController] itself returns for
  // every non-`associationRequired` status.
  SyncAssociationCheckResult? _cloudKitAssociationStatus;
  bool _cloudKitAssociationActionInProgress = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSyncAssociationStatus());
  }

  /// `null` whenever neither an injected test controller nor the production
  /// composition-root global (`app_services.cloudKitAssociationController`)
  /// is available yet -- i.e. this screen was mounted before
  /// `initializeKeptStorage()` ever ran (every existing isolated Home/
  /// Settings navigation widget test does exactly this). This screen never
  /// calls `initializeKeptStorage()` itself, never constructs a second,
  /// disconnected controller, and never treats a missing controller as
  /// anything other than "not enabled yet" -- see
  /// [_refreshSyncAssociationStatus] and [_enableSyncAssociation].
  SyncAssociationController? get _cloudKitAssociationController =>
      widget.cloudKitAssociationController ??
      app_services.cloudKitAssociationController;

  // Shared by every Settings divider (see requirement: "all Settings
  // dividers use one shared value"). Derived from the approved muted-text
  // token rather than a duplicated raw RGB literal.
  final Color _settingsDividerColor = eastMutedTextColor.withValues(
    alpha: 0.30,
  );

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
      'https://east.productions/app/privacy',
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

  // -----------------------------------------------------------------------
  // Build 26 Phase 4G: explicit one-time iCloud association.
  //
  // This screen never constructs CloudKit transport, never knows a
  // fingerprint or record name, never touches persistence files, and never
  // implements any part of the bootstrap state machine itself -- every
  // decision is made by [SyncAssociationController], which itself only
  // ever calls the existing, already-audited
  // `KeptSyncBootstrapCoordinator.evaluateAssociation`/`.authorizeAssociation`
  // pair and, on success, the existing runtime policy owner
  // (`CloudKitSyncRuntimeCoordinator.requestSync`, via a plain callback --
  // see `app_services.dart`'s wiring). Disabling/deleting synced data is
  // explicitly out of scope for this row (a later export/delete/recovery
  // phase owns that).
  //
  // No controller available yet (see [_cloudKitAssociationController]) is
  // treated exactly like [SyncAssociationDisplayStatus.notEnabled] with
  // `requiresExplicitConsent: false` -- the same safe, non-actionable
  // default the controller itself already returns for every other
  // not-yet-resolved state. This never calls `initializeKeptStorage()`,
  // never fabricates a controller, and never touches CloudKit/native code
  // merely because Settings mounted.
  // -----------------------------------------------------------------------

  static const SyncAssociationCheckResult _cloudKitAssociationUnavailable =
      SyncAssociationCheckResult(
    displayStatus: SyncAssociationDisplayStatus.notEnabled,
    requiresExplicitConsent: false,
  );

  Future<void> _refreshSyncAssociationStatus() async {
    final controller = _cloudKitAssociationController;
    final result = controller == null
        ? _cloudKitAssociationUnavailable
        : await controller.checkStatus();
    if (!mounted) return;
    setState(() {
      _cloudKitAssociationStatus = result;
    });
  }

  String get _cloudKitSyncSubtitle {
    if (_cloudKitAssociationActionInProgress) return "Enabling…";
    return _cloudKitAssociationStatus?.displayStatus ==
            SyncAssociationDisplayStatus.enabled
        ? "Enabled"
        : "Not enabled";
  }

  String get _cloudKitSyncSemanticLabel {
    if (_cloudKitAssociationActionInProgress) {
      return 'iCloud Sync. Enabling.';
    }
    return 'iCloud Sync. $_cloudKitSyncSubtitle';
  }

  /// `null` (disabling the row, exactly like [restoreAction] et al. do)
  /// whenever an action is already in flight, or whenever the most recent
  /// status check did not report [SyncAssociationCheckResult
  /// .requiresExplicitConsent] -- requirement 1: never show an unnecessary
  /// authorization prompt.
  VoidCallback? get cloudKitSyncAction {
    if (_cloudKitAssociationActionInProgress) return null;
    if (_cloudKitAssociationStatus?.requiresExplicitConsent != true) {
      return null;
    }
    return _showEnableICloudSyncSheet;
  }

  Future<void> _showEnableICloudSyncSheet() async {
    if (_cloudKitAssociationActionInProgress || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: Text(
            "Enable iCloud Sync?",
            style: eastStyle(21),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Your Kept wisdoms and Reflections will be stored in your "
                "private iCloud database and kept in sync across your "
                "devices.",
                style: eastStyle(16, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Text(
                "Your daily ritual timing stays on this device.",
                style: eastStyle(14, color: const Color(0x91FFFFFF)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text("Cancel", style: eastStyle(16)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text("Enable", style: eastStyle(16)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _enableSyncAssociation();
    }
  }

  Future<void> _enableSyncAssociation() async {
    if (_cloudKitAssociationActionInProgress || !mounted) return;

    setState(() {
      _cloudKitAssociationActionInProgress = true;
    });

    SyncAssociationEnableOutcome outcome;
    try {
      final controller = _cloudKitAssociationController;
      outcome = controller == null
          ? SyncAssociationEnableOutcome.failed
          : await controller.enableSync();
    } catch (_) {
      outcome = SyncAssociationEnableOutcome.failed;
    }

    if (!mounted) return;

    setState(() {
      _cloudKitAssociationActionInProgress = false;
    });

    if (outcome == SyncAssociationEnableOutcome.failed) {
      showSettingsSnack("iCloud Sync could not be enabled. Please try again.");
    }

    await _refreshSyncAssociationStatus();
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
                        rowKey: const ValueKey('settings-icloud-sync-row'),
                        title: "iCloud Sync",
                        subtitle: _cloudKitSyncSubtitle,
                        semanticLabel: _cloudKitSyncSemanticLabel,
                        onTap: cloudKitSyncAction,
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
