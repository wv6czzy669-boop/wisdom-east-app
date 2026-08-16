/// EAST. Phase 8 — the six approved Reflection prompts and the
/// deterministic, occurrence-keyed selection among them.
///
/// Exactly one prompt is ever shown per occurrence. Selection is a pure
/// function of a stable identity key (a Kept occurrence's `revealId`, or
/// its `id` when no `revealId` exists yet — see [reflectionPromptFor]'s own
/// call sites), so it needs no persisted "which prompt was chosen" field of
/// its own to stay stable across rebuild, relaunch, edit, sync, or reopen.
const List<String> reflectionPrompts = [
  'What remains?',
  'What stayed with you?',
  'What became clearer?',
  'What are you noticing now?',
  'What feels different?',
  'What would you like to carry forward?',
];

/// Deterministically resolves [key] to exactly one of [reflectionPrompts].
///
/// Deliberately not based on [key]'s own `String.hashCode`: Dart makes no
/// public promise that `hashCode` is stable across app relaunches, Dart/
/// Flutter versions, or even repeated runs of the same process — only that
/// equal strings hash equally *within* one such run. A prompt that changed
/// on relaunch would violate the one-prompt-per-occurrence contract. This
/// instead sums [key]'s UTF-16 code units into an explicit, always-portable
/// checksum.
String reflectionPromptFor(String key) {
  var checksum = 0;
  for (final codeUnit in key.codeUnits) {
    // Keeps the running total within a safe, fixed-width range on every
    // platform (including compiled-to-JS web, where `int` is a double) —
    // the modulus itself has no bearing on which prompt is picked, since
    // the final `%reflectionPrompts.length` below only ever depends on the
    // checksum's value relative to that length.
    checksum = (checksum + codeUnit) % 1000003;
  }
  return reflectionPrompts[checksum % reflectionPrompts.length];
}
