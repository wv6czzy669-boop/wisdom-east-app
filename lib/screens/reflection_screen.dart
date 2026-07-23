import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/favorite_item.dart';
import '../services/app_services.dart' as app_services;
import '../services/saved_reflections_service.dart';
import 'keeper_screen.dart';

class ReflectionScreen extends StatefulWidget {
  const ReflectionScreen({
    super.key,
    required this.item,
    required this.isKeeper,
    this.savedReflectionsService,
  });

  final FavoriteItem item;
  final bool isKeeper;
  final SavedReflectionsService? savedReflectionsService;

  @override
  State<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends State<ReflectionScreen> {
  static const int _counterThreshold = 220;

  late final TextEditingController _controller;
  late final SavedReflectionsService _service;
  bool _operationInProgress = false;

  bool get _isKeeper =>
      widget.isKeeper || app_services.purchaseService.isKeeper;

  TextStyle _style(
    double size, {
    Color color = const Color(0xFFF4F0E8),
    double height = 1.38,
    double letterSpacing = 0.35,
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

  @override
  void initState() {
    super.initState();
    _service =
        widget.savedReflectionsService ?? app_services.savedReflectionsService;
    _controller = TextEditingController(text: widget.item.reflection)
      ..addListener(_refresh);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get _canSave =>
      !_operationInProgress && _controller.text.trim().isNotEmpty;

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

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() {
      _operationInProgress = true;
    });

    try {
      final result = await _service.saveReflection(
        itemId: widget.item.id,
        reflection: _controller.text,
        isKeeper: _isKeeper,
      );
      if (!mounted) return;

      if (result.reflectionLimitReached) {
        setState(() {
          _operationInProgress = false;
        });
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) => const KeeperScreen(),
          ),
        );
        return;
      }

      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _operationInProgress = false;
      });
      _showMessage('Reflection could not be kept. Please try again.');
    }
  }

  Future<void> _delete() async {
    if (_operationInProgress || !widget.item.hasReflection) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              title: Text('Delete Reflection?', style: _style(22)),
              content: Text(
                'The reflection will be removed from this kept wisdom.',
                style: _style(
                  17,
                  color: const Color(0xB3FFFFFF),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text('Cancel', style: _style(17)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text('Delete', style: _style(17)),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _operationInProgress = true;
    });

    try {
      await _service.deleteReflection(itemId: widget.item.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _operationInProgress = false;
      });
      _showMessage('Reflection could not be deleted. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final characterCount = _controller.text.characters.length;

    return Scaffold(
      backgroundColor: const Color(0xFF040404),
      appBar: AppBar(
        backgroundColor: const Color(0xFF040404),
        foregroundColor: const Color(0xFFF4F0E8),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        title: Text('Reflection', style: _style(24)),
        actions: [
          if (widget.item.hasReflection)
            Semantics(
              button: true,
              enabled: !_operationInProgress,
              label: 'Delete reflection',
              child: ExcludeSemantics(
                child: TextButton(
                  onPressed: _operationInProgress ? null : _delete,
                  child: Text('Delete', style: _style(16)),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                widget.item.text,
                key: const ValueKey('reflection-associated-wisdom'),
                style: _style(24, height: 1.46),
              ),
              const SizedBox(height: 42),
              Text(
                'What stayed with you?',
                style: _style(
                  19,
                  color: const Color(0xB3FFFFFF),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('reflection-writing-area'),
                controller: _controller,
                enabled: !_operationInProgress,
                autofocus: false,
                keyboardType: TextInputType.multiline,
                minLines: 7,
                maxLines: null,
                maxLength: SavedReflectionsService.maximumReflectionLength,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(
                    SavedReflectionsService.maximumReflectionLength,
                  ),
                ],
                style: _style(20, height: 1.45),
                cursorColor: const Color(0xFFF4F0E8),
                decoration: InputDecoration(
                  hintText: 'Write quietly.',
                  hintStyle: _style(
                    20,
                    color: const Color(0x66FFFFFF),
                    height: 1.45,
                  ),
                  counter: characterCount >= _counterThreshold
                      ? Text(
                          '$characterCount/'
                          '${SavedReflectionsService.maximumReflectionLength}',
                          style: _style(
                            13,
                            color: const Color(0x91FFFFFF),
                          ),
                        )
                      : const SizedBox.shrink(),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Color(0x3DFFFFFF),
                      width: 0.5,
                    ),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Color(0x91FFFFFF),
                      width: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _operationInProgress
                        ? null
                        : () => Navigator.pop(context, false),
                    child: Text('Cancel', style: _style(17)),
                  ),
                  const SizedBox(width: 14),
                  Semantics(
                    button: true,
                    enabled: _canSave,
                    label: _operationInProgress
                        ? 'Keep Reflection. Saving.'
                        : _canSave
                            ? 'Keep Reflection'
                            : 'Keep Reflection. Enter a reflection first.',
                    child: ExcludeSemantics(
                      child: TextButton(
                        key: const ValueKey('keep-reflection-action'),
                        onPressed: _canSave ? _save : null,
                        child: Text(
                          'Keep Reflection',
                          style: _style(
                            17,
                            color: _canSave
                                ? const Color(0xFFF4F0E8)
                                : const Color(0x61FFFFFF),
                            letterSpacing: 0.65,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
