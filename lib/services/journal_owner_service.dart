import '../persistence/journal_owner_store.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/storage_preferences_adapter.dart';
import '../utils/journal_owner_name_policy.dart';

/// EAST. Phase 10 — Journal's own device-local "whose journal is this"
/// preference.
///
/// Deliberately narrow: this is the entire surface. No account/profile
/// model, no CloudKit sync, no analytics. See each method's own doc
/// comment for the exact privacy contract.
class JournalOwnerService {
  JournalOwnerService({
    StoragePreferencesAdapter? preferencesAdapter,
    JournalOwnerStore? ownerStore,
    PersistenceOperationCoordinator? operationCoordinator,
  })  : _preferencesAdapter = preferencesAdapter ?? StoragePreferencesAdapter(),
        _ownerStore = ownerStore ?? ProtectedJournalOwnerStore(),
        _operationCoordinator =
            operationCoordinator ?? PersistenceOperationCoordinator();

  static const String nameKey = 'east_journal_owner_name';
  static const String promptHandledKey = 'east_journal_name_prompt_handled';

  final StoragePreferencesAdapter _preferencesAdapter;
  final JournalOwnerStore _ownerStore;
  final PersistenceOperationCoordinator _operationCoordinator;
  static const String _resourceKey = 'journal_owner_service';

  /// The saved owner name, already trimmed, or `null` if none is saved.
  /// Device-local only -- never read from or written to CloudKit, and
  /// never logged. A persistence failure fails safe to `null`: Journal
  /// generation always proceeds, with or without a name.
  Future<String?> loadName() async {
    return _operationCoordinator.runExclusive<String?>(
      resourceKey: _resourceKey,
      operation: () async {
        try {
          final protectedName = await _ownerStore.loadName();
          if (protectedName != null) {
            await _removeLegacyNameBestEffort();
            return JournalOwnerNamePolicy.normalize(protectedName);
          }
        } catch (_) {
          // Fall through to the legacy value. A protected-store outage must
          // never make a previously-saved Journal owner disappear.
        }

        final legacy = await _loadLegacyNameBestEffort();
        if (legacy == null) return null;
        try {
          await _ownerStore.writeName(legacy);
          if (await _ownerStore.loadName() == legacy) {
            await _removeLegacyNameBestEffort();
          }
        } catch (_) {
          // Keep and return the legacy value until a later load can migrate
          // it safely. Never delete the only durable copy first.
        }
        return JournalOwnerNamePolicy.normalize(legacy);
      },
    );
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
    final normalized = JournalOwnerNamePolicy.normalize(name);
    try {
      await _operationCoordinator.runExclusive<void>(
        resourceKey: _resourceKey,
        operation: () async {
          await _ownerStore.writeName(normalized);
          if (normalized == null ||
              await _ownerStore.loadName() == normalized) {
            await _removeLegacyNameBestEffort();
          }
        },
      );
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
      await _operationCoordinator.runExclusive<void>(
        resourceKey: _resourceKey,
        operation: () async {
          await _ownerStore.writeName(null);
          await _removeLegacyNameBestEffort();
        },
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<String?> _loadLegacyNameBestEffort() async {
    try {
      final raw = await _preferencesAdapter.getString(nameKey);
      return JournalOwnerNamePolicy.normalize(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeLegacyNameBestEffort() async {
    try {
      await _preferencesAdapter.remove(nameKey);
    } catch (_) {
      // A duplicate legacy value is safer than deleting before verification.
    }
  }
}
