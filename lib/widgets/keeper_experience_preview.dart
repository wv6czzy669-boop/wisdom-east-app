import 'package:flutter/material.dart';

import '../l10n/east_localizations.dart';
import '../services/wisdom_localization_resolver.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';

// Fixed examples and a Journal invitation. Personal writing is never
// displayed here; the parent owns navigation to the protected Journal.
class KeeperExperiencePreview extends StatefulWidget {
  const KeeperExperiencePreview({
    super.key,
    this.journalHasEntries,
    this.journalLoadFailed = false,
    this.onJournalSelected,
    this.onOpenJournal,
  });

  final bool? journalHasEntries;
  final bool journalLoadFailed;
  final VoidCallback? onJournalSelected;
  final VoidCallback? onOpenJournal;

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
                  onPressed: () {
                    setState(() => _selected = preview);
                    if (preview == _Preview.journal) {
                      widget.onJournalSelected?.call();
                    }
                  },
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
            _Preview.journal => l10n.keeperJournalExport,
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
    final empty = widget.journalHasEntries == false;
    final action = widget.journalLoadFailed
        ? widget.onJournalSelected
        : widget.journalHasEntries == true
            ? widget.onOpenJournal
            : null;
    final actionLabel =
        widget.journalLoadFailed ? l10n.retry : l10n.keeperJournalOpen;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Semantics(
        button: action != null,
        onTap: action,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('keeper-preview-journal'),
            onTap: action,
            excludeFromSemantics: true,
            splashFactory: NoSplash.splashFactory,
            highlightColor: EastColors.of(context).ink.withValues(alpha: 0.025),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 196),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                border: Border.all(
                    color: EastColors.of(context).divider, width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.keeperJournalTitle, style: _style(25)),
                  const SizedBox(height: 14),
                  Text(l10n.keeperJournalDescription,
                      style: _style(17, muted: true)),
                  const SizedBox(height: 26),
                  if (empty)
                    Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(l10n.keeperJournalEmpty,
                          key: const ValueKey('keeper-journal-empty'),
                          style: _style(16, muted: true)),
                    )
                  else ...[
                    if (widget.journalLoadFailed) ...[
                      Text(l10n.journalCouldNotBePrepared,
                          style: _style(16, muted: true)),
                      const SizedBox(height: 12),
                    ],
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(actionLabel,
                                key: const ValueKey('keeper-journal-open'),
                                style: _style(18, muted: action == null)),
                          ),
                          const SizedBox(width: 12),
                          ExcludeSemantics(
                            child: Icon(Icons.arrow_forward,
                                size: 18,
                                color: action == null
                                    ? eastMutedTextColor(context)
                                    : EastColors.of(context).ink),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
