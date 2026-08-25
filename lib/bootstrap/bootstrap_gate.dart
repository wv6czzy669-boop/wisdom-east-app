import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../controllers/appearance_preference_controller.dart';
import '../controllers/locale_preference_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/east_localizations.dart';
import '../localization/east_locale_registry.dart';
import '../theme/east_design.dart';

/// Lets Flutter paint a safe EAST. surface while the one mandatory storage
/// bootstrap is still running.
///
/// The supplied [bootstrap] future is observed exactly once. This widget
/// never cancels, times out, retries, or recreates it, so a protected-storage
/// migration cannot be interrupted or run twice. A slow native channel now
/// leaves a real, accessible waiting surface instead of keeping the process
/// behind the native launch screen indefinitely; an unexpected failure is
/// rendered fail-closed and never constructs [readyBuilder].
class BootstrapGate extends StatefulWidget {
  const BootstrapGate({
    super.key,
    required this.bootstrap,
    required this.readyBuilder,
    this.localePreferenceController,
    this.appearancePreferenceController,
    this.waitingDisclosureDelay = const Duration(milliseconds: 750),
    this.longWaitDisclosureDelay = const Duration(seconds: 15),
  });

  final Future<void> bootstrap;
  final WidgetBuilder readyBuilder;
  final LocalePreferenceController? localePreferenceController;
  final AppearancePreferenceController? appearancePreferenceController;
  final Duration waitingDisclosureDelay;
  final Duration longWaitDisclosureDelay;

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

enum _BootstrapPhase { waiting, ready, failed }

class _BootstrapGateState extends State<BootstrapGate> {
  _BootstrapPhase _phase = _BootstrapPhase.waiting;
  Timer? _waitingDisclosureTimer;
  Timer? _longWaitDisclosureTimer;
  bool _showWaitingDisclosure = false;
  bool _showLongWaitDisclosure = false;

  @override
  void initState() {
    super.initState();
    _observeBootstrapOnce();
    _waitingDisclosureTimer = Timer(widget.waitingDisclosureDelay, () {
      if (!mounted || _phase != _BootstrapPhase.waiting) return;
      setState(() => _showWaitingDisclosure = true);
    });
    _longWaitDisclosureTimer = Timer(widget.longWaitDisclosureDelay, () {
      if (!mounted || _phase != _BootstrapPhase.waiting) return;
      setState(() => _showLongWaitDisclosure = true);
    });
  }

  void _observeBootstrapOnce() {
    widget.bootstrap.then(
      (_) {
        if (!mounted) return;
        _waitingDisclosureTimer?.cancel();
        _longWaitDisclosureTimer?.cancel();
        setState(() => _phase = _BootstrapPhase.ready);
      },
      onError: (Object _, StackTrace __) {
        if (!mounted) return;
        _waitingDisclosureTimer?.cancel();
        _longWaitDisclosureTimer?.cancel();
        setState(() => _phase = _BootstrapPhase.failed);
      },
    );
  }

  @override
  void dispose() {
    _waitingDisclosureTimer?.cancel();
    _longWaitDisclosureTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _BootstrapPhase.ready) {
      return widget.readyBuilder(context);
    }

    final listenables = <Listenable>[
      if (widget.localePreferenceController != null)
        widget.localePreferenceController!,
      if (widget.appearancePreferenceController != null)
        widget.appearancePreferenceController!,
    ];
    if (listenables.isEmpty) return _buildBootstrapApp();
    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (_, __) => _buildBootstrapApp(),
    );
  }

  Widget _buildBootstrapApp() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final brightness = dispatcher.platformBrightness;
    final explicitLocale = widget.localePreferenceController?.explicitLocale;
    final effectiveThemeLocale = explicitLocale ??
        EastLocaleRegistry.resolveProductLocale(dispatcher.locale);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: eastTheme(locale: effectiveThemeLocale),
      darkTheme: eastTheme(
        locale: effectiveThemeLocale,
        brightness: Brightness.dark,
      ),
      themeMode: widget.appearancePreferenceController?.themeMode ??
          (brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: EastLocaleRegistry.runtimeSupported,
      locale: explicitLocale,
      localeResolutionCallback: (deviceLocale, supportedLocales) =>
          LocalePreferenceController.resolveSystemLocale(
        deviceLocale,
        supportedLocales,
      ),
      home: _BootstrapSurface(
        failed: _phase == _BootstrapPhase.failed,
        discloseWaiting: _showWaitingDisclosure,
        discloseLongWait: _showLongWaitDisclosure,
      ),
    );
  }
}

class _BootstrapSurface extends StatelessWidget {
  const _BootstrapSurface({
    required this.failed,
    required this.discloseWaiting,
    required this.discloseLongWait,
  });

  final bool failed;
  final bool discloseWaiting;
  final bool discloseLongWait;

  @override
  Widget build(BuildContext context) {
    final colors = EastColors.of(context);
    final l10n = eastLocalizations(context);
    final needsRecovery = failed || discloseLongWait;
    final status = needsRecovery ? l10n.bootstrapRecovery : l10n.opening;

    return Scaffold(
      body: Center(
        child: Semantics(
          container: true,
          liveRegion: true,
          label: failed || discloseWaiting || discloseLongWait ? status : null,
          child: ExcludeSemantics(
            child: AnimatedOpacity(
              opacity: failed || discloseWaiting || discloseLongWait ? 1 : 0,
              duration: const Duration(milliseconds: 240),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'EAST.',
                    style: EastTypography.editorial(
                      size: 44,
                      color: colors.ink,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (needsRecovery)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(
                        status,
                        textAlign: TextAlign.center,
                        style: EastTypography.localized(
                          context,
                          size: 17,
                          color: colors.secondary,
                        ),
                      ),
                    )
                  else
                    CupertinoActivityIndicator(color: colors.secondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
