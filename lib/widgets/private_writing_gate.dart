import 'dart:async';
import 'package:flutter/material.dart';
import '../controllers/private_writing_lock_controller.dart';
import '../l10n/east_localizations.dart';
import '../theme/east_design.dart';
import 'east_back_button.dart';

/// Retains an editor's controller/draft while hiding paint, focus, pointer
/// interaction and accessibility together. The native shield covers snapshots.
class PrivateWritingGate extends StatefulWidget {
  const PrivateWritingGate({super.key, required this.child, this.controller});
  final Widget child;
  final PrivateWritingLockController? controller;
  @override
  State<PrivateWritingGate> createState() => _PrivateWritingGateState();
}

class _PrivateWritingGateState extends State<PrivateWritingGate> {
  late final _controller =
      widget.controller ?? PrivateWritingLockController.shared;
  final _scope = Object();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Navigation within an authenticated visit keeps the writing visible;
    // a new/unknown session starts behind the locked field.
    _ready = _controller.canRead;
    _controller.addListener(_changed);
    unawaited(_enter());
  }

  Future<void> _enter() async {
    try {
      await _controller.enter(_scope);
      if (!mounted) return;
      setState(() => _ready = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _controller.enabled &&
            !_controller.canRead &&
            ModalRoute.of(context)?.isCurrent != false) {
          unawaited(
              _controller.unlock(eastLocalizations(context).writingLockReason));
        }
      });
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!_controller.canRead) FocusManager.instance.primaryFocus?.unfocus();
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.leave(_scope);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hidden = !_ready || !_controller.canRead;
    return Stack(children: [
      Offstage(
          offstage: hidden,
          child: TickerMode(
              enabled: !hidden,
              child: ExcludeSemantics(
                  excluding: hidden,
                  child: IgnorePointer(
                      ignoring: hidden,
                      child: FocusScope(
                          canRequestFocus: !hidden, child: widget.child))))),
      if (hidden) _lockedField(context),
    ]);
  }

  Widget _lockedField(BuildContext context) {
    final l10n = eastLocalizations(context);
    final palette = EastColors.of(context);
    TextStyle style(double size, {bool muted = false}) =>
        EastTypography.localized(context,
            size: size,
            height: 1.45,
            letterSpacing: 0.2,
            color: muted ? palette.secondary : palette.ink);
    return Scaffold(
      key: const ValueKey('private-writing-locked'),
      backgroundColor: palette.background,
      appBar: AppBar(
          backgroundColor: palette.background,
          foregroundColor: palette.ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.canPop(context) ? const EastBackButton() : null),
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 28, color: palette.secondary),
                        const SizedBox(height: 30),
                        Text(l10n.writingLockTitle,
                            textAlign: TextAlign.center, style: style(28)),
                        const SizedBox(height: 16),
                        Text(
                            _controller.failed
                                ? l10n.writingLockUnavailable
                                : l10n.writingLockPrompt,
                            textAlign: TextAlign.center,
                            style: style(18, muted: true)),
                        const SizedBox(height: 32),
                        TextButton(
                            key: const ValueKey('private-writing-unlock'),
                            onPressed: _controller.busy
                                ? null
                                : () async {
                                    if (!_ready || !_controller.loaded) {
                                      await _enter();
                                    }
                                    if (mounted) {
                                      await _controller
                                          .unlock(l10n.writingLockReason);
                                    }
                                  },
                            child: Text(
                                _controller.busy
                                    ? l10n.writingLockChecking
                                    : l10n.writingLockUnlock,
                                style: style(20))),
                      ]))))),
    );
  }
}
