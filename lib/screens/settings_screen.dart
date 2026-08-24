import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../l10n/east_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/appearance_preference_controller.dart';
import '../controllers/icloud_removal_controller.dart';
import '../controllers/locale_preference_controller.dart';
import '../localization/east_locale_registry.dart';
import '../controllers/sync_association_controller.dart';
import '../services/app_services.dart' as app_services;
import '../services/data_export_service.dart';
import '../services/purchase_service.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';
import '../widgets/east_back_button.dart';
import 'appearance_selection_screen.dart';
import 'keeper_screen.dart';
import 'language_selection_screen.dart';

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
    this.localePreferenceController,
    this.appearancePreferenceController,
  });

  final SettingsUrlLauncher? urlLauncher;
  final PurchaseService? purchaseService;
  final DataExportService? dataExportService;
  final LocalePreferenceController? localePreferenceController;
  final AppearancePreferenceController? appearancePreferenceController;

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
  late final LocalePreferenceController _fallbackLocalePreferenceController =
      LocalePreferenceController();
  late final AppearancePreferenceController
      _fallbackAppearancePreferenceController =
      AppearancePreferenceController();
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

  LocalePreferenceController get _localePreferenceController =>
      widget.localePreferenceController ?? _fallbackLocalePreferenceController;

  AppearancePreferenceController get _appearancePreferenceController =>
      widget.appearancePreferenceController ??
      _fallbackAppearancePreferenceController;

  String _localePreferenceLabel(AppLocalizations l10n) {
    final explicit = _localePreferenceController.explicitLocale;
    return explicit == null
        ? l10n.systemDefault
        : EastLocaleRegistry.definitionFor(explicit).nativeName;
  }

  String _appearancePreferenceLabel(AppLocalizations l10n) {
    switch (_appearancePreferenceController.mode) {
      case EastAppearanceMode.system:
        return l10n.systemDefault;
      case EastAppearanceMode.light:
        return l10n.light;
      case EastAppearanceMode.dark:
        return l10n.dark;
    }
  }

  // Shared by every Settings divider (see requirement: "all Settings
  // dividers use one shared value"). Derived from the approved muted-text
  // token rather than a duplicated raw RGB literal.
  Color _settingsDividerColor(BuildContext context) =>
      eastMutedTextColor(context).withValues(alpha: 0.30);

  PurchaseService get _purchaseService =>
      widget.purchaseService ?? app_services.purchaseService;

  /// Export My Data is free for everyone -- this getter never consults
  /// [_purchaseService]/entitlement state at all, exactly like
  /// [DataExportService] itself never does.
  DataExportService get _dataExportService =>
      widget.dataExportService ?? app_services.dataExportService;

  TextStyle eastStyle(
    double size, {
    Color? color,
  }) {
    return EastTypography.localized(
      context,
      size: size,
      color: color,
      height: 1.35,
      letterSpacing: 0.4,
    );
  }

  // Shared by every actionable Settings row so the pressed/hover/focus
  // state never paints a grey overlay: the row background stays stone in
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
                          style: eastStyle(21),
                        ),
                        if (showSubtitle) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: eastStyle(
                              15,
                              color: EastColors.of(context).secondary,
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
        alignment: AlignmentDirectional.centerEnd,
        child: Text(
          value,
          style: EastTypography.localized(
            context,
            size: 11,
            color: eastMutedTextColor(context),
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }

  Widget _settingsGroupDivider() {
    return Divider(
      color: _settingsDividerColor(context),
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
        backgroundColor: EastColors.of(context).surface,
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
    final l10n = eastLocalizations(context);
    setState(() {
      _restoreResultMessage = restoreStarted
          ? l10n.restoreRequestSent
          : _purchaseService.restoreNeedsRecovery
              ? l10n.restoreRecoveryPending
              : l10n.operationFailedRetry;
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
    final l10n = eastLocalizations(context);
    if (_restoreInProgress || _purchaseService.isLoading) {
      return '${l10n.restorePurchases}. ${l10n.preparing}';
    }
    return '${l10n.restorePurchases}. ${l10n.restoreBelongs}';
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
    showSettingsSnack(eastLocalizations(context).operationFailedRetry);
  }

  VoidCallback? get dataExportAction {
    if (_dataExportInProgress) return null;

    return exportDataFromSettings;
  }

  String get dataExportSemanticLabel {
    final l10n = eastLocalizations(context);
    if (_dataExportInProgress) {
      return '${l10n.exportMyData}. ${l10n.preparing}';
    }
    return '${l10n.exportMyData}. ${l10n.exportKeptAndReflections}';
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
    final l10n = eastLocalizations(context);
    if (_privacyPolicyLaunchInProgress) {
      return '${l10n.privacyPolicy}. ${l10n.opening}';
    }
    return '${l10n.privacyPolicy}. ${l10n.whatStaysPrivate}';
  }

  String get reachOutSemanticLabel {
    final l10n = eastLocalizations(context);
    if (_reachOutLaunchInProgress) {
      return '${l10n.reachOut}. ${l10n.opening}';
    }
    return '${l10n.reachOut}. ${l10n.thoughtsAndQuestions}';
  }

  String get eastProductionsSemanticLabel {
    final l10n = eastLocalizations(context);
    if (_eastProductionsLaunchInProgress) {
      return '${l10n.eastProductions}. ${l10n.opening}';
    }
    return '${l10n.eastProductions}. ${l10n.worldBeyondRitual}';
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
    final l10n = eastLocalizations(context);
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
            color: EastColors.of(context).overlay,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.restorePurchases,
                  textAlign: TextAlign.center,
                  style: eastStyle(28),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: eastStyle(15, color: EastColors.of(context).secondary),
                ),
                const SizedBox(height: 44),
                // Build 33 real-device Voice Control repair: the outer
                // `Semantics` must carry its own `onTap` -- see
                // `_removeFromICloudDecisionLabel` below for the full
                // explanation.
                Semantics(
                  button: true,
                  label: l10n.close,
                  onTap: _closeRestoreResult,
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
                        child: Center(
                          child: Text(
                            l10n.close.toUpperCase(),
                            style: EastTypography.localized(
                              context,
                              size: 11,
                              color: EastColors.of(context).ink,
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

  // Build 33 real-device Voice Control repair: this outer `Semantics`
  // previously had no `onTap` of its own -- `ExcludeSemantics` below
  // discards the inner `GestureDetector`'s handler, so the node had a
  // label and a `button` trait but no real `SemanticsAction.tap`. Voice
  // Control's activation relies on that action being present; VoiceOver's
  // label-then-double-tap path tolerated its absence. The same fix
  // applies to `_enableSyncDecisionLabel`, Reflection's
  // `_deleteDecisionLabel`, Journal's `_nameDecisionLabel`/name-action/
  // export-action, Home's `_favoriteLimitDecisionLabel`, and Kept's
  // Reflection-row actions -- see each site's own comment.
  Widget _removeFromICloudDecisionLabel(
    String label, {
    required VoidCallback onTap,
    required Color color,
  }) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Text(
                label,
                style: EastTypography.localized(
                  context,
                  size: 11,
                  color: color,
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
    final l10n = eastLocalizations(context);

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_removeFromICloudConfirmVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          opacity: _removeFromICloudConfirmVisible ? 1.0 : 0.0,
          child: Container(
            key: const ValueKey('settings-remove-from-icloud-confirm'),
            color: EastColors.of(context).overlay,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${l10n.removeFromIcloud}?',
                  textAlign: TextAlign.center,
                  style: eastStyle(28),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.removeIcloudLocalData,
                  textAlign: TextAlign.center,
                  style: eastStyle(15, color: EastColors.of(context).secondary),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.removeIcloudCloudData,
                  textAlign: TextAlign.center,
                  style: eastStyle(14, color: EastColors.of(context).secondary),
                ),
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _removeFromICloudDecisionLabel(
                      l10n.cancelUpper,
                      onTap: _cancelRemoveFromICloud,
                      color: EastColors.of(context).secondary,
                    ),
                    const SizedBox(width: 56),
                    _removeFromICloudDecisionLabel(
                      l10n.removeUpper,
                      onTap: _confirmRemoveFromICloud,
                      color: EastColors.of(context).ink,
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
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Text(
                label,
                style: EastTypography.localized(
                  context,
                  size: 11,
                  color: color,
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
    final l10n = eastLocalizations(context);

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_enableSyncOverlayVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          opacity: _enableSyncOverlayVisible ? 1.0 : 0.0,
          child: Container(
            key: const ValueKey('settings-enable-sync-confirm'),
            color: EastColors.of(context).overlay,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.enableIcloudQuestion,
                  textAlign: TextAlign.center,
                  style: eastStyle(28),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.enableIcloudData,
                  textAlign: TextAlign.center,
                  style: eastStyle(15, color: EastColors.of(context).secondary),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.dailyRitualOnDevice,
                  textAlign: TextAlign.center,
                  style: eastStyle(14, color: EastColors.of(context).secondary),
                ),
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _enableSyncDecisionLabel(
                      l10n.cancelUpper,
                      onTap: _cancelEnableSync,
                      color: EastColors.of(context).secondary,
                    ),
                    const SizedBox(width: 56),
                    _enableSyncDecisionLabel(
                      l10n.enableUpper,
                      onTap: _confirmEnableSync,
                      color: EastColors.of(context).ink,
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
      failureMessage: eastLocalizations(context).operationFailedRetry,
    );
  }

  Future<void> sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'hello@east.productions',
      queryParameters: <String, String>{
        'subject': eastLocalizations(context).supportEmailSubject,
      },
    );

    await _runExternalAction(
      inProgress: _reachOutLaunchInProgress,
      setInProgress: (value) {
        _reachOutLaunchInProgress = value;
      },
      uri: uri,
      mode: LaunchMode.platformDefault,
      failureMessage: eastLocalizations(context).operationFailedRetry,
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
      failureMessage: eastLocalizations(context).operationFailedRetry,
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

  Future<void> _openLanguage() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LanguageSelectionScreen(
          localePreferenceController: _localePreferenceController,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Mirrors [_openLanguage] exactly -- Appearance and Language are two
  /// fully independent preferences that happen to share the same "push a
  /// minimal picker, refresh this row on return" shape.
  Future<void> _openAppearance() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AppearanceSelectionScreen(
          appearancePreferenceController: _appearancePreferenceController,
        ),
      ),
    );
    if (mounted) setState(() {});
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
    final l10n = eastLocalizations(context);
    if (_cloudKitAssociationActionInProgress) return l10n.icloudEnabling;
    return _cloudKitAssociationStatus?.displayStatus ==
            SyncAssociationDisplayStatus.enabled
        ? l10n.icloudEnabled
        : l10n.icloudNotEnabled;
  }

  String get _cloudKitSyncSemanticLabel {
    final l10n = eastLocalizations(context);
    if (_cloudKitAssociationActionInProgress) {
      return '${l10n.icloudSync}. ${l10n.icloudEnabling}';
    }
    return '${l10n.icloudSync}. $_cloudKitSyncSubtitle';
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
      showSettingsSnack(eastLocalizations(context).operationFailedRetry);
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
    final l10n = eastLocalizations(context);
    if (_icloudRemovalActionInProgress) return l10n.icloudRemovalStarting;
    if (_icloudRemovalJustCompleted) return l10n.icloudRemovalCompleted;
    switch (_icloudRemovalStatus) {
      case ICloudRemovalDisplayStatus.pending:
        return l10n.icloudRemovalPending;
      case ICloudRemovalDisplayStatus.idle:
        return l10n.icloudRemovalIdle;
      case ICloudRemovalDisplayStatus.notApplicable:
      case null:
        return l10n.icloudRemovalNone;
    }
  }

  String get _icloudRemovalSemanticLabel {
    final l10n = eastLocalizations(context);
    if (_icloudRemovalActionInProgress) {
      return '${l10n.removeFromIcloud}. ${l10n.icloudRemovalStarting}';
    }
    return '${l10n.removeFromIcloud}. $_icloudRemovalSubtitle';
  }

  /// The ordinary explanatory subtitle is intentionally absent from the
  /// compact Settings layout. A live operation or observed outcome remains
  /// visible because it is status, not descriptive copy.
  bool get _showICloudRemovalStatus =>
      _icloudRemovalActionInProgress ||
      _icloudRemovalJustCompleted ||
      _icloudRemovalStatus == ICloudRemovalDisplayStatus.pending;

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
      showSettingsSnack(eastLocalizations(context).operationFailedRetry);
    }

    await _refreshICloudRemovalStatus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = eastLocalizations(context);
    return Scaffold(
      backgroundColor: EastColors.of(context).background,
      appBar: AppBar(
        backgroundColor: EastColors.of(context).background,
        foregroundColor: EastColors.of(context).ink,
        iconTheme: IconThemeData(
          color: EastColors.of(context).ink,
          size: 22,
          weight: 300,
        ),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: Navigator.canPop(context) ? const EastBackButton() : null,
        centerTitle: true,
        title: Semantics(
          header: true,
          child: Text(l10n.settings, style: eastStyle(24)),
        ),
      ),
      body: Stack(
        children: [
          IgnorePointer(
            ignoring: _restoreResultVisible ||
                _removeFromICloudConfirmVisible ||
                _enableSyncOverlayVisible,
            child: ExcludeSemantics(
              excluding: _restoreResultVisible ||
                  _removeFromICloudConfirmVisible ||
                  _enableSyncOverlayVisible,
              child: _settingsBody(context),
            ),
          ),
          _restoreResultOverlay(),
          _removeFromICloudOverlay(),
          _enableSyncOverlay(),
        ],
      ),
    );
  }

  Widget _settingsBody(BuildContext context) {
    final l10n = eastLocalizations(context);
    final localePreferenceLabel = _localePreferenceLabel(l10n);
    final appearancePreferenceLabel = _appearancePreferenceLabel(l10n);
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
                    // Group 1 — what you can own: Keeper and Restore
                    // Purchases. Every Settings title shares the same
                    // iCloud Sync typographic tier; subtitles retain their
                    // existing independent hierarchy.
                    settingsItem(
                      rowKey: const ValueKey('settings-keeper-row'),
                      title: l10n.keeper,
                      subtitle: l10n.supportCircle,
                      onTap: _openKeeper,
                    ),
                    const SizedBox(height: 6),
                    settingsItem(
                      rowKey: const ValueKey('settings-restore-purchases-row'),
                      title: l10n.restorePurchases,
                      subtitle: l10n.restoreBelongs,
                      semanticLabel: restoreSemanticLabel,
                      onTap: restoreAction,
                      showSubtitle: false,
                    ),

                    _settingsGroupDivider(),

                    // Group 2 — what holds your data: iCloud Sync's own
                    // state reads as a trailing ledger entry rather than a
                    // second subtitle line.
                    settingsItem(
                      rowKey: const ValueKey('settings-icloud-sync-row'),
                      title: l10n.icloudSync,
                      subtitle: _cloudKitSyncSubtitle,
                      showSubtitle: false,
                      semanticLabel: _cloudKitSyncSemanticLabel,
                      onTap: cloudKitSyncAction,
                      trailing: _settingsTrailingState(_cloudKitSyncSubtitle),
                    ),
                    const SizedBox(height: 12),
                    settingsItem(
                      rowKey: const ValueKey('settings-remove-from-icloud-row'),
                      title: l10n.removeFromIcloud,
                      subtitle: _icloudRemovalSubtitle,
                      semanticLabel: _icloudRemovalSemanticLabel,
                      onTap: icloudRemovalAction,
                      showSubtitle: _showICloudRemovalStatus,
                    ),
                    const SizedBox(height: 12),
                    settingsItem(
                      rowKey: const ValueKey('settings-export-data-row'),
                      title: l10n.exportMyData,
                      subtitle: _dataExportInProgress
                          ? l10n.preparing
                          : l10n.exportKeptAndReflections,
                      semanticLabel: dataExportSemanticLabel,
                      onTap: dataExportAction,
                    ),

                    _settingsGroupDivider(),

                    // Group 3 — language stays inside the main Settings
                    // area, before links that leave EAST.
                    settingsItem(
                      rowKey: const ValueKey('settings-language-row'),
                      title: l10n.language,
                      subtitle: localePreferenceLabel,
                      showSubtitle: false,
                      semanticLabel:
                          l10n.languageSettingSemantics(localePreferenceLabel),
                      onTap: _openLanguage,
                      trailing: _settingsTrailingState(localePreferenceLabel),
                    ),
                    const SizedBox(height: 24),
                    settingsItem(
                      rowKey: const ValueKey('settings-appearance-row'),
                      title: l10n.appearance,
                      subtitle: appearancePreferenceLabel,
                      showSubtitle: false,
                      semanticLabel: l10n.appearanceSettingSemantics(
                        appearancePreferenceLabel,
                      ),
                      onTap: _openAppearance,
                      trailing:
                          _settingsTrailingState(appearancePreferenceLabel),
                    ),

                    _settingsGroupDivider(),

                    // The world outside: a tight cluster of everything that
                    // leaves EAST., using the same title tier as every other
                    // Settings row.
                    settingsItem(
                      rowKey: const ValueKey('settings-east-productions-row'),
                      title: l10n.eastProductions,
                      subtitle: l10n.worldBeyondRitual,
                      semanticLabel: eastProductionsSemanticLabel,
                      onTap: eastProductionsAction,
                    ),
                    const SizedBox(height: 10),
                    settingsItem(
                      rowKey: const ValueKey('settings-privacy-policy-row'),
                      title: l10n.privacyPolicy,
                      subtitle: l10n.whatStaysPrivate,
                      semanticLabel: privacyPolicySemanticLabel,
                      onTap: privacyPolicyAction,
                      showSubtitle: false,
                    ),
                    const SizedBox(height: 10),
                    settingsItem(
                      rowKey: const ValueKey('settings-reach-out-row'),
                      title: l10n.reachOut,
                      subtitle: l10n.thoughtsAndQuestions,
                      semanticLabel: reachOutSemanticLabel,
                      onTap: reachOutAction,
                      showSubtitle: false,
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
