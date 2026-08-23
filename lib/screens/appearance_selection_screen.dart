import 'package:flutter/material.dart';

import '../controllers/appearance_preference_controller.dart';
import '../l10n/east_localizations.dart';
import '../theme/east_design.dart';
import '../widgets/east_back_button.dart';

/// EAST.'s immediate, persisted Appearance picker: System Default, Light,
/// Dark. Deliberately mirrors [LanguageSelectionScreen]'s structure and
/// restraint -- exactly three plain-text rows, no flags/icons/preview, no
/// Save button, applies immediately, normal back navigation. Appearance is
/// independent of Language: this screen never reads or writes any locale
/// preference.
class AppearanceSelectionScreen extends StatelessWidget {
  const AppearanceSelectionScreen({
    super.key,
    required this.appearancePreferenceController,
  });

  final AppearancePreferenceController appearancePreferenceController;

  static const WidgetStateProperty<Color?> _noOverlayColor =
      WidgetStatePropertyAll(Colors.transparent);

  @override
  Widget build(BuildContext context) {
    final l10n = eastLocalizations(context);
    final palette = EastColors.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.ink,
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
            animation: appearancePreferenceController,
            builder: (context, _) {
              final palette = EastColors.of(context);
              return ListView(
                children: [
                  Text(
                    l10n.appearance,
                    style: EastTypography.localized(context, size: 27),
                  ),
                  const SizedBox(height: 28),
                  _option(
                    context: context,
                    key: const ValueKey('appearance-system-option'),
                    label: l10n.systemDefault,
                    mode: EastAppearanceMode.system,
                    palette: palette,
                  ),
                  Divider(height: 1, color: palette.divider),
                  _option(
                    context: context,
                    key: const ValueKey('appearance-light-option'),
                    label: l10n.light,
                    mode: EastAppearanceMode.light,
                    palette: palette,
                  ),
                  Divider(height: 1, color: palette.divider),
                  _option(
                    context: context,
                    key: const ValueKey('appearance-dark-option'),
                    label: l10n.dark,
                    mode: EastAppearanceMode.dark,
                    palette: palette,
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
    required EastAppearanceMode mode,
    required EastColorScheme palette,
  }) {
    final selected = appearancePreferenceController.mode == mode;
    final l10n = eastLocalizations(context);
    return Semantics(
      button: true,
      selected: selected,
      label: l10n.appearanceOptionSemantics(label),
      onTap: () => appearancePreferenceController.setMode(mode),
      child: ExcludeSemantics(
        child: InkWell(
          key: key,
          onTap: () => appearancePreferenceController.setMode(mode),
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
                  Icon(
                    Icons.check,
                    color: palette.ink,
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
