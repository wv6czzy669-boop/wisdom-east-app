import 'package:flutter/material.dart';

import '../controllers/locale_preference_controller.dart';
import '../l10n/east_localizations.dart';
import '../theme/east_design.dart';
import '../widgets/east_back_button.dart';

/// The intentionally small, English-only language picker.
class LanguageSelectionScreen extends StatelessWidget {
  const LanguageSelectionScreen({
    super.key,
    required this.localePreferenceController,
  });

  final LocalePreferenceController localePreferenceController;

  static const WidgetStateProperty<Color?> _noOverlayColor =
      WidgetStatePropertyAll(Colors.transparent);

  @override
  Widget build(BuildContext context) {
    final l10n = eastLocalizations(context);
    return Scaffold(
      backgroundColor: EastColors.background,
      appBar: AppBar(
        backgroundColor: EastColors.background,
        foregroundColor: EastColors.ink,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: const EastBackButton(),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
          child: AnimatedBuilder(
            animation: localePreferenceController,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.language,
                    style: EastTypography.localized(context, size: 27),
                  ),
                  const SizedBox(height: 28),
                  _option(
                    context: context,
                    key: const ValueKey('language-system-default-option'),
                    label: l10n.systemDefault,
                    locale: null,
                  ),
                  const Divider(height: 1, color: EastColors.divider),
                  _option(
                    context: context,
                    key: const ValueKey('language-english-option'),
                    label: l10n.english,
                    locale: const Locale('en'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _option({
    required BuildContext context,
    required Key key,
    required String label,
    required Locale? locale,
  }) {
    final selected = locale == null
        ? localePreferenceController.isSystemDefault
        : localePreferenceController.explicitLocale == locale;
    final l10n = eastLocalizations(context);
    return Semantics(
      button: true,
      selected: selected,
      label: l10n.languageOptionSemantics(label),
      onTap: () => localePreferenceController.setExplicitLocale(locale),
      child: ExcludeSemantics(
        child: InkWell(
          key: key,
          onTap: () => localePreferenceController.setExplicitLocale(locale),
          overlayColor: _noOverlayColor,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: EastTypography.localized(context, size: 21),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check,
                    color: EastColors.ink,
                    size: 19,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
