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
import '../utils/kept_search_matcher.dart';
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
  bool _deleteInProgress = false;
  FavoriteItem? _pendingDeleteItem;
  int _deleteDismissRevision = 0;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  bool get _confirmingDelete => _pendingDeleteItem != null;

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
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    app_services.keptStateRevisionNotifier.removeListener(_onKeptStateChanged);
    _incomingKeptRefreshGuard.invalidate();
    _searchController.dispose();
    _searchFocusNode
      ..removeListener(_onSearchFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
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

  void _requestDelete(FavoriteItem item) {
    if (_deleteInProgress || !mounted) return;
    setState(() {
      _pendingDeleteItem = item;
    });
  }

  void _cancelDelete() {
    if (_deleteInProgress || !mounted) return;
    setState(() {
      _pendingDeleteItem = null;
      // Cancel means abandoning the complete destructive interaction, not
      // merely hiding its confirmation. Advancing this signal returns any
      // revealed swipe action to the ordinary closed Kept-row state.
      _deleteDismissRevision += 1;
    });
  }

  Future<void> _confirmDelete() async {
    final item = _pendingDeleteItem;
    if (_deleteInProgress || item == null || !mounted) return;

    setState(() {
      _deleteInProgress = true;
    });

    try {
      final removed = await _service.remove(itemId: item.id);
      if (!mounted) return;
      setState(() {
        if (removed != null) {
          _items = removed.items;
        }
        _deleteInProgress = false;
        _pendingDeleteItem = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleteInProgress = false;
        _pendingDeleteItem = null;
      });
      _showMessage(
        eastLocalizations(context).wisdomCouldNotBeRemoved,
      );
    }
  }

  Widget _deleteDecisionLabel(
    String label, {
    required VoidCallback? onTap,
    required Color color,
  }) {
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
            key: const ValueKey('kept-delete-decision'),
            color: EastColors.of(context).overlay,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.removeKeptQuestion,
                  textAlign: TextAlign.center,
                  style: _style(28, height: 1.1),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.keptDeleteExplanation,
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

  // Build 33 real-device Voice Control repair: `itemNumber` (1-based,
  // screen-order -- see `itemBuilder`'s `index`) makes each row's
  // Reflection action uniquely addressable by name ("Open Reflection,
  // item 2"), since the wisdom text itself must never be the spoken
  // control name and dates are not guaranteed unique. The static date/
  // wisdom content remains unnumbered and VoiceOver-readable via ordinary
  // Text auto-semantics -- only the actionable control's name changes.
  Widget? _status(FavoriteItem item, int itemNumber) {
    final l10n = eastLocalizations(context);
    if (!item.hasReflection) return null;

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
          _requestDelete(item);
        },
      },
      child: _KeptSwipeToDeleteRow(
        key: ValueKey('kept-${item.id}'),
        itemId: item.id,
        dismissRevision: _deleteDismissRevision,
        deleteLabelStyle: _statusStyle,
        deleteLabel: eastLocalizations(context).deleteUpper,
        onDelete: () => _requestDelete(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_displayDate(item),
                style: _style(
                  15,
                  color: eastMutedTextColor(context),
                  letterSpacing: 0.4,
                )),
            if (_status(item, itemNumber) case final status?) ...[
              const SizedBox(height: 5),
              status,
              const SizedBox(height: 7),
            ] else
              const SizedBox(height: 12),
            // The wisdom itself is also a natural entry point into its
            // Reflection. The explicit ADD REFLECTION / REFLECTED control
            // below remains the accessible named action; excluding only
            // this gesture from semantics avoids announcing two identical
            // controls while preserving the wisdom Text's reading semantics.
            GestureDetector(
              key: ValueKey('kept-${item.id}-wisdom-action'),
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: () => unawaited(_openReflection(item)),
              child: Text(_displayWisdom(item), style: _style(24)),
            ),
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

  void _updateSearch(String value) {
    if (value == _searchQuery || !mounted) return;
    setState(() => _searchQuery = value);
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty || !mounted) return;
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  /// Kept is a chronological reading surface, so its order must come from
  /// each record's durable timestamp rather than envelope/list arrival order
  /// (which can change after CloudKit reconciliation). Records produced by
  /// the current repository always carry `keptAt`; the index fallback keeps
  /// legacy/injected records deterministic and preserves the screen's former
  /// newest-appended-first behavior when no reliable timestamp exists.
  List<FavoriteItem> _newestFirstItems() {
    final indexed = _items.asMap().entries.toList(growable: false);
    indexed.sort((a, b) {
      final aKeptAt = _parseKeptAt(a.value);
      final bKeptAt = _parseKeptAt(b.value);
      if (aKeptAt != null && bKeptAt != null) {
        final byKeptAt = bKeptAt.compareTo(aKeptAt);
        if (byKeptAt != 0) return byKeptAt;
      } else if (aKeptAt != bKeptAt) {
        return aKeptAt == null ? 1 : -1;
      }
      return b.key.compareTo(a.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }

  DateTime? _parseKeptAt(FavoriteItem item) {
    final raw = item.keptAt;
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  Widget _searchField() {
    final l10n = eastLocalizations(context);
    final palette = EastColors.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
      child: AnimatedContainer(
        key: const ValueKey('kept-search-shell'),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _searchFocusNode.hasFocus ? palette.ink : palette.divider,
              width: _searchFocusNode.hasFocus ? 0.8 : 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 44,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Icon(
                    Icons.search,
                    size: 19,
                    color: palette.secondary,
                    weight: 300,
                  ),
                ),
              ),
            ),
            Expanded(
              child: MergeSemantics(
                child: Semantics(
                  key: const ValueKey('kept-search-semantics'),
                  label: l10n.searchKept,
                  child: TextField(
                    key: const ValueKey('kept-search-field'),
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _updateSearch,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onSubmitted: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    cursorColor: palette.ink,
                    keyboardAppearance: Theme.of(context).brightness,
                    textInputAction: TextInputAction.search,
                    style: _style(19, height: 1.2),
                    decoration: InputDecoration(
                      hintText: l10n.searchKept,
                      hintStyle: _style(
                        18,
                        color: palette.hint,
                        height: 1.2,
                        letterSpacing: 0.4,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              Semantics(
                key: const ValueKey('kept-search-clear-semantics'),
                button: true,
                label: l10n.clearSearch,
                onTap: _clearSearch,
                child: ExcludeSemantics(
                  child: IconButton(
                    key: const ValueKey('kept-search-clear'),
                    onPressed: _clearSearch,
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: palette.secondary,
                      weight: 300,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = eastLocalizations(context);
    final visibleItems = _newestFirstItems().where((item) {
      return KeptSearchMatcher.matches(
        wisdom: _displayWisdom(item),
        reflection: item.reflection,
        query: _searchQuery,
      );
    }).toList(growable: false);
    final hasQuery = KeptSearchMatcher.normalize(_searchQuery).isNotEmpty;

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
      body: Stack(
        children: [
          IgnorePointer(
            ignoring: _confirmingDelete,
            child: ExcludeSemantics(
              excluding: _confirmingDelete,
              child: _items.isEmpty
                  ? Center(
                      child: Text(
                        l10n.nothingHasStayedYet,
                        style: _style(
                          21,
                          color: eastMutedTextColor(context),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        _searchField(),
                        Expanded(
                          child: visibleItems.isEmpty && hasQuery
                              ? Center(
                                  child: Text(
                                    l10n.noKeptSearchResults,
                                    key: const ValueKey(
                                      'kept-search-empty-state',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: _style(
                                      21,
                                      color: eastMutedTextColor(context),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    14,
                                    24,
                                    32,
                                  ),
                                  itemCount: visibleItems.length,
                                  separatorBuilder: (context, index) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Divider(
                                        color: EastColors.of(context).divider,
                                        thickness: 0.5,
                                      ),
                                    );
                                  },
                                  itemBuilder: (context, index) {
                                    return _keptItem(
                                      visibleItems[index],
                                      index,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
          ),
          _deleteDecisionOverlay(),
        ],
      ),
    );
  }
}

/// A single Kept row that reveals a trailing "DELETE" action on a leftward
/// swipe, in the style of a conventional iOS trailing swipe action.
///
/// Swiping alone never deletes anything: it only slides [child] aside to
/// expose the DELETE action, which stays exposed until the user explicitly
/// taps it, taps the row again, or swipes the row back closed. Tapping the
/// DELETE action invokes [onDelete], which requests the full-field decision;
/// the durable removal runs only after that separate confirmation.
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
    required this.dismissRevision,
    required this.onDelete,
    required this.deleteLabelStyle,
    required this.deleteLabel,
    required this.child,
  });

  final String itemId;
  final int dismissRevision;
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
  void didUpdateWidget(covariant _KeptSwipeToDeleteRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dismissRevision != oldWidget.dismissRevision) {
      _closeIfOpen();
    }
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
              final isRevealed = _controller.value > 0;
              return Transform.translate(
                offset: Offset(
                  (direction == TextDirection.rtl ? 1 : -1) *
                      _revealWidth *
                      _controller.value,
                  0,
                ),
                child: GestureDetector(
                  key: ValueKey('kept-${widget.itemId}-swipe-foreground'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                  onHorizontalDragEnd: _handleHorizontalDragEnd,
                  // A revealed DELETE action always gets the first tap:
                  // close the row without allowing an interior wisdom or
                  // Reflection control to navigate in the same gesture.
                  onTap: isRevealed ? _closeIfOpen : null,
                  child: AbsorbPointer(
                    absorbing: isRevealed,
                    child: child,
                  ),
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
