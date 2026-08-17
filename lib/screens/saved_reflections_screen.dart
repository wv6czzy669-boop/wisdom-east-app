import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../controllers/latest_request_guard.dart';
import '../models/favorite_item.dart';
import '../services/app_services.dart' as app_services;
import '../services/purchase_service.dart';
import '../services/return_service.dart';
import '../services/saved_reflections_service.dart';
import '../theme/muted_text_color.dart';
import '../utils/kept_diagnostics.dart';
import '../widgets/east_back_button.dart';
import 'journal_screen.dart';
import 'keeper_screen.dart';
import 'reflection_screen.dart';
import 'return_screen.dart';

class SavedReflectionsScreen extends StatefulWidget {
  const SavedReflectionsScreen({
    super.key,
    required this.reflections,
    this.isKeeper = false,
    this.savedReflectionsService,
    this.purchaseService,
    this.returnService,
  });

  final List<FavoriteItem> reflections;
  final bool isKeeper;
  final SavedReflectionsService? savedReflectionsService;
  final PurchaseService? purchaseService;
  final ReturnService? returnService;

  @override
  State<SavedReflectionsScreen> createState() => _SavedReflectionsScreenState();
}

class _SavedReflectionsScreenState extends State<SavedReflectionsScreen> {
  late List<FavoriteItem> _items;
  late final SavedReflectionsService _service;
  late final PurchaseService _purchaseService;
  late final ReturnService _returnService;
  bool _navigationInProgress = false;

  /// The occurrence Return currently points at, if any. Visual-polish
  /// repair: Return itself is now ALWAYS visible in the utility region --
  /// `null` here means "nothing has ever been selected yet" (before the
  /// first 14-day-eligible occurrence, or a rare edge case with no
  /// selectable candidate), not "hide Return". Resolved asynchronously,
  /// never blocking this screen's own initial render.
  FavoriteItem? _currentReturn;

  /// How long remains until a *new* Return selection could next be made,
  /// mirrored alongside [_currentReturn] purely for the small muted
  /// supporting line -- see [ReturnService.cadenceRemaining]'s own doc
  /// comment. Never influences selection.
  Duration? _returnCadenceRemaining;
  final _returnRefreshGuard = LatestRequestGuard();

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
    Color color = const Color(0xFFF4F0E8),
    double height = 1.35,
    double letterSpacing = 0.3,
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontFamily: 'CormorantGaramond',
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  TextStyle get _statusStyle => _style(
        13,
        color: eastMutedTextColor,
        letterSpacing: 1.15,
      );

  @override
  void initState() {
    super.initState();
    _items = List<FavoriteItem>.from(widget.reflections);
    _service =
        widget.savedReflectionsService ?? app_services.savedReflectionsService;
    _purchaseService = widget.purchaseService ?? app_services.purchaseService;
    _returnService = widget.returnService ?? app_services.returnService;
    // Build 26 Phase 4H-6: subscribe to the neutral incoming-Kept-state
    // signal for as long as this screen stays mounted -- mirrors the
    // existing `app_services.purchaseService.addListener(...)` pattern
    // `home_screen.dart` already uses for its own cross-cutting listener.
    app_services.keptStateRevisionNotifier.addListener(_onKeptStateChanged);
    unawaited(_refreshReturn());
  }

  @override
  void dispose() {
    app_services.keptStateRevisionNotifier.removeListener(_onKeptStateChanged);
    _incomingKeptRefreshGuard.invalidate();
    _returnRefreshGuard.invalidate();
    super.dispose();
  }

  /// EAST. Phase 9: re-resolves Return against the current [_items] and
  /// applies the result if it is still the freshest outstanding call. Safe
  /// to call as often as [_items] itself changes -- resolution is a no-op
  /// (no reroll, no write) whenever the already-pinned selection is still
  /// current; see [ReturnService.resolveCurrentReturn].
  Future<void> _refreshReturn() async {
    final generation = _returnRefreshGuard.begin();
    final resolved = await _returnService.resolveCurrentReturn(_items);
    final cadenceRemaining = await _returnService.cadenceRemaining();
    if (!mounted || !_returnRefreshGuard.isCurrent(generation)) return;
    setState(() {
      _currentReturn = resolved;
      _returnCadenceRemaining = cadenceRemaining;
    });
  }

  /// Visual-polish repair: the small muted supporting line shown under the
  /// always-visible Return action. Never influences selection -- purely a
  /// presentation derivation over [_currentReturn]/[_returnCadenceRemaining].
  String _returnSupportingCopy() {
    if (_currentReturn == null) {
      return 'What you keep may return after 14 days.';
    }

    final remaining = _returnCadenceRemaining;
    if (remaining == null || remaining <= Duration.zero) {
      // A next Return is available now (or cadence is unknown) -- never a
      // nonsensical "0 days" message; the clean active state instead.
      return 'Return to what stayed.';
    }

    final days = (remaining.inHours / 24).ceil();
    if (days <= 0) return 'Return to what stayed.';
    return days == 1 ? 'A new Return in 1 day.' : 'A new Return in $days days.';
  }

  /// Approved Ritual/Kept direction: "What you keep may return after 14
  /// days." belongs to Return's own empty state (see [ReturnScreen]),
  /// never to Kept itself -- Kept shows no supporting line until a real
  /// Return actually exists. Accessibility is unaffected:
  /// [_returnSupportingCopy] above (unchanged) still feeds the full
  /// explanation to the Return action's semantic label regardless of what
  /// is visibly printed here.
  String _returnVisibleSupportingCopy() {
    if (_currentReturn == null) return '';
    return _returnSupportingCopy();
  }

  /// Build 26 Phase 4H-6: invoked synchronously by
  /// [app_services.keptStateRevisionNotifier] only after an incoming
  /// CloudKit sync has durably applied a Kept/Reflection content change
  /// while this screen is mounted. Never shows a spinner, never shows a
  /// snackbar, never resets scroll position or navigation -- this is a
  /// silent background refresh, deliberately distinct from [_reload]'s own
  /// user-initiated-navigation-return behaviour (which does surface a
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
    unawaited(_refreshReturn());
  }

  String _displayDate(String storedDate) => storedDate.toUpperCase();

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF111111),
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
      unawaited(_refreshReturn());
    } catch (_) {
      keptDiagnostic('kept-screen: reload-failed');
      _showMessage('Kept wisdoms could not be refreshed.');
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

  /// EAST. Phase 9 (visual-polish repair): Return is now always tappable.
  /// Never re-resolves or reselects here -- [_refreshReturn] is the only
  /// place selection happens, and it already ran (and persisted, if it
  /// chose anything new) well before this control could ever be tapped.
  ///
  /// Before any occurrence has ever been selected ([_currentReturn] is
  /// `null`), this opens the quiet pre-eligibility explanation state --
  /// available identically to Free and Keeper, never gated, since it only
  /// ever explains what Return is. Once an actual Return exists, Free users
  /// reuse the exact same Keeper/paywall entry point [_openReflection]
  /// above already uses; no second paywall.
  Future<void> _openReturn() async {
    if (_navigationInProgress || !mounted) return;
    final item = _currentReturn;

    _navigationInProgress = true;
    try {
      if (item == null) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (context) => const ReturnScreen(),
          ),
        );
        return;
      }

      if (!_isKeeper) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (context) => const KeeperScreen(),
          ),
        );
        return;
      }

      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) => ReturnScreen(item: item),
        ),
      );
    } finally {
      _navigationInProgress = false;
    }
  }

  /// EAST. Phase 10 (visual-polish repair): opens the dedicated Journal
  /// screen for both Free and Keeper -- Journal itself is openable by
  /// everyone; only its "Take it with you" export action is Keeper-gated,
  /// entirely inside [JournalScreen]. Unlike Return, Journal has no
  /// eligibility window -- it is always offered; the empty-content case is
  /// handled entirely inside [JournalScreen] itself, never by hiding this
  /// control.
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
      _showMessage('This wisdom could not be removed. Please try again.');
    }
  }

  Widget _status(FavoriteItem item) {
    if (!item.hasReflection) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('KEPT', style: _statusStyle),
        ),
      );
    }

    return Semantics(
      button: true,
      label: 'REFLECTED. Edit reflection.',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openReflection(item),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('REFLECTED', style: _statusStyle),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keptItem(FavoriteItem item) {
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Delete'): () {
          unawaited(_deleteItem(item));
        },
      },
      child: _KeptSwipeToDeleteRow(
        key: ValueKey('kept-${item.id}'),
        itemId: item.id,
        deleteLabelStyle: _statusStyle,
        onDelete: () => unawaited(_deleteItem(item)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_displayDate(item.date),
                style: _style(
                  15,
                  color: eastMutedTextColor,
                  letterSpacing: 0.4,
                )),
            const SizedBox(height: 5),
            _status(item),
            const SizedBox(height: 7),
            Text(item.text, style: _style(24)),
            if (!item.hasReflection) ...[
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: 'Add reflection',
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openReflection(item),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('ADD REFLECTION', style: _statusStyle),
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
    final visibleItems = _items.reversed.toList(growable: false);

    return Scaffold(
      key: const ValueKey('kept-screen-root'),
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
        elevation: 0,
        leading: Navigator.canPop(context) ? const EastBackButton() : null,
        title: Text('Kept', style: _style(24)),
      ),
      body: Column(
        // Real-device repair: the outer Column's default `center`
        // cross-axis alignment was shrink-wrapping and re-centering the
        // Return/Journal utility row (its own internal Row was already
        // left-aligned, but the block containing it had no reason to span
        // full width, so the whole narrow block sat centered on screen).
        // `start` fixes that without affecting the archive list below
        // (ListView already fills to the max cross-axis extent regardless
        // of this alignment) or the empty state (explicitly wrapped in its
        // own `Center`).
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _keptUtilityRow(),
          Expanded(
            child: visibleItems.isEmpty
                ? Center(
                    child: Text(
                      'Nothing has stayed yet.',
                      style: _style(
                        21,
                        color: eastMutedTextColor,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
                    itemCount: visibleItems.length,
                    separatorBuilder: (context, index) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Divider(
                          color: Colors.white24,
                          thickness: 0.5,
                        ),
                      );
                    },
                    itemBuilder: (context, index) {
                      return _keptItem(visibleItems[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// EAST. Phase 9/10 (visual-polish repair) — the Kept header utility
  /// region: quiet, compact, immediately below the "Kept" title and above
  /// the existing Basic Wisdoms/Reflected content, which this never
  /// inserts into, reorders, or visually disturbs. Return and Journal are
  /// now BOTH always offered -- premium status is communicated through
  /// behavior alone, never a "KEEPER" badge beside either. A small muted
  /// line under the row carries Return's own state-dependent supporting
  /// copy; Journal needs no such line here (its own Keeper note lives
  /// inside the Journal screen itself, next to its export action).
  Widget _keptUtilityRow() {
    final supportingCopy = _returnVisibleSupportingCopy();
    // Approved Kept direction: the archive begins a deliberate, but no
    // longer excessive, gap beneath the Return / Journal row when there is
    // no supporting line to carry (the common case, now that
    // pre-eligibility copy no longer appears here) -- no dead zone, but a
    // real, intentional gap rather than the old tight spacing.
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 6, 24, supportingCopy.isEmpty ? 32 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A horizontally-scrolling container, not a bare Row: at very
          // large accessibility text scales on a narrow device,
          // "Return | Journal" can genuinely exceed the screen width.
          // Scrolling degrades gracefully rather than overflowing/
          // crashing; at ordinary scale this is visually identical to a
          // plain Row.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _utilityAction(
                  key: const ValueKey('kept-return-action'),
                  label: 'Return',
                  semanticLabel: 'Return. ${_returnSupportingCopy()}',
                  onTap: _openReturn,
                ),
                Container(
                  height: 15,
                  width: 0.5,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  color: Colors.white24,
                ),
                _utilityAction(
                  key: const ValueKey('kept-journal-action'),
                  label: 'Journal',
                  semanticLabel: 'Journal',
                  onTap: _openJournal,
                ),
              ],
            ),
          ),
          if (supportingCopy.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              supportingCopy,
              key: const ValueKey('kept-return-supporting-copy'),
              style: _style(13, color: eastMutedTextColor, letterSpacing: 0.3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _utilityAction({
    required Key key,
    required String label,
    required String semanticLabel,
    required Future<void> Function() onTap,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(onTap()),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Align(
              alignment: Alignment.centerLeft,
              // Visual polish: a hairline underline tied to each word's own
              // width (Flutter's text decoration, not a separate divider
              // widget) -- thin and muted rather than a bright hyperlink
              // underline, so "Return"/"Journal" read as quiet editorial
              // labels, not web links or buttons.
              child: Text(
                label,
                style: _style(18.5, color: eastMutedTextColor).copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor:
                          eastMutedTextColor.withValues(alpha: 0.45),
                      decorationThickness: 0.6,
                      decorationStyle: TextDecorationStyle.solid,
                    ),
              ),
            ),
          ),
        ),
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
    required this.child,
  });

  final String itemId;
  final VoidCallback onDelete;
  final TextStyle deleteLabelStyle;
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
    _controller.value =
        (_controller.value - delta / _revealWidth).clamp(0.0, 1.0);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
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
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: _revealWidth,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return IgnorePointer(
                  ignoring: !_isOpen,
                  child: child,
                );
              },
              child: GestureDetector(
                key: ValueKey('kept-${widget.itemId}-delete-action'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDelete,
                child: Container(
                  alignment: Alignment.center,
                  color: const Color(0xFF040404),
                  child: Text('DELETE', style: widget.deleteLabelStyle),
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
              return Transform.translate(
                offset: Offset(-_revealWidth * _controller.value, 0),
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
                color: const Color(0xFF040404),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
