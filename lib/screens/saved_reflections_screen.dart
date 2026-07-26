import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../models/favorite_item.dart';
import '../services/app_services.dart' as app_services;
import '../services/purchase_service.dart';
import '../services/saved_reflections_service.dart';
import '../theme/muted_text_color.dart';
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
  late List<FavoriteItem> _items;
  late final SavedReflectionsService _service;
  late final PurchaseService _purchaseService;
  bool _navigationInProgress = false;

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

  Future<void> _reload() async {
    try {
      final loaded = await _service.load();
      if (!mounted) return;
      setState(() {
        _items = loaded;
      });
    } catch (_) {
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
        title: Text('Kept', style: _style(24)),
      ),
      body: visibleItems.isEmpty
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
