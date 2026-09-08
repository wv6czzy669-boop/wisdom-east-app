import 'package:flutter/material.dart';
import '../controllers/ritual_sound_preference_controller.dart';
import '../l10n/east_localizations.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';
import '../widgets/east_back_button.dart';

class RitualSoundSelectionScreen extends StatelessWidget {
  const RitualSoundSelectionScreen({super.key, required this.controller});
  final RitualSoundPreferenceController controller;

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
          elevation: 0,
          leading: const EastBackButton()),
      body: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 40),
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.ritualSound,
                          style: EastTypography.localized(context, size: 30)),
                      const SizedBox(height: 30),
                      for (final mode in RitualSoundMode.values) ...[
                        _option(context, mode),
                        Divider(
                            height: 1, thickness: 0.5, color: palette.divider),
                      ],
                      if (controller.saveFailed) ...[
                        const SizedBox(height: 24),
                        Text(l10n.ritualSoundSaveFailed,
                            style: EastTypography.localized(context,
                                size: 17,
                                height: 1.4,
                                color: eastMutedTextColor(context))),
                        TextButton(
                            onPressed: () =>
                                controller.setMode(controller.mode),
                            child: Text(l10n.retry)),
                      ],
                    ]),
              )),
            ),
          )),
    );
  }

  Widget _option(BuildContext context, RitualSoundMode mode) {
    final l10n = eastLocalizations(context);
    final label = mode == RitualSoundMode.sound
        ? l10n.ritualSoundOn
        : l10n.ritualSoundOff;
    final detail = mode == RitualSoundMode.sound
        ? l10n.ritualSoundOnDescription
        : l10n.ritualSoundOffDescription;
    final selected = controller.mode == mode;
    void select() {
      controller.setMode(mode);
    }

    return Semantics(
      button: true,
      selected: selected,
      label: '$label. $detail',
      onTap: select,
      child: ExcludeSemantics(
          child: InkWell(
        key: ValueKey('ritual-sound-${mode.name}'),
        onTap: select,
        splashFactory: NoSplash.splashFactory,
        highlightColor: EastColors.of(context).ink.withValues(alpha: 0.025),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: EastTypography.localized(context, size: 23)),
                  const SizedBox(height: 10),
                  Text(detail,
                      style: EastTypography.localized(context,
                          size: 17,
                          height: 1.45,
                          color: eastMutedTextColor(context))),
                ])),
            const SizedBox(width: 20),
            SizedBox(
                width: 20,
                height: 30,
                child: selected
                    ? Icon(Icons.check,
                        size: 19, color: EastColors.of(context).ink)
                    : null),
          ]),
        ),
      )),
    );
  }
}
