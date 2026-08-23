import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../controllers/latest_request_guard.dart';
import '../l10n/east_localizations.dart';
import '../models/favorite_item.dart';
import '../services/app_services.dart' as app_services;
import '../services/purchase_service.dart';
import '../services/saved_reflections_service.dart';
import '../services/wisdom_localization_resolver.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';
import '../utils/kept_diagnostics.dart';
import '../utils/date_formatter.dart';
import '../widgets/east_back_button.dart';
import 'journal_screen.dart';
import 'keeper_screen.dart';
import 'reflection_screen.dart';

class SavedReflectionsScreen extends StatefulWidget {
  const SavedReflectionsScreen({
    super.key,
    required this.reflections,
    this.isKeeper = false,
    this.savedReflectionsService,
    this.purchaseService,
  });

  final List<FavoriteItem> reflections;
  final bool isKeeper;
  final SavedReflectionsService? savedReflectionsService;
  final PurchaseService? purchaseService;

  @override
  State<SavedReflectionsScreen> createState() => _SavedReflectionsScreenState();
}

class _SavedReflectionsScreenState extends State<SavedReflectionsScreen> {
  static const _wisdomPresentation = WisdomLocalizationResolver();
  late List<FavoriteItem> _items;
  late final SavedReflectionsService _service;
  late final PurchaseService _purchaseService;
  bool _navigationInProgress = false;

  /// Build 26 Phase 4H-6: guards the silent background reload triggered by
  /// [app_services.keptStateRevisionNotifier] (an incoming CloudKit sync
  /// applying new/changed Kept or Reflection data while this screen is
  /// already mounted) -- a dedicated instance, never shared with any other
  /// async operation on this screen, so a rapid second incoming
  /// notification always wins over a still-in-flight earlier reload.
  final _incomingKeptRefreshGuard = LatestRequestGuard();

  bool get _isKeeper => widget.isKeeper || _purchaseService.isKeeper;

  TextStyle _style(
    double size, {
    Color? color,
    double height = 1.35,
    double letterSpacing = 0.3,
  }) {
    return EastTypography.localized(
      context,
      size: size,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  TextStyle get _statusStyle => _style(
        13,
        color: eastMutedTextColor(context),
        letterSpacing: 1.15,
      );

  @override
  void initState() {
    super.initState();
    _items = List<FavoriteItem>.from(widget.reflections);
    _service =
        widget.savedReflectionsService ?? app_services.savedReflectionsService;
    _purchaseService = widget.purchaseService ?? app_services.purchaseService;
    // Build 26 Phase 4H-6: subscribe to the neutral incoming-Kept-state
    // signal for as long as this screen stays mounted -- mirrors the
    // existing `app_services.purchaseService.addListener(...)` pattern
    // `home_screen.dart` already uses for its own cross-cutting listener.
    app_services.keptStateRevisionNotifier.addListener(_onKeptStateChanged);
  }

  @override
  void dispose() {
    app_services.keptStateRevisionNotifier.removeListener(_onKeptStateChanged);
    _incomingKeptRefreshGuard.invalidate();
    super.dispose();
  }

  /// Build 26 Phase 4H-6: invoked synchronously by
  /// [app_services.keptStateRevisionNotifier] only after an incoming
  /// CloudKit sync has durably applied a Kept/Reflection content change
  /// while this screen is mounted. Never shows a spinner, never shows a
  /// snackbar, never resets scroll position or navigation -- this is a
  /// silent background refresh, deliberately distinct from [_reload]'s own
  /// user-initiated navigation completion (which does surface a
  /// failure message, since that reload follows a user action).
  void _onKeptStateChanged() {
    if (!mounted) return;
    final generation = _incomingKeptRefreshGuard.begin();
    unawaited(_reloadForIncomingStateChange(generation));
  }

  Future<void> _reloadForIncomingStateChange(int generation) async {
    final List<FavoriteItem> loaded;
    try {
      loaded = await _service.load();
    } catch (_) {
      // A failed silent background refresh must never interrupt the user
      // (no snackbar) -- leave `_items` exactly as it already was. A
      // future incoming batch (or the user's own next explicit action)
      // will retry.
      return;
    }
    // Both checks matter: `mounted` guards against a dispose that happened
    // while `_service.load()` was in flight; `isCurrent` guards against a
    // newer incoming notification's own reload having already started (and
    // possibly already finished) after this one began -- this call must
    // never overwrite a fresher result with a stale one.
    if (!mounted || !_incomingKeptRefreshGuard.isCurrent(generation)) return;
    setState(() {
      _items = loaded;
    });
  }

  String _displayDate(FavoriteItem item) => formatLocalizedDateOrLegacy(
        timestamp: item.keptAt == null ? null : DateTime.tryParse(item.keptAt!),
        legacyDisplay: item.date,
        localeTag: localeTagForDate(Localizations.localeOf(context)),
      );

  String _displayWisdom(FavoriteItem item) =>
      _wisdomPresentation.resolveItem(item, Localizations.localeOf(context));

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

  // Real-device diagnostic pass: a permanent, low-volume, content-free
  // outcome/failure trace (see the matching note in
  // `reflection_screen.dart`) -- no wisdom/reflection text, only stage
  // names and counts.
  Future<void> _reload() async {
    keptDiagnostic('kept-screen: reload-begin');
    try {
      final loaded = await _service.load();
      if (!mounted) return;
      setState(() {
        _items = loaded;
      });
      keptDiagnostic('kept-screen: reload-end itemCount=${loaded.length}');
    } catch (_) {
      keptDiagnostic('kept-screen: reload-failed');
      _showMessage(eastLocalizations(context).wisdomCouldNotBeRemoved);
    }
  }

  Future<void> _openReflection(FavoriteItem item) async {
    if (_navigationInProgress || !mounted) return;

    _navigationInProgress = true;
    try {
      if (!item.hasReflection &&
          !_isKeeper &&
          _items.where((candidate) => candidate.hasReflection).length >=
              SavedReflectionsService.freeReflectionLimit) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (context) => const KeeperScreen(),
          ),
        );
        return;
      }

      await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (context) => ReflectionScreen(
            item: item,
            isKeeper: _isKeeper,
            savedReflectionsService: _service,
          ),
        ),
      );
      if (!mounted) return;
      await _reload();
      // Real-device diagnostic pass: a permanent, low-volume, content-free
      // outcome check -- whether the exact occurrence just opened for
      // reflection is present in the freshly-reloaded list, and whether it
      // now carries a reflection. Never affects reload/navigation
      // behavior; a swallowed lookup failure here is diagnostic-only.
      if (kDebugMode) {
        final match = _items.where((i) => i.id == item.id).toList();
        final found = match.isNotEmpty;
        final hasReflection = found && match.first.hasReflection;
        keptDiagnostic(
          'kept-screen: post-reflection-reload matchingRecordFound=$found '
          'matchingRecordHasReflection=$hasReflection',
        );
      }
    } finally {
      _navigationInProgress = false;
    }
  }

  /// Opens the dedicated Journal screen for both Free and Keeper. Journal
  /// is openable by everyone; only its "Take it with you" export action is
  /// Keeper-gated,
  /// entirely inside [JournalScreen]. The empty-content case is handled
  /// inside [JournalScreen] itself.
  Future<void> _openJournal() async {
    if (_navigationInProgress || !mounted) return;

    _navigationInProgress = true;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) =>
              JournalScreen(items: _items, isKeeper: _isKeeper),
        ),
      );
    } finally {
      _navigationInProgress = false;
    }
  }

  Future<void> _deleteItem(FavoriteItem item) async {
    try {
      final removed = await _service.remove(itemId: item.id);
      if (!mounted || removed == null) return;
      setState(() {
        _items = removed.items;
      });
    } catch (_) {
      _showMessage(
        eastLocalizations(context).wisdomCouldNotBeRemoved,
      );
    }
  }

  // Build 33 real-device Voice Control repair: `itemNumber` (1-based,
  // screen-order -- see `itemBuilder`'s `index`) makes each row's
  // Reflection action uniquely addressable by name ("Open Reflection,
  // item 2"), since the wisdom text itself must never be the spoken
  // control name and dates are not guaranteed unique. The static date/
  // wisdom content remains unnumbered and VoiceOver-readable via ordinary
  // Text auto-semantics -- only the actionable control's name changes.
  Widget _status(FavoriteItem item, int itemNumber) {
    final l10n = eastLocalizations(context);
    if (!item.hasReflection) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(l10n.keptUpper, style: _statusStyle),
        ),
      );
    }

    // Build 33 real-device Voice Control repair: the outer `Semantics`
    // previously carried a `label` and `button: true` but no `onTap` of
    // its own -- the only tap handler lived on the `GestureDetector`
    // wrapped in `ExcludeSemantics` below, so no `SemanticsAction.tap`
    // ever reached the platform. VoiceOver's read-the-label-and-double-
    // tap path tolerated this; Voice Control's "Tap <name>"/"Show Names"
    // -- which activates via the real semantics action -- did not. Fixed
    // by mirroring the same `onTap` on the outer node, matching the
    // pattern already used correctly elsewhere (Settings' `settingsItem`,
    // Language/Appearance rows, `EastBackButton`).
    //
    // `container: true` is also new here: `_keptItem`'s own outer
    // `Semantics(customSemanticsActions: {...})` has no `container` of
    // its own, so it merges every un-boundaried descendant's label into
    // one combined string (date + status + wisdom) -- without a boundary
    // here, this control's own unique per-row label would get swallowed
    // into that same merged string, defeating the per-row uniqueness
    // below. `container: true` keeps this control's accessible name
    // exactly what it claims to be, and correspondingly keeps the row's
    // static content (date/status/wisdom) as the one coherent,
    // un-cluttered content node the audit called for.
    return Semantics(
      container: true,
      button: true,
      label: l10n.openReflectionNumbered(itemNumber),
      onTap: () => _openReflection(item),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openReflection(item),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(l10n.reflectedUpper, style: _statusStyle),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keptItem(FavoriteItem item, int index) {
    final itemNumber = index + 1;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: eastLocalizations(context).delete): () {
          unawaited(_deleteItem(item));
        },
      },
      child: _KeptSwipeToDeleteRow(
        key: ValueKey('kept-${item.id}'),
        itemId: item.id,
        deleteLabelStyle: _statusStyle,
        deleteLabel: eastLocalizations(context).deleteUpper,
        onDelete: () => unawaited(_deleteItem(item)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_displayDate(item),
                style: _style(
                  15,
                  color: eastMutedTextColor(context),
                  letterSpacing: 0.4,
                )),
            const SizedBox(height: 5),
            _status(item, itemNumber),
            const SizedBox(height: 7),
            Text(_displayWisdom(item), style: _style(24)),
            if (!item.hasReflection) ...[
              const SizedBox(height: 12),
              // `container: true` -- see `_status` above for why this is
              // needed to keep this control's per-row label from merging
              // into the row's static date/status/wisdom content.
              Semantics(
                container: true,
                button: true,
                label: eastLocalizations(context).addReflectionNumbered(
                  itemNumber,
                ),
                onTap: () => _openReflection(item),
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openReflection(item),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          eastLocalizations(context).addReflectionUpper,
                          style: _statusStyle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = eastLocalizations(context);
    final visibleItems = _items.reversed.toList(growable: false);

    return Scaffold(
      key: const ValueKey('kept-screen-root'),
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
        elevation: 0,
        leading: Navigator.canPop(context) ? const EastBackButton() : null,
        centerTitle: true,
        title: Text(l10n.kept, style: _style(24)),
        actions: [
          Semantics(
            button: true,
            label: l10n.journal,
            onTap: () => unawaited(_openJournal()),
            child: ExcludeSemantics(
              child: IconButton(
                key: const ValueKey('kept-journal-control'),
                onPressed: () => unawaited(_openJournal()),
                icon: const Icon(Icons.menu_book_outlined),
              ),
            ),
          ),
        ],
      ),
      body: visibleItems.isEmpty
          ? Center(
              child: Text(
                l10n.nothingHasStayedYet,
                style: _style(
                  21,
                  color: eastMutedTextColor(context),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
              itemCount: visibleItems.length,
              separatorBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Divider(
                    color: EastColors.of(context).divider,
                    thickness: 0.5,
                  ),
                );
              },
              itemBuilder: (context, index) {
                return _keptItem(visibleItems[index], index);
              },
            ),
    );
  }
}

/// A single Kept row that reveals a trailing "DELETE" action on a leftward
/// swipe, in the style of a conventional iOS trailing swipe action.
///
/// Swiping alone never deletes anything: it only slides [child] aside to
/// expose the DELETE action, which stays exposed until the user explicitly
/// taps it, taps the row again, or swipes the row back closed. Only an
/// explicit tap on the DELETE action invokes [onDelete].
///
/// Both the sliding foreground and the revealed DELETE action are built so
/// that their *hit-test* regions move/appear exactly where they are
/// *painted*: the foreground's `GestureDetector` sits inside its
/// `Transform.translate`, not outside it, so an opaque foreground never
/// keeps covering the DELETE region after it has visually slid away.
class _KeptSwipeToDeleteRow extends StatefulWidget {
  const _KeptSwipeToDeleteRow({
    super.key,
    required this.itemId,
    required this.onDelete,
    required this.deleteLabelStyle,
    required this.deleteLabel,
    required this.child,
  });

  final String itemId;
  final VoidCallback onDelete;
  final TextStyle deleteLabelStyle;
  final String deleteLabel;
  final Widget child;

  @override
  State<_KeptSwipeToDeleteRow> createState() => _KeptSwipeToDeleteRowState();
}

class _KeptSwipeToDeleteRowState extends State<_KeptSwipeToDeleteRow>
    with SingleTickerProviderStateMixin {
  static const double _revealWidth = 84;
  static const double _openThreshold = 0.5;
  static const double _flingVelocityThreshold = 300;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isOpen => _controller.value >= 1.0;

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta;
    if (delta == null) return;
    final directionalDelta =
        Directionality.of(context) == TextDirection.rtl ? -delta : delta;
    _controller.value =
        (_controller.value - directionalDelta / _revealWidth).clamp(0.0, 1.0);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final rawVelocity = details.primaryVelocity ?? 0;
    final velocity = Directionality.of(context) == TextDirection.rtl
        ? -rawVelocity
        : rawVelocity;
    final double target;
    if (velocity <= -_flingVelocityThreshold) {
      target = 1.0;
    } else if (velocity >= _flingVelocityThreshold) {
      target = 0.0;
    } else {
      target = _controller.value >= _openThreshold ? 1.0 : 0.0;
    }
    _controller.animateTo(target, curve: Curves.easeOut);
  }

  void _closeIfOpen() {
    if (_controller.value != 0) {
      _controller.animateTo(0, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          // The DELETE action occupies a fixed-width, full-height region
          // pinned to the right edge. It is only hit-testable once fully
          // revealed (`_isOpen`); while closed it sits, inert, behind the
          // foreground row.
          PositionedDirectional(
            top: 0,
            bottom: 0,
            end: 0,
            width: _revealWidth,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // Build 33 accessibility repair: while closed, this control
                // must not exist as an accessibility-focusable child --
                // VoiceOver swipe navigation should never land on a "DELETE"
                // stop with no visible on-screen anchor. The row-level
                // CustomSemanticsAction("Delete") (see `_keptItem`) already
                // provides a fully accessible delete path regardless of
                // this region's open/closed state.
                return IgnorePointer(
                  ignoring: !_isOpen,
                  child: ExcludeSemantics(
                    excluding: !_isOpen,
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                key: ValueKey('kept-${widget.itemId}-delete-action'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDelete,
                child: Container(
                  alignment: Alignment.center,
                  color: EastColors.of(context).background,
                  child: Text(
                    widget.deleteLabel,
                    style: widget.deleteLabelStyle,
                  ),
                ),
              ),
            ),
          ),
          // The foreground row. Its GestureDetector lives *inside* the
          // Transform.translate so the opaque hit-test area slides together
          // with the visible content, uncovering the DELETE region above
          // once the row is swiped open.
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final direction = Directionality.of(context);
              return Transform.translate(
                offset: Offset(
                  (direction == TextDirection.rtl ? 1 : -1) *
                      _revealWidth *
                      _controller.value,
                  0,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                  onHorizontalDragEnd: _handleHorizontalDragEnd,
                  onTap: _isOpen ? _closeIfOpen : null,
                  child: child,
                ),
              );
            },
            child: SizedBox(
              width: double.infinity,
              child: ColoredBox(
                color: EastColors.of(context).background,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
