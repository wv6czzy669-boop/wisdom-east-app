import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/icloud_removal_controller.dart';
import '../controllers/sync_association_controller.dart';
import '../services/app_services.dart' as app_services;
import '../services/data_export_service.dart';
import '../services/purchase_service.dart';
import '../theme/muted_text_color.dart';
import '../widgets/east_back_button.dart';
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
    this.icloudRemovalController,
    this.dataExportService,
  });

  final SettingsUrlLauncher? urlLauncher;
  final PurchaseService? purchaseService;
  final DataExportService? dataExportService;

  /// Build 26 Phase 4G: injectable only for tests -- production always uses
  /// the single [app_services.cloudKitAssociationController] instance (see
  /// [_cloudKitAssociationController]), never a second, disconnected
  /// controller. Both this field and the production global it falls back to
  /// are nullable: isolated widget tests may mount [SettingsScreen] before
  /// any composition root has run, and this screen must still mount safely
  /// in that case (see [_cloudKitAssociationController]).
  final SyncAssociationController? cloudKitAssociationController;

  /// Build 26 Phase 5 (final slice): injectable only for tests -- production
  /// always uses the single [app_services.icloudRemovalController] instance
  /// (see [_icloudRemovalController]), never a second, disconnected
  /// controller. Both this field and the production global it falls back to
  /// are nullable, for the exact same reason
  /// [cloudKitAssociationController] already is.
  final ICloudRemovalController? icloudRemovalController;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _keeperNavigationInProgress = false;
  bool _privacyPolicyLaunchInProgress = false;
  bool _reachOutLaunchInProgress = false;
  bool _restoreInProgress = false;
  // Settings visual repair: the Restore Purchases result is now the same
  // full-field EAST takeover as Delete Reflection/Journal Name (see
  // `_restoreResultOverlay`) instead of a rounded `AlertDialog`. State only
  // -- `restorePurchasesFromSettings` below still computes the exact same
  // outcome-dependent message it always did.
  bool _restoreResultVisible = false;
  String? _restoreResultMessage;
  bool _eastProductionsLaunchInProgress = false;
  bool _dataExportInProgress = false;

  // Build 26 Phase 4G: the explicit one-time iCloud association row. `null`
  // until the first [_refreshSyncAssociationStatus] call resolves --
  // rendered as "Not enabled"/non-actionable in the meantime, the same safe
  // fail-closed default [SyncAssociationController] itself returns for
  // every non-`associationRequired` status.
  SyncAssociationCheckResult? _cloudKitAssociationStatus;
  bool _cloudKitAssociationActionInProgress = false;
  bool _enableSyncOverlayVisible = false;

  // Build 26 Phase 5 (final slice): the explicit "Remove from iCloud" row.
  // `null` until the first [_refreshICloudRemovalStatus] call resolves --
  // rendered as "Nothing to remove."/non-actionable in the meantime, the
  // same safe fail-closed default [ICloudRemovalController] itself returns
  // for every unexpected-failure case.
  ICloudRemovalDisplayStatus? _icloudRemovalStatus;
  bool _icloudRemovalActionInProgress = false;
  bool _removeFromICloudConfirmVisible = false;

  /// `true` only once this screen instance has itself observed the removal
  /// transition from [ICloudRemovalDisplayStatus.pending] to anything else
  /// -- never fabricated from a persisted flag, never true merely because no
  /// transaction happens to be pending. See [_refreshICloudRemovalStatus].
  bool _icloudRemovalJustCompleted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSyncAssociationStatus());
    unawaited(_refreshICloudRemovalStatus());
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

  /// `null` whenever neither an injected test controller nor the production
  /// composition-root global (`app_services.icloudRemovalController`) is
  /// available yet -- mirrors [_cloudKitAssociationController]'s own
  /// identical reasoning exactly. This screen never touches
  /// `SyncPersistenceStore`/`CloudKitSyncRuntimeCoordinator` directly, never
  /// constructs a second, disconnected controller, and never treats a
  /// missing controller as anything other than "nothing to remove yet" --
  /// see [_refreshICloudRemovalStatus] and [_beginICloudRemoval].
  ICloudRemovalController? get _icloudRemovalController =>
      widget.icloudRemovalController ?? app_services.icloudRemovalController;

  // Shared by every Settings divider (see requirement: "all Settings
  // dividers use one shared value"). Derived from the approved muted-text
  // token rather than a duplicated raw RGB literal.
  final Color _settingsDividerColor = eastMutedTextColor.withValues(
    alpha: 0.30,
  );

  PurchaseService get _purchaseService =>
      widget.purchaseService ?? app_services.purchaseService;

  /// Export My Data is free for everyone -- this getter never consults
  /// [_purchaseService]/entitlement state at all, exactly like
  /// [DataExportService] itself never does.
  DataExportService get _dataExportService =>
      widget.dataExportService ?? app_services.dataExportService;

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
    // Build 26 Phase 6 (approved EAST Settings direction): Restore
    // Purchases sits as a subordinate row directly under Keeper -- title
    // only, one tier smaller -- rather than a full-weight row of its own.
    // Content/semantics/behavior are entirely unchanged; only the title's
    // own size differs from the standard 21pt.
    double titleSize = 21,
    // Approved direction: iCloud Sync's state reads as a ledger entry on
    // the trailing margin, not a second subtitle line -- every other row
    // keeps its explanatory subtitle.
    bool showSubtitle = true,
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
                          style: eastStyle(titleSize),
                        ),
                        if (showSubtitle) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: eastStyle(
                              15,
                              color: const Color(0x91FFFFFF),
                            ),
                          ),
                        ],
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

  // Approved EAST Settings direction: a state marker on the trailing
  // margin (e.g. iCloud Sync's ENABLED / NOT ENABLED), read like a ledger
  // entry -- the tracked label tier the rest of the app already uses.
  Widget _settingsTrailingState(String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 96),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          value,
          style: const TextStyle(
            color: eastMutedTextColor,
            fontSize: 11,
            fontWeight: FontWeight.w300,
            fontFamily: 'CormorantGaramond',
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }

  Widget _settingsGroupDivider() {
    return Divider(
      color: _settingsDividerColor,
      thickness: 0.5,
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
    setState(() {
      _restoreResultMessage = restoreStarted
          ? "Restore request sent. Keeper access will update automatically."
          : _purchaseService.restoreNeedsRecovery
              ? "A previous restore is still being reconciled. Keeper access will update automatically; reopen EAST. before trying again."
              : "Restore is not available right now. Please try again shortly.";
      _restoreResultVisible = true;
    });
  }

  void _closeRestoreResult() {
    if (!mounted) return;
    setState(() {
      _restoreResultVisible = false;
    });
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

  /// Free for everyone -- no Keeper check of any kind. Generates both
  /// export files entirely on-device and presents the native Share Sheet;
  /// a failure here (generation or presentation) shows one quiet, generic
  /// message and never mutates Kept/Reflection/sync state, which this path
  /// never writes to in the first place.
  Future<void> exportDataFromSettings() async {
    if (_dataExportInProgress || !mounted) return;

    setState(() {
      _dataExportInProgress = true;
    });

    bool succeeded;
    try {
      succeeded = await _dataExportService.exportAndShare();
    } catch (_) {
      succeeded = false;
    } finally {
      if (mounted) {
        setState(() {
          _dataExportInProgress = false;
        });
      }
    }

    if (!mounted || succeeded) return;
    showSettingsSnack('Your data could not be exported. Please try again.');
  }

  VoidCallback? get dataExportAction {
    if (_dataExportInProgress) return null;

    return exportDataFromSettings;
  }

  String get dataExportSemanticLabel {
    if (_dataExportInProgress) {
      return 'Export My Data. Preparing.';
    }

    return 'Export My Data. Take your Kept wisdoms and Reflections with '
        'you.';
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

  /// Settings visual repair: the Restore Purchases result takeover -- same
  /// visual system as Delete Reflection (`reflection_screen.dart`'s
  /// `_deleteDecisionOverlay`) and Journal Name (`journal_screen.dart`'s
  /// `_nameDecisionOverlay`): Settings stays mounted and strongly dimmed
  /// behind it, no `AlertDialog`, no card, no rounded rectangle, no border,
  /// no shadow. `message` is always the exact outcome-dependent copy
  /// `restorePurchasesFromSettings` already computed -- this widget never
  /// decides what happened, only how it is shown.
  Widget _restoreResultOverlay() {
    if (!_restoreResultVisible) return const SizedBox.shrink();
    final message = _restoreResultMessage ?? '';

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_restoreResultVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          opacity: _restoreResultVisible ? 1.0 : 0.0,
          child: Container(
            key: const ValueKey('settings-restore-result'),
            color: const Color(0xFF040404).withValues(alpha: 0.94),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Restore Purchases',
                  textAlign: TextAlign.center,
                  style: eastStyle(28),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: eastStyle(15, color: const Color(0xB3FFFFFF)),
                ),
                const SizedBox(height: 44),
                Semantics(
                  button: true,
                  label: 'Close',
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      key: const ValueKey('settings-restore-result-close'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _closeRestoreResult,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        child: const Center(
                          child: Text(
                            'CLOSE',
                            style: TextStyle(
                              color: Color(0xFFF4F0E8),
                              fontSize: 11,
                              fontWeight: FontWeight.w300,
                              fontFamily: 'CormorantGaramond',
                              letterSpacing: 3.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _removeFromICloudDecisionLabel(
    String label, {
    required VoidCallback onTap,
    required Color color,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w300,
                  fontFamily: 'CormorantGaramond',
                  letterSpacing: 3.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Settings visual repair: the "Remove from iCloud" confirmation takeover
  /// -- same visual system as Restore Purchases above, Delete Reflection
  /// (`reflection_screen.dart`'s `_deleteDecisionOverlay`), Journal Name
  /// (`journal_screen.dart`'s `_nameDecisionOverlay`), and Kept Limit
  /// (`home_screen.dart`'s `_favoriteLimitOverlay`): Settings stays mounted
  /// and strongly dimmed behind it, no `AlertDialog`, no card, no rounded
  /// rectangle, no border, no shadow. Replaces the previous
  /// `showGeneralDialog`-based confirmation; the removal/deletion flow
  /// itself (`_cancelRemoveFromICloud`/`_confirmRemoveFromICloud` ->
  /// `_beginICloudRemoval` -> `ICloudRemovalController.beginRemoval`) is
  /// unchanged, only the presentation. REMOVE stays visually within the
  /// family (no filled button) but reads as the more decisive action via
  /// full warm-white -- exactly how Delete Reflection's own DELETE label
  /// already reads as destructive without a red fill.
  Widget _removeFromICloudOverlay() {
    if (!_removeFromICloudConfirmVisible) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_removeFromICloudConfirmVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          opacity: _removeFromICloudConfirmVisible ? 1.0 : 0.0,
          child: Container(
            key: const ValueKey('settings-remove-from-icloud-confirm'),
            color: const Color(0xFF040404).withValues(alpha: 0.94),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Remove from iCloud?",
                  textAlign: TextAlign.center,
                  style: eastStyle(28),
                ),
                const SizedBox(height: 16),
                Text(
                  "Your Kept wisdoms and Reflections will remain on this "
                  "iPhone.",
                  textAlign: TextAlign.center,
                  style: eastStyle(15, color: const Color(0xB3FFFFFF)),
                ),
                const SizedBox(height: 8),
                Text(
                  "Their iCloud copies will be removed, and iCloud Sync "
                  "will turn off.",
                  textAlign: TextAlign.center,
                  style: eastStyle(14, color: const Color(0x91FFFFFF)),
                ),
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _removeFromICloudDecisionLabel(
                      'CANCEL',
                      onTap: _cancelRemoveFromICloud,
                      color: const Color(0xB3FFFFFF),
                    ),
                    const SizedBox(width: 56),
                    _removeFromICloudDecisionLabel(
                      'REMOVE',
                      onTap: _confirmRemoveFromICloud,
                      color: const Color(0xFFF4F0E8),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _enableSyncDecisionLabel(
    String label, {
    required VoidCallback onTap,
    required Color color,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w300,
                  fontFamily: 'CormorantGaramond',
                  letterSpacing: 3.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Settings visual repair: the "Enable iCloud Sync" confirmation takeover
  /// -- same visual system as Restore Purchases, Remove from iCloud
  /// (above), Delete Reflection (`reflection_screen.dart`'s
  /// `_deleteDecisionOverlay`), Journal Name (`journal_screen.dart`'s
  /// `_nameDecisionOverlay`), and Kept Limit (`home_screen.dart`'s
  /// `_favoriteLimitOverlay`): Settings stays mounted and strongly dimmed
  /// behind it, no `AlertDialog`, no card, no rounded rectangle, no border,
  /// no shadow. Replaces the previous `showDialog`-based confirmation; the
  /// explicit-consent gating and enable flow itself
  /// (`_cancelEnableSync`/`_confirmEnableSync` -> `_enableSyncAssociation`
  /// -> `SyncAssociationController.enableSync`) is unchanged, only the
  /// presentation.
  Widget _enableSyncOverlay() {
    if (!_enableSyncOverlayVisible) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_enableSyncOverlayVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          opacity: _enableSyncOverlayVisible ? 1.0 : 0.0,
          child: Container(
            key: const ValueKey('settings-enable-sync-confirm'),
            color: const Color(0xFF040404).withValues(alpha: 0.94),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Enable iCloud Sync?",
                  textAlign: TextAlign.center,
                  style: eastStyle(28),
                ),
                const SizedBox(height: 16),
                Text(
                  "Your Kept wisdoms and Reflections will be stored in your "
                  "private iCloud database and kept in sync across your "
                  "devices.",
                  textAlign: TextAlign.center,
                  style: eastStyle(15, color: const Color(0xB3FFFFFF)),
                ),
                const SizedBox(height: 8),
                Text(
                  "Your daily ritual timing stays on this device.",
                  textAlign: TextAlign.center,
                  style: eastStyle(14, color: const Color(0x91FFFFFF)),
                ),
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _enableSyncDecisionLabel(
                      'CANCEL',
                      onTap: _cancelEnableSync,
                      color: const Color(0xB3FFFFFF),
                    ),
                    const SizedBox(width: 56),
                    _enableSyncDecisionLabel(
                      'ENABLE',
                      onTap: _confirmEnableSync,
                      color: const Color(0xFFF4F0E8),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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

  void _showEnableICloudSyncSheet() {
    if (_cloudKitAssociationActionInProgress || !mounted) return;

    // Matches the other approved EAST full-field overlays: the guard is
    // read via `cloudKitSyncAction`/`_enableSyncOverlayVisible` together
    // (the row's own `IgnorePointer` beneath the overlay), so a second tap
    // while this confirmation is showing can never open a duplicate one.
    setState(() {
      _enableSyncOverlayVisible = true;
    });
  }

  void _cancelEnableSync() {
    if (!mounted) return;
    setState(() {
      _enableSyncOverlayVisible = false;
    });
  }

  void _confirmEnableSync() {
    if (!mounted) return;
    setState(() {
      _enableSyncOverlayVisible = false;
    });
    unawaited(_enableSyncAssociation());
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

  // -----------------------------------------------------------------------
  // Build 26 Phase 5 (final slice): the explicit "Remove from iCloud" row.
  //
  // This screen never constructs CloudKit transport, never knows a
  // fingerprint, epoch, or record name, never touches persistence files
  // directly, and never implements any part of the deletion state machine
  // itself -- every decision is made by [ICloudRemovalController], which
  // itself only ever calls the existing, already-audited
  // `SyncPersistenceStore.beginDeletionTransaction` entry point and, on
  // success, the existing runtime policy owner
  // (`CloudKitSyncRuntimeCoordinator.requestSync`, via a plain callback --
  // see `app_services.dart`'s wiring). Every further step -- the epoch
  // barrier, the remote purge, the remote-empty verification, and the local
  // finalize/detach -- is driven entirely by the already-implemented and
  // already-tested Phase 5 slice 2/3 pipeline; nothing here duplicates any
  // part of it.
  //
  // No controller available yet (see [_icloudRemovalController]) is treated
  // exactly like [ICloudRemovalDisplayStatus.notApplicable] -- the same
  // safe, non-actionable default the controller itself already returns for
  // every other unexpected-failure state. This never fabricates a
  // controller and never touches CloudKit/native code merely because
  // Settings mounted.
  //
  // While a removal is [ICloudRemovalDisplayStatus.pending], tapping the row
  // never starts a second deletion transaction and never re-shows the
  // confirmation prompt -- it only re-reads already-durable state (the real
  // Phase 5 runtime pipeline keeps driving the transaction forward entirely
  // on its own, independent of whether this screen is even open). This is a
  // deliberate, calm, explicit "check again," never a silent background
  // poll -- consistent with this screen's existing discipline of only ever
  // refreshing state in direct response to something the user did.
  // -----------------------------------------------------------------------

  String get _icloudRemovalSubtitle {
    if (_icloudRemovalActionInProgress) return "Starting…";
    if (_icloudRemovalJustCompleted) return "Removed from iCloud.";
    switch (_icloudRemovalStatus) {
      case ICloudRemovalDisplayStatus.pending:
        return "Removal pending. EAST. will finish when iCloud is available.";
      case ICloudRemovalDisplayStatus.idle:
        return "Remove your iCloud copies.";
      case ICloudRemovalDisplayStatus.notApplicable:
      case null:
        return "Nothing to remove.";
    }
  }

  String get _icloudRemovalSemanticLabel {
    if (_icloudRemovalActionInProgress) {
      return 'Remove from iCloud. Starting.';
    }
    return 'Remove from iCloud. $_icloudRemovalSubtitle';
  }

  /// `null` (disabling the row) whenever an action is already in flight, or
  /// whenever no controller is available yet or the status is
  /// [ICloudRemovalDisplayStatus.notApplicable] (nothing to remove and
  /// nothing pending to check on). Actionable for both
  /// [ICloudRemovalDisplayStatus.idle] (shows the confirmation prompt) and
  /// [ICloudRemovalDisplayStatus.pending] (re-reads state only -- see this
  /// section's own doc comment).
  VoidCallback? get icloudRemovalAction {
    if (_icloudRemovalActionInProgress) return null;
    switch (_icloudRemovalStatus) {
      case ICloudRemovalDisplayStatus.idle:
        return _showRemoveFromICloudSheet;
      case ICloudRemovalDisplayStatus.pending:
        return () => unawaited(_refreshICloudRemovalStatus());
      case ICloudRemovalDisplayStatus.notApplicable:
      case null:
        return null;
    }
  }

  Future<void> _refreshICloudRemovalStatus() async {
    final controller = _icloudRemovalController;
    final result = controller == null
        ? const ICloudRemovalCheckResult(
            displayStatus: ICloudRemovalDisplayStatus.notApplicable,
          )
        : await controller.checkStatus();
    if (!mounted) return;

    final wasPending =
        _icloudRemovalStatus == ICloudRemovalDisplayStatus.pending;
    final isPending =
        result.displayStatus == ICloudRemovalDisplayStatus.pending;

    setState(() {
      _icloudRemovalStatus = result.displayStatus;
      if (wasPending && !isPending) {
        // This screen instance itself watched the durable transaction go
        // from pending to gone -- the one, and only, condition under which
        // the "Removed from iCloud." confirmation is ever shown.
        _icloudRemovalJustCompleted = true;
      } else if (isPending) {
        // Still (or newly) pending -- any previously-shown confirmation is
        // stale.
        _icloudRemovalJustCompleted = false;
      }
    });
  }

  void _showRemoveFromICloudSheet() {
    if (_icloudRemovalActionInProgress || !mounted) return;

    // Final UI repair: the duplicate-action guard is set HERE -- before the
    // confirmation overlay is even shown -- not merely once the user
    // confirms. `icloudRemovalAction` reads this exact flag, so a second
    // tap arriving at any point from here through `_beginICloudRemoval`'s
    // own resolution can never open a second confirmation overlay and can
    // never start a second attempt of any kind.
    setState(() {
      _icloudRemovalActionInProgress = true;
      _removeFromICloudConfirmVisible = true;
    });
  }

  void _cancelRemoveFromICloud() {
    if (!mounted) return;

    // Cancel -- nothing was started, so a later, genuinely new attempt
    // must remain possible.
    setState(() {
      _removeFromICloudConfirmVisible = false;
      _icloudRemovalActionInProgress = false;
    });
  }

  void _confirmRemoveFromICloud() {
    if (!mounted) return;
    setState(() {
      _removeFromICloudConfirmVisible = false;
    });
    unawaited(_beginICloudRemoval());
  }

  Future<void> _beginICloudRemoval() async {
    if (!mounted) return;

    // `_icloudRemovalActionInProgress` is already `true` here -- set by
    // `_showRemoveFromICloudSheet` before the confirmation dialog was ever
    // shown (see its own comment). This method's only remaining
    // responsibility for that flag is resetting it once the begin attempt
    // itself has fully resolved, below.
    ICloudRemovalBeginOutcome outcome;
    try {
      final controller = _icloudRemovalController;
      outcome = controller == null
          ? ICloudRemovalBeginOutcome.failed
          : await controller.beginRemoval();
    } catch (_) {
      outcome = ICloudRemovalBeginOutcome.failed;
    }

    if (!mounted) return;

    setState(() {
      _icloudRemovalActionInProgress = false;
    });

    if (outcome == ICloudRemovalBeginOutcome.failed) {
      showSettingsSnack(
        "Remove from iCloud could not be started. Please try again.",
      );
    }

    await _refreshICloudRemovalStatus();
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
        leading: Navigator.canPop(context) ? const EastBackButton() : null,
      ),
      body: Stack(
        children: [
          IgnorePointer(
            ignoring: _restoreResultVisible ||
                _removeFromICloudConfirmVisible ||
                _enableSyncOverlayVisible,
            child: _settingsBody(context),
          ),
          _restoreResultOverlay(),
          _removeFromICloudOverlay(),
          _enableSyncOverlay(),
        ],
      ),
    );
  }

  Widget _settingsBody(BuildContext context) {
    return SafeArea(
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
                      const SizedBox(height: 40),

                      // Group 1 — what you can own: Keeper, with Restore
                      // Purchases sitting directly beneath it as a
                      // subordinate, findable row (never a full-weight row
                      // of its own).
                      settingsItem(
                        rowKey: const ValueKey('settings-keeper-row'),
                        title: "Keeper",
                        subtitle: "Support the circle, keep what stays.",
                        onTap: _openKeeper,
                      ),
                      const SizedBox(height: 6),
                      settingsItem(
                        rowKey:
                            const ValueKey('settings-restore-purchases-row'),
                        title: "Restore Purchases",
                        subtitle: "Restore what belongs with you.",
                        semanticLabel: restoreSemanticLabel,
                        onTap: restoreAction,
                        titleSize: 15,
                      ),

                      _settingsGroupDivider(),

                      // Group 2 — what holds your data: iCloud Sync's own
                      // state reads as a trailing ledger entry rather than a
                      // second subtitle line.
                      settingsItem(
                        rowKey: const ValueKey('settings-icloud-sync-row'),
                        title: "iCloud Sync",
                        subtitle: _cloudKitSyncSubtitle,
                        showSubtitle: false,
                        semanticLabel: _cloudKitSyncSemanticLabel,
                        onTap: cloudKitSyncAction,
                        trailing: _settingsTrailingState(_cloudKitSyncSubtitle),
                      ),
                      const SizedBox(height: 24),
                      settingsItem(
                        rowKey:
                            const ValueKey('settings-remove-from-icloud-row'),
                        title: "Remove from iCloud",
                        subtitle: _icloudRemovalSubtitle,
                        semanticLabel: _icloudRemovalSemanticLabel,
                        onTap: icloudRemovalAction,
                      ),
                      const SizedBox(height: 24),
                      settingsItem(
                        rowKey: const ValueKey('settings-export-data-row'),
                        title: "Export My Data",
                        subtitle: _dataExportInProgress
                            ? "Preparing…"
                            : "Take your Kept wisdoms and Reflections with "
                                "you.",
                        semanticLabel: dataExportSemanticLabel,
                        onTap: dataExportAction,
                      ),

                      _settingsGroupDivider(),

                      // Group 3 — the world outside: a tight cluster, one
                      // tier quieter, of everything that leaves EAST.
                      settingsItem(
                        rowKey: const ValueKey('settings-east-productions-row'),
                        title: "EAST. Productions",
                        subtitle: "The world beyond the ritual.",
                        semanticLabel: eastProductionsSemanticLabel,
                        onTap: eastProductionsAction,
                        titleSize: 17,
                      ),
                      const SizedBox(height: 10),
                      settingsItem(
                        rowKey: const ValueKey('settings-privacy-policy-row'),
                        title: "Privacy Policy",
                        subtitle: "What stays private.",
                        semanticLabel: privacyPolicySemanticLabel,
                        onTap: privacyPolicyAction,
                        titleSize: 17,
                      ),
                      const SizedBox(height: 10),
                      settingsItem(
                        rowKey: const ValueKey('settings-reach-out-row'),
                        title: "Reach Out",
                        subtitle: "For thoughts and questions.",
                        semanticLabel: reachOutSemanticLabel,
                        onTap: reachOutAction,
                        titleSize: 17,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
  }
}
