import 'package:flutter/material.dart';

import '../l10n/east_localizations.dart';
import '../services/wisdom_localization_resolver.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';

// A fixed, explicitly labelled example. This view never selects a daily
// wisdom, reads personal writing, advances the ritual, or writes to storage.
class KeeperExperiencePreview extends StatefulWidget {
  const KeeperExperiencePreview({super.key});

  @override
  State<KeeperExperiencePreview> createState() =>
      _KeeperExperiencePreviewState();
}

enum _Preview { ritual, reflection, journal }

class _KeeperExperiencePreviewState extends State<KeeperExperiencePreview> {
  _Preview _selected = _Preview.ritual;

  TextStyle _style(double size, {bool muted = false}) =>
      EastTypography.localized(
        context,
        size: size,
        color: muted ? eastMutedTextColor(context) : EastColors.of(context).ink,
        height: 1.38,
        letterSpacing: 0.2,
      );

  String get _exampleWisdom => const WisdomLocalizationResolver().resolve(
        wisdomId: 'east_wisdom_0059',
        locale: Localizations.maybeLocaleOf(context) ?? const Locale('en'),
        persistedSnapshot: 'Peace enters slowly.',
      )!;

  @override
  Widget build(BuildContext context) {
    final l10n = eastLocalizations(context);
    final labels = [l10n.keeperWidgetTab, l10n.reflection, l10n.journal];
    return Column(
      key: const ValueKey('keeper-experience-preview'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.keeperPreviewLabel, style: _style(15, muted: true)),
        ),
        const SizedBox(height: 8),
        // Wrap rather than compress the labels at larger accessibility sizes
        // or in languages with longer names. Every tab remains a 44pt target.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          children: [
            for (final preview in _Preview.values)
              Semantics(
                selected: _selected == preview,
                child: TextButton(
                  key: ValueKey('keeper-preview-tab-${preview.name}'),
                  onPressed: () => setState(() => _selected = preview),
                  style: TextButton.styleFrom(
                    foregroundColor: EastColors.of(context).ink,
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 5),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _selected == preview
                              ? EastColors.of(context).ink
                              : Colors.transparent,
                          width: 0.7,
                        ),
                      ),
                    ),
                    child: Text(labels[preview.index],
                        style: _style(16, muted: _selected != preview)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 216),
          child: Center(
            child: switch (_selected) {
              _Preview.ritual => _ritual(),
              _Preview.reflection => _reflection(),
              _Preview.journal => _journal(),
            },
          ),
        ),
        const SizedBox(height: 14),
        Text(
          switch (_selected) {
            _Preview.ritual => l10n.keeperWidgetRitual,
            _Preview.reflection => l10n.reflectWithoutLimit,
            _Preview.journal => l10n.takeJournalWithYou,
          },
          key: const ValueKey('keeper-preview-caption'),
          textAlign: TextAlign.center,
          style: _style(16),
        ),
      ],
    );
  }

  Widget _ritual() {
    final l10n = eastLocalizations(context);
    return Column(
      key: const ValueKey('keeper-preview-ritual'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 156),
          padding: const EdgeInsets.fromLTRB(22, 19, 22, 18),
          decoration: BoxDecoration(
            color: EastColors.of(context).background,
            borderRadius: BorderRadius.circular(24),
            border:
                Border.all(color: EastColors.of(context).divider, width: 0.7),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.pause,
                  textAlign: TextAlign.center,
                  style: _style(32).copyWith(
                    color: Color.lerp(EastColors.of(context).background,
                        EastColors.of(context).ink, 0.34),
                  )),
              Text(l10n.feel, textAlign: TextAlign.center, style: _style(32)),
              const SizedBox(height: 18),
              ExcludeSemantics(
                child: Container(
                  width: 18,
                  height: 1,
                  color: EastColors.of(context).ink.withValues(alpha: 0.24),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(l10n.keeperPreviewExample, style: _style(13, muted: true)),
      ],
    );
  }

  Widget _reflection() {
    final l10n = eastLocalizations(context);
    return Container(
      key: const ValueKey('keeper-preview-reflection'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.keeperPreviewExample, style: _style(13, muted: true)),
          const SizedBox(height: 16),
          Text(_exampleWisdom, style: _style(23)),
          const SizedBox(height: 20),
          Text(l10n.keeperPreviewReflection, style: _style(20, muted: true)),
          const SizedBox(height: 18),
          Divider(
              height: 1, thickness: 0.5, color: EastColors.of(context).divider),
        ],
      ),
    );
  }

  Widget _journal() {
    final l10n = eastLocalizations(context);
    return Container(
      key: const ValueKey('keeper-preview-journal'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
      decoration: BoxDecoration(
        border: Border.all(color: EastColors.of(context).divider, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.keeperPreviewExample, style: _style(13, muted: true)),
          const SizedBox(height: 18),
          Text(_exampleWisdom, style: _style(22)),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14, top: 14),
            child: Text(l10n.keeperPreviewReflection,
                style: _style(16, muted: true)),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(MaterialLocalizations.of(context).formatDecimal(1),
                style: _style(13, muted: true)),
          ),
        ],
      ),
    );
  }
}
