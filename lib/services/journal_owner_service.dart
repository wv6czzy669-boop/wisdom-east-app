import '../persistence/storage_preferences_adapter.dart';

/// EAST. Phase 10 — Journal's own device-local "whose journal is this"
/// preference.
///
/// Deliberately narrow: this is the entire surface. No account/profile
/// model, no CloudKit sync, no analytics. See each method's own doc
/// comment for the exact privacy contract.
class JournalOwnerService {
  JournalOwnerService({StoragePreferencesAdapter? preferencesAdapter})
      : _preferencesAdapter = preferencesAdapter ?? StoragePreferencesAdapter();

  static const String nameKey = 'east_journal_owner_name';
  static const String promptHandledKey = 'east_journal_name_prompt_handled';

  final StoragePreferencesAdapter _preferencesAdapter;

  /// The saved owner name, already trimmed, or `null` if none is saved.
  /// Device-local only -- never read from or written to CloudKit, and
  /// never logged. A persistence failure fails safe to `null`: Journal
  /// generation always proceeds, with or without a name.
  Future<String?> loadName() async {
    try {
      final raw = await _preferencesAdapter.getString(nameKey);
      final trimmed = raw?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  /// Whether the first-run "whose journal is this" step has already been
  /// resolved once -- by a saved name or by Skip -- so Journal never asks
  /// again. Fails safe to `false` on a read failure, which only means the
  /// step may be (harmlessly) offered once more.
  Future<bool> hasHandledNamePrompt() async {
    try {
      return await _preferencesAdapter.getBool(promptHandledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Saves [name] (trimmed of surrounding whitespace) and marks the
  /// first-run step handled. A blank/whitespace-only [name] is treated
  /// exactly like [skip] -- never persisted as an empty string. Best-effort
  /// only: a persistence failure here never blocks or fails Journal
  /// generation itself.
  Future<void> saveName(String name) async {
    final trimmed = name.trim();
    try {
      if (trimmed.isEmpty) {
        await _preferencesAdapter.remove(nameKey);
      } else {
        await _preferencesAdapter.setString(nameKey, trimmed);
      }
      await _preferencesAdapter.setBool(promptHandledKey, true);
    } catch (_) {
      // Best-effort only -- see the doc comment above.
    }
  }

  /// Records the first-run step as handled with no name saved. Journal
  /// generation must never be blocked on this call actually completing.
  Future<void> skip() async {
    try {
      await _preferencesAdapter.setBool(promptHandledKey, true);
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Removes any saved name without touching whether the first-run step
  /// has been handled -- used by the "remove name" affordance inside
  /// Journal itself, never by the first-run step.
  Future<void> clearName() async {
    try {
      await _preferencesAdapter.remove(nameKey);
    } catch (_) {
      // Best-effort only.
    }
  }
}
