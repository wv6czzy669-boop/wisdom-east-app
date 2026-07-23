import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../models/favorite_item.dart';
import '../services/app_services.dart' as app_services;
import '../services/purchase_service.dart';
import '../services/saved_reflections_service.dart';
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
  final Map<String, RemovedSavedReflection> _pendingRemovals = {};
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
        color: const Color(0x91FFFFFF),
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

  Future<bool> _confirmRemoval(FavoriteItem item) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              title: Text('Remove from Kept?', style: _style(22)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text('Cancel', style: _style(17)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text('Remove', style: _style(17)),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed || !mounted) return false;

    try {
      final removed = await _service.remove(itemId: item.id);
      if (!mounted || removed == null) return false;
      _pendingRemovals[item.id] = removed;
      return true;
    } catch (_) {
      _showMessage('This wisdom could not be removed. Please try again.');
      return false;
    }
  }

  void _completeRemoval(FavoriteItem item) {
    final removed = _pendingRemovals.remove(item.id);
    if (removed == null || !mounted) return;

    setState(() {
      _items = removed.items;
    });

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF111111),
          content: Text('Removed from Kept.', style: _style(17)),
          action: SnackBarAction(
            label: 'Undo',
            textColor: const Color(0xFFF4F0E8),
            onPressed: () {
              _undoRemoval(removed);
            },
          ),
        ),
      );
  }

  Future<void> _undoRemoval(RemovedSavedReflection removed) async {
    try {
      final restored = await _service.restore(removed);
      if (!mounted) return;
      setState(() {
        _items = restored;
      });
    } catch (_) {
      _showMessage('This wisdom could not be restored.');
    }
  }

  Future<void> _removeFromAccessibility(FavoriteItem item) async {
    if (!await _confirmRemoval(item) || !mounted) return;
    _completeRemoval(item);
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
        const CustomSemanticsAction(label: 'Remove from Kept'): () {
          unawaited(_removeFromAccessibility(item));
        },
      },
      child: Dismissible(
        key: ValueKey('kept-${item.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmRemoval(item),
        onDismissed: (_) => _completeRemoval(item),
        background: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('REMOVE', style: _statusStyle),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_displayDate(item.date),
                style: _style(
                  15,
                  color: const Color(0x91FFFFFF),
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
                  color: const Color(0x91FFFFFF),
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
