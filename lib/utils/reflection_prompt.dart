import '../l10n/app_localizations.dart';

/// EAST. Phase 8 — the six approved Reflection prompts and the
/// deterministic, occurrence-keyed selection among them.
///
/// Exactly one prompt is ever shown per occurrence. Selection is a pure
/// function of a stable identity key (a Kept occurrence's `revealId`, or
/// its `id` when no `revealId` exists yet — see [reflectionPromptIndexFor]'s
/// own call sites), so it needs no persisted "which prompt was chosen"
/// field of its own to stay stable across rebuild, relaunch, edit, sync,
/// reopen, or a change of the app's selected language.
///
/// This canonical English list is the fixed *identity order* — index 0 is
/// "prompt A", index 5 is "prompt F", forever — never reordered, extended,
/// or shortened casually, since [reflectionPromptIndexFor]'s checksum
/// selection is defined purely in terms of this list's length. Only ever
/// used directly by legacy/back-compat callers and tests that pin the
/// canonical English wording itself; production presentation instead goes
/// through [localizedReflectionPrompts], indexed by
/// [reflectionPromptIndexFor].
const List<String> reflectionPrompts = [
  'What remains?',
  'What stayed with you?',
  'What became clearer?',
  'What are you noticing now?',
  'What feels different?',
  'What would you like to carry forward?',
];

/// Phase 5G: the same six prompts, in the exact same order as
/// [reflectionPrompts], resolved through [l10n] for the current EAST.
/// locale. Locale switching changes only which list this returns from —
/// never which *index* [reflectionPromptIndexFor] picks.
List<String> localizedReflectionPrompts(AppLocalizations l10n) => [
      l10n.reflectionPromptWhatRemains,
      l10n.reflectionPromptWhatStayedWithYou,
      l10n.reflectionPromptWhatBecameClearer,
      l10n.reflectionPrompt,
      l10n.reflectionPromptWhatFeelsDifferent,
      l10n.reflectionPromptCarryForward,
    ];

/// Deterministically resolves [key] to an index into [reflectionPrompts]/
/// [localizedReflectionPrompts] — the stable prompt *identity* itself,
/// independent of presentation language.
///
/// Deliberately not based on [key]'s own `String.hashCode`: Dart makes no
/// public promise that `hashCode` is stable across app relaunches, Dart/
/// Flutter versions, or even repeated runs of the same process — only that
/// equal strings hash equally *within* one such run. A prompt that changed
/// on relaunch would violate the one-prompt-per-occurrence contract. This
/// instead sums [key]'s UTF-16 code units into an explicit, always-portable
/// checksum.
int reflectionPromptIndexFor(String key) {
  var checksum = 0;
  for (final codeUnit in key.codeUnits) {
    // Keeps the running total within a safe, fixed-width range on every
    // platform (including compiled-to-JS web, where `int` is a double) —
    // the modulus itself has no bearing on which prompt is picked, since
    // the final `%reflectionPrompts.length` below only ever depends on the
    // checksum's value relative to that length.
    checksum = (checksum + codeUnit) % 1000003;
  }
  return checksum % reflectionPrompts.length;
}

/// Back-compat/legacy-callers-only accessor: the canonical *English*
/// wording for [key]'s deterministically selected prompt. Production
/// presentation must use [reflectionPromptIndexFor] +
/// [localizedReflectionPrompts] instead, so the shown text tracks the
/// current EAST. locale; this always returns the fixed English source text
/// regardless of locale, by construction — the exact prior behavior of
/// this function, preserved unchanged for anything that still calls it.
String reflectionPromptFor(String key) =>
    reflectionPrompts[reflectionPromptIndexFor(key)];
