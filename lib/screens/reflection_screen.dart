import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/reflection_autosave_coordinator.dart';
import '../models/favorite_item.dart';
import '../l10n/east_localizations.dart';
import '../services/app_services.dart' as app_services;
import '../services/purchase_service.dart';
import '../services/saved_reflections_service.dart';
import '../services/wisdom_localization_resolver.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';
import '../utils/kept_diagnostics.dart';
import '../utils/reflection_prompt.dart';
import '../utils/reflection_text_policy.dart';
import '../widgets/east_back_button.dart';

class ReflectionScreen extends StatefulWidget {
  const ReflectionScreen({
    super.key,
    required this.item,
    required this.isKeeper,
    this.savedReflectionsService,
    this.purchaseService,
    this.autosaveDebounce = const Duration(milliseconds: 600),
  });

  final FavoriteItem item;
  final bool isKeeper;
  final SavedReflectionsService? savedReflectionsService;
  final PurchaseService? purchaseService;

  /// How long typing must pause before the current text is autosaved and
  /// (if it actually changed) becomes eligible for the next coalesced
  /// CloudKit sync attempt. Exposed for tests only — production always uses
  /// the default.
  final Duration autosaveDebounce;

  @override
  State<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends State<ReflectionScreen>
    with WidgetsBindingObserver {
  static const _wisdomPresentation = WisdomLocalizationResolver();
  // Real-device diagnostic pass (Phase 8/root-cause repair): every
  // `keptDiagnostic(...)` call in this file (pop-requested/flush-begin/
  // local-write-begin/success/limit-reached/failed/exhausted/pop-allowed/
  // pop-blocked) is a permanent, low-volume, privacy-safe failure/outcome
  // trace, per `lib/utils/kept_diagnostics.dart`'s own established
  // contract: debug-build-only, content-free (stage names, attempt
  // numbers, and exception *types* only -- never wisdom or Reflection
  // text). The higher-volume per-keystroke/per-revision investigation
  // instrumentation used to root-cause the false-success in-flight-Future
  // bug (text-change/debounce-scheduled/debounce-fired/persist-requested/
  // flush-awaiting-inflight/persist-complete, and the extra debug-only
  // authoritative-readback disk read) has been removed now that the bug
  // is fixed and verified. Persistence ownership now lives in
  // [ReflectionAutosaveCoordinator].
  late final TextEditingController _controller;
  late final SavedReflectionsService _service;
  late final PurchaseService _purchaseService;
  late final ReflectionAutosaveCoordinator _autosave;
  late final int _promptIndex;

  /// Phase 5G: resolved every `build()` (never cached), exactly like this
  /// screen's own wisdom presentation, so a locale change while this
  /// screen is open updates the shown prompt immediately. [_promptIndex]
  /// itself is the stable prompt *identity* -- fixed once in [initState],
  /// never re-derived -- so switching locale changes only which language
  /// this list is read in, never which prompt is selected.
  String get _prompt =>
      localizedReflectionPrompts(eastLocalizations(context))[_promptIndex];

  bool _deleteInProgress = false;
  bool _confirmingDelete = false;
  bool _popInProgress = false;
  double _backSwipeDistance = 0;

  static const double _backSwipeWidth = 24;
  static const double _backSwipeDistanceThreshold = 64;
  static const double _backSwipeVelocityThreshold = 700;

  bool get _isKeeper => _purchaseService.resolveKeeperAccess(
        unresolvedFallback: widget.isKeeper,
      );

  TextStyle _style(
    double size, {
    Color? color,
    double height = 1.38,
    double letterSpacing = 0.35,
  }) {
    return EastTypography.localized(
      context,
      size: size,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service =
        widget.savedReflectionsService ?? app_services.savedReflectionsService;
    _purchaseService = widget.purchaseService ?? app_services.purchaseService;
    _purchaseService.addListener(_onKeeperEntitlementChanged);
    // Deterministic per Phase 8: keyed on the occurrence's own `revealId`
    // (falling back to its always-present `id` only for pre-revealId
    // legacy Kept records) -- never on a persisted "chosen prompt" field,
    // and never re-derived from anything that can change across a save.
    _promptIndex =
        reflectionPromptIndexFor(widget.item.revealId ?? widget.item.id);
    _controller = TextEditingController(text: widget.item.reflection)
      ..addListener(_handleTextChanged);
    _autosave = ReflectionAutosaveCoordinator(
      debounce: widget.autosaveDebounce,
      readText: () => _controller.text,
      initialPersistedText: widget.item.reflection,
      persistText: _persistReflection,
      onLimitReached: () {
        if (mounted) {
          _showMessage(eastLocalizations(context).reflectionSaveFailed);
        }
      },
      onPersistFailure: () {
        if (mounted) {
          _showMessage(eastLocalizations(context).reflectionAutosaveFailed);
        }
      },
      onDiagnostic: keptDiagnostic,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _purchaseService.removeListener(_onKeeperEntitlementChanged);
    _autosave.dispose();
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    super.dispose();
  }

  void _onKeeperEntitlementChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_autosave.flush());
    }
  }

  void _handleTextChanged() {
    // Record the edit before scheduling the rebuild. This guarantees that the
    // rebuilt PopScope immediately protects the new, unpersisted revision.
    _autosave.handleTextChanged();

    // Only for the character counter below the field, which reads
    // `_controller.text` directly in `build()` -- the hint text itself
    // already hides/shows on its own the moment the field stops being
    // empty, with no state of this widget's own involved.
    if (mounted) setState(() {});
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: EastColors.of(context).surface,
          content: Text(message, style: _style(17)),
        ),
      );
  }

  Future<ReflectionPersistResult> _persistReflection(String text) async {
    final result = await _service.saveReflection(
      itemId: widget.item.id,
      reflection: text,
      isKeeper: _isKeeper,
    );
    return result.reflectionLimitReached
        ? ReflectionPersistResult.limitReached
        : ReflectionPersistResult.saved;
  }

  // Approved Ritual direction: the decision to delete is a full-field
  // takeover in the ritual voice, on the horizon, centred -- never a
  // default system alert. Cancel/Delete meaning, the underlying deletion
  // call, and the persisted wisdom being kept are all unchanged from the
  // prior AlertDialog implementation; only the presentation is replaced.
  void _delete() {
    if (_deleteInProgress || !widget.item.hasReflection) return;
    setState(() {
      _confirmingDelete = true;
    });
  }

  void _cancelDelete() {
    if (!mounted) return;
    setState(() {
      _confirmingDelete = false;
    });
  }

  Future<void> _confirmDelete() async {
    if (_deleteInProgress || !mounted) return;

    _autosave.cancelPending();
    setState(() {
      _deleteInProgress = true;
    });

    try {
      await _service.deleteReflection(itemId: widget.item.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleteInProgress = false;
        _confirmingDelete = false;
      });
      _showMessage(eastLocalizations(context).reflectionDeleteFailed);
    }
  }

  Widget _deleteDecisionLabel(
    String label, {
    required VoidCallback? onTap,
    required Color color,
  }) {
    // Build 33 real-device Voice Control repair: the outer `Semantics`
    // must carry its own `onTap` -- `ExcludeSemantics` below discards the
    // inner `GestureDetector`'s, so without this the node has a label and
    // a `button` trait but no real `SemanticsAction.tap`, which Voice
    // Control's activation relies on.
    return Semantics(
      button: true,
      enabled: onTap != null,
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

  Widget _deleteDecisionOverlay() {
    final l10n = eastLocalizations(context);
    if (!_confirmingDelete) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_confirmingDelete,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          opacity: _confirmingDelete ? 1.0 : 0.0,
          child: Container(
            key: const ValueKey('reflection-delete-decision'),
            color: EastColors.of(context).overlay,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.deleteReflectionQuestion,
                  textAlign: TextAlign.center,
                  style: _style(28, height: 1.1),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.reflectionDeleteExplanation,
                  textAlign: TextAlign.center,
                  style: _style(
                    15,
                    color: EastColors.of(context).secondary,
                    height: 1.45,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _deleteDecisionLabel(
                      l10n.cancelUpper,
                      onTap: _deleteInProgress ? null : _cancelDelete,
                      color: EastColors.of(context).secondary,
                    ),
                    const SizedBox(width: 56),
                    _deleteDecisionLabel(
                      l10n.deleteUpper,
                      onTap: _deleteInProgress
                          ? null
                          : () => unawaited(_confirmDelete()),
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

  /// [PopScope] continues to veto an immediate route pop so a same-frame edit
  /// can never slip past persistence. A narrow iOS leading-edge gesture below
  /// requests the exact same flush-before-pop path as the visible back button.
  ///
  /// Root-cause repair: a flush that genuinely, persistently fails (every
  /// retry exhausted -- a real on-device disk/file-protection failure, not
  /// a transient blip) must never let the pop through. Popping anyway would
  /// silently discard text the user can no longer recover, directly
  /// contradicting the already-shown "It will try again as you keep
  /// writing." message from [_attemptPersist]. Staying put keeps that
  /// promise true: the text remains in the field, and the very next
  /// keystroke (or another back attempt) is a fresh, real retry.
  Future<void> _handlePopAttempt() async {
    if (_popInProgress) return;
    _popInProgress = true;
    try {
      final flushed = await _autosave.flush();
      if (!mounted) return;
      if (!flushed) {
        keptDiagnostic('reflection-screen: pop-blocked');
        return;
      }
      keptDiagnostic('reflection-screen: pop-allowed');
      Navigator.pop(context);
    } finally {
      _popInProgress = false;
    }
  }

  double _backSwipeDirectionFactor(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  void _handleBackSwipeStart(DragStartDetails details) {
    _backSwipeDistance = 0;
  }

  void _handleBackSwipeUpdate(
    BuildContext context,
    DragUpdateDetails details,
  ) {
    final forwardDelta = details.delta.dx * _backSwipeDirectionFactor(context);
    _backSwipeDistance =
        (_backSwipeDistance + forwardDelta).clamp(0, double.infinity);
  }

  void _handleBackSwipeEnd(BuildContext context, DragEndDetails details) {
    final forwardVelocity = details.velocity.pixelsPerSecond.dx *
        _backSwipeDirectionFactor(context);
    final shouldPop = _backSwipeDistance >= _backSwipeDistanceThreshold ||
        forwardVelocity >= _backSwipeVelocityThreshold;
    _backSwipeDistance = 0;
    if (!shouldPop || _popInProgress) return;
    keptDiagnostic('reflection-screen: pop-requested-by-edge-swipe');
    unawaited(_handlePopAttempt());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = eastLocalizations(context);
    final characterCount = ReflectionTextPolicy.length(_controller.text);
    const counterThreshold = 900;

    final hasUnpersistedChanges = _autosave.hasUnpersistedChanges;

    return PopScope(
      // A clean Reflection must keep iOS's real interactive back gesture.
      // Only a genuinely unpersisted edit needs the guarded custom edge
      // gesture below so its local write can finish before the route pops.
      canPop: !hasUnpersistedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        keptDiagnostic('reflection-screen: pop-requested');
        unawaited(_handlePopAttempt());
      },
      child: Scaffold(
        backgroundColor: EastColors.of(context).background,
        appBar: AppBar(
          backgroundColor: EastColors.of(context).background,
          foregroundColor: EastColors.of(context).ink,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          // The visible Back control always uses the durable exit path. This
          // also closes the same-frame gap where text has changed but the
          // PopScope rebuild has not yet reached the element tree.
          leading: Navigator.canPop(context)
              ? EastBackButton(onPressed: () => unawaited(_handlePopAttempt()))
              : null,
          title: Text(l10n.reflection, style: _style(24)),
          actions: [
            if (widget.item.hasReflection)
              Semantics(
                button: true,
                enabled: !_deleteInProgress,
                label: l10n.deleteReflection,
                onTap: _deleteInProgress ? null : _delete,
                child: ExcludeSemantics(
                  child: TextButton(
                    onPressed: _deleteInProgress ? null : _delete,
                    child: Text(l10n.delete, style: _style(16)),
                  ),
                ),
              ),
          ],
        ),
        body: Stack(
          children: [
            SafeArea(
              top: false,
              child: IgnorePointer(
                ignoring: _confirmingDelete,
                child: ExcludeSemantics(
                  excluding: _confirmingDelete,
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      16,
                      24,
                      28 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _wisdomPresentation.resolveItem(
                            widget.item,
                            Localizations.localeOf(context),
                          ),
                          key: const ValueKey('reflection-associated-wisdom'),
                          style: _style(24, height: 1.46),
                        ),
                        const SizedBox(height: 42),
                        // A stable, always-present accessible name for this
                        // field: `MergeSemantics` folds the TextField's own
                        // native text-input semantics (live value, editing
                        // actions, and the framework's built-in
                        // maxLength-driven character-count announcement)
                        // together with this label, so the field's purpose
                        // is announced whether or not it is empty --
                        // `hintText` alone is not a reliable accessible name
                        // once a value has been entered.
                        MergeSemantics(
                          child: Semantics(
                            label: eastLocalizations(context).reflection,
                            child: TextField(
                              key: const ValueKey('reflection-writing-area'),
                              controller: _controller,
                              enabled: !_deleteInProgress,
                              autofocus: false,
                              keyboardType: TextInputType.multiline,
                              minLines: 7,
                              maxLines: null,
                              maxLength: SavedReflectionsService
                                  .maximumReflectionLength,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(
                                  SavedReflectionsService
                                      .maximumReflectionLength,
                                ),
                              ],
                              style: _style(20, height: 1.45),
                              cursorColor: EastColors.of(context).ink,
                              decoration: InputDecoration(
                                hintText: _prompt,
                                hintStyle: _style(
                                  20,
                                  color: EastColors.of(context).hint,
                                  height: 1.45,
                                ),
                                // The TextField's own `maxLength` already
                                // gives VoiceOver a native, non-obtrusive
                                // current/maximum character announcement
                                // (Flutter wires this into the field's own
                                // Semantics automatically). This visible
                                // counter is a sighted-only convenience near
                                // the limit; excluding it from semantics
                                // avoids a redundant duplicate announcement.
                                counter: ExcludeSemantics(
                                  child: characterCount >= counterThreshold
                                      ? Text(
                                          '$characterCount/'
                                          '${SavedReflectionsService.maximumReflectionLength}',
                                          style: _style(
                                            13,
                                            color: EastColors.of(context)
                                                .secondary,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: eastMutedTextColor(context),
                                    width: 0.5,
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: eastMutedTextColor(context),
                                    width: 0.5,
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
            ),
            if (Theme.of(context).platform == TargetPlatform.iOS &&
                hasUnpersistedChanges)
              PositionedDirectional(
                key: const ValueKey('reflection-back-swipe-region'),
                start: 0,
                top: 0,
                bottom: 0,
                width: _backSwipeWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  excludeFromSemantics: true,
                  onHorizontalDragStart: _handleBackSwipeStart,
                  onHorizontalDragUpdate: (details) =>
                      _handleBackSwipeUpdate(context, details),
                  onHorizontalDragEnd: (details) =>
                      _handleBackSwipeEnd(context, details),
                  onHorizontalDragCancel: () {
                    _backSwipeDistance = 0;
                  },
                ),
              ),
            _deleteDecisionOverlay(),
          ],
        ),
      ),
    );
  }
}
