import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/models/kept_migration_journal.dart';
import 'package:wisdom_app/models/kept_migration_recovery_artifact.dart';
import 'package:wisdom_app/models/kept_migration_snapshot.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';
import 'package:wisdom_app/persistence/kept_migration_artifact_store.dart';
import 'package:wisdom_app/persistence/kept_migration_journal_store.dart';
import 'package:wisdom_app/persistence/kept_state_store.dart';
import 'package:wisdom_app/persistence/protected_file_kept_state_store.dart'
    show KeptStateStoreException;
import 'package:wisdom_app/persistence/protected_kept_migration_artifact_store.dart'
    show KeptMigrationArtifactStoreException;
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/daily_access_repository.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef PersistString = Future<void> Function();
typedef ReadString = Future<String?> Function();
typedef PersistRemove = Future<void> Function();
typedef GetStringInterceptor = Future<String?> Function(
  String key,
  ReadString read,
);
typedef SetStringInterceptor = Future<void> Function(
  String key,
  String value,
  PersistString persist,
);
typedef RemoveInterceptor = Future<void> Function(
  String key,
  PersistRemove persist,
);

class InterceptingStoragePreferencesAdapter extends StoragePreferencesAdapter {
  InterceptingStoragePreferencesAdapter({
    super.preferencesProvider,
    this.getStringInterceptor,
    this.setStringInterceptor,
    this.removeInterceptor,
  });

  final GetStringInterceptor? getStringInterceptor;
  final SetStringInterceptor? setStringInterceptor;
  final RemoveInterceptor? removeInterceptor;

  @override
  Future<String?> getString(String key) async {
    final interceptor = getStringInterceptor;
    if (interceptor == null) {
      return super.getString(key);
    }

    return interceptor(key, () => super.getString(key));
  }

  @override
  Future<void> setString(String key, String value) async {
    final interceptor = setStringInterceptor;
    if (interceptor == null) {
      await super.setString(key, value);
      return;
    }

    await interceptor(key, value, () => super.setString(key, value));
  }

  @override
  Future<void> remove(String key) async {
    final interceptor = removeInterceptor;
    if (interceptor == null) {
      await super.remove(key);
      return;
    }

    await interceptor(key, () => super.remove(key));
  }
}

class DailyAccessTestGraph {
  DailyAccessTestGraph({
    StoragePreferencesAdapter? adapter,
    PersistenceOperationCoordinator? coordinator,
    Future<void> Function(SharedPreferences prefs, String key)?
        obsoleteKeyRemover,
    Future<void> Function(SharedPreferences prefs, String key)?
        pendingRevealRemover,
    WisdomClock? clock,
    Duration statusTimeout = DailyWisdomAccessService.defaultStatusTimeout,
  })  : adapter = adapter ?? StoragePreferencesAdapter(),
        coordinator = coordinator ?? PersistenceOperationCoordinator() {
    repository = DailyAccessRepository(
      preferencesAdapter: this.adapter,
      operationCoordinator: this.coordinator,
      obsoleteKeyRemover: obsoleteKeyRemover,
      pendingRevealRemover: pendingRevealRemover,
    );
    service = DailyWisdomAccessService(
      repository: repository,
      clock: clock,
      statusTimeout: statusTimeout,
    );
  }

  final StoragePreferencesAdapter adapter;
  final PersistenceOperationCoordinator coordinator;
  late final DailyAccessRepository repository;
  late final DailyWisdomAccessService service;
}

/// Deterministic, in-memory [KeptStateStore] for tests. Never touches the
/// filesystem or platform channels. Holds exactly one [KeptStateEnvelope] in
/// memory (or none, before the first [replace]), mirroring the "no
/// authoritative envelope has ever been created yet" contract
/// [KeptStateStore.load] documents.
///
/// [failLoad]/[failReplace], when set, make the next matching call throw a
/// [KeptStateStoreException] instead of touching [envelope] — for tests that
/// need to exercise `KeptRepository`'s own store-failure mapping.
class InMemoryKeptStateStore implements KeptStateStore {
  KeptStateEnvelope? envelope;
  Object? failLoad;
  Object? failReplace;

  @override
  Future<KeptStateEnvelope?> load() async {
    final failure = failLoad;
    if (failure != null) {
      failLoad = null;
      throw failure;
    }
    return envelope;
  }

  @override
  Future<void> replace(KeptStateEnvelope newEnvelope) async {
    final failure = failReplace;
    if (failure != null) {
      failReplace = null;
      throw failure;
    }
    envelope = newEnvelope;
  }
}

/// Round-trips every [replace] through real JSON encode/decode
/// (`KeptStateEnvelope.encodeString()`/`decodeString()`) before ever
/// considering it durable — comparing the decoded-back envelope against the
/// intended one by value first, exactly mirroring the mandatory post-write
/// verification `ProtectedFileKeptStateStore._replace` performs on its
/// temporary file before ever renaming it into place (see that class's
/// steps 10-11). [load] likewise always decodes from the last successfully
/// stored JSON string rather than returning a retained object reference.
///
/// This is deliberately different from [InMemoryKeptStateStore], which
/// stores the `KeptStateEnvelope` object directly and therefore can never
/// reproduce a defect that only manifests through genuine JSON
/// serialization — such as the Phase 3D-D real-device migration failure,
/// where a legacy `reflectedAt` value's genuine sub-millisecond precision
/// survived into an in-memory migrated `KeptRecord` but was silently
/// dropped by `KeptRecord.encode()`'s millisecond-only wire format,
/// making the freshly-decoded read-back compare unequal to the in-memory
/// original. Use this store specifically when a test needs to prove
/// something about that real persistence round-trip, not just about the
/// migration/repository logic sitting on top of it.
class JsonRoundTrippingKeptStateStore implements KeptStateStore {
  String? _encoded;

  /// Forces every subsequent [replace] to fail verification regardless of
  /// content — for tests proving "a failure before verification leaves the
  /// prior state untouched" without depending on any particular content
  /// defect to trigger it.
  bool forceVerifyFailure = false;

  /// Call counters, mirroring the pattern already used by
  /// `_CountingKeptStateStore` (`kept_storage_bootstrap_test.dart`) and the
  /// coordinator suite's own fakes — so a test can assert exactly how many
  /// times the store was actually touched (e.g. proving an idempotent
  /// no-op mutation never calls [replace]).
  int loadCallCount = 0;
  int replaceCallCount = 0;

  @override
  Future<KeptStateEnvelope?> load() async {
    loadCallCount += 1;
    final encoded = _encoded;
    if (encoded == null) return null;
    return KeptStateEnvelope.decodeString(encoded);
  }

  @override
  Future<void> replace(KeptStateEnvelope envelope) async {
    replaceCallCount += 1;
    final encoded = envelope.encodeString();
    final decoded = KeptStateEnvelope.decodeString(encoded);
    if (forceVerifyFailure || decoded != envelope) {
      throw const KeptStateStoreException(
        'replace-verify-temp',
        'Temporary kept-state file did not match the intended envelope.',
      );
    }
    _encoded = encoded;
  }
}

/// Round-trips every `writeSnapshot`/`writeRecoveryArtifact` through real
/// JSON encode/decode before ever considering it durable — the same
/// reasoning as [JsonRoundTrippingKeptStateStore] above, applied to the
/// Phase 3C migration artifact store. An object-retaining fake (like
/// `_FakeArtifactStore` in `kept_migration_coordinator_test.dart`) stores
/// the `KeptMigrationSnapshot`/`KeptMigrationRecoveryArtifact` instance
/// directly and can never reproduce a defect that only manifests through
/// genuine JSON serialization — such as the Phase 3D-D real-device
/// `snapshot-write` failure, where a snapshot's genuinely
/// sub-millisecond-precision `capturedAt` survived into the in-memory
/// snapshot but was silently dropped by `KeptMigrationSnapshot.encode()`'s
/// millisecond-only wire format, making the freshly-decoded read-back
/// compare unequal to the in-memory original.
///
/// Mirrors `ProtectedKeptMigrationArtifactStore._writeArtifact`'s own
/// mandatory write-then-read-back verification exactly: a round-trip
/// mismatch throws [KeptMigrationArtifactStoreException] with stage
/// `'write-verify-temp'`, the same stage a real protected-file mismatch
/// would report.
class JsonRoundTrippingKeptMigrationArtifactStore
    implements KeptMigrationArtifactStore {
  final Map<String, String> _encodedSnapshots = {};
  final Map<String, String> _encodedRecoveryArtifacts = {};

  /// Forces every subsequent `writeSnapshot`/`writeRecoveryArtifact` call to
  /// fail verification regardless of content — for tests proving "a
  /// failure before verification leaves prior state untouched" without
  /// depending on a particular content defect to trigger it.
  bool forceVerifyFailure = false;

  int writeSnapshotCallCount = 0;
  int writeRecoveryArtifactCallCount = 0;

  @override
  Future<KeptMigrationSnapshot?> loadSnapshot(String fileName) async {
    final encoded = _encodedSnapshots[fileName];
    if (encoded == null) return null;
    return KeptMigrationSnapshot.decodeString(encoded);
  }

  @override
  Future<void> writeSnapshot(
    String fileName,
    KeptMigrationSnapshot snapshot,
  ) async {
    writeSnapshotCallCount += 1;
    final encoded = snapshot.encodeString();
    final decoded = KeptMigrationSnapshot.decodeString(encoded);
    if (forceVerifyFailure || decoded != snapshot) {
      throw const KeptMigrationArtifactStoreException(
        'write-verify-temp',
        'Temporary artifact file did not match the intended content.',
      );
    }
    _encodedSnapshots[fileName] = encoded;
  }

  @override
  Future<KeptMigrationRecoveryArtifact?> loadRecoveryArtifact(
    String fileName,
  ) async {
    final encoded = _encodedRecoveryArtifacts[fileName];
    if (encoded == null) return null;
    return KeptMigrationRecoveryArtifact.decodeString(encoded);
  }

  @override
  Future<void> writeRecoveryArtifact(
    String fileName,
    KeptMigrationRecoveryArtifact artifact,
  ) async {
    writeRecoveryArtifactCallCount += 1;
    final encoded = artifact.encodeString();
    final decoded = KeptMigrationRecoveryArtifact.decodeString(encoded);
    if (forceVerifyFailure || decoded != artifact) {
      throw const KeptMigrationArtifactStoreException(
        'write-verify-temp',
        'Temporary artifact file did not match the intended content.',
      );
    }
    _encodedRecoveryArtifacts[fileName] = encoded;
  }
}

/// Round-trips every `save` through real JSON encode/decode before ever
/// considering the migration journal durable — the journal counterpart to
/// [JsonRoundTrippingKeptMigrationArtifactStore] and
/// [JsonRoundTrippingKeptStateStore] above, exercising
/// `KeptMigrationJournal.encode()`/`decode()`'s real millisecond-only wire
/// format against `operator==`'s exact `isAtSameMomentAs` comparison on
/// `startedAt`/`updatedAt`.
class JsonRoundTrippingKeptMigrationJournalStore
    implements KeptMigrationJournalStore {
  String? _encoded;
  int saveCallCount = 0;

  @override
  Future<KeptMigrationJournal?> load() async {
    final encoded = _encoded;
    if (encoded == null) return null;
    return KeptMigrationJournal.decodeString(encoded);
  }

  @override
  Future<void> save(KeptMigrationJournal journal) async {
    saveCallCount += 1;
    final encoded = journal.encodeString();
    final decoded = KeptMigrationJournal.decodeString(encoded);
    if (decoded != journal) {
      throw const KeptMigrationJournalStoreException(
        'save-verify',
        'The migration journal read-back did not match the intended value.',
      );
    }
    _encoded = encoded;
  }
}

/// Test-only wiring for the Build 26 Phase 3D-C protected Kept repository
/// graph, mirroring [DailyAccessTestGraph]'s role for daily access.
///
/// Every production `SavedReflectionsService` caller (`HomeScreen`,
/// `SavedReflectionsScreen`, `ReflectionScreen`) now reaches the Kept store
/// only through `KeptRepository`, so a widget test that wants to seed
/// "already kept" state, or read back what a widget interaction persisted,
/// needs the exact same [KeptRepository] instance the widget itself was
/// built with — never a disconnected second instance pointed at a different
/// in-memory store. Constructing one [KeptRepositoryTestGraph] and passing
/// its [service] into the widget under test (and reading [store].envelope /
/// calling [service].load() afterward) keeps both sides of a test looking at
/// the same protected state.
class KeptRepositoryTestGraph {
  KeptRepositoryTestGraph({
    KeptBootstrapResult bootstrap = const KeptBootstrapResult.ready(),
    KeptClock? clock,
    KeptIdFactory? idFactory,
    int freeKeptLimit = 3,
    int freeReflectionLimit = 3,
  }) : store = InMemoryKeptStateStore() {
    repository = KeptRepository(
      store: store,
      bootstrap: bootstrap,
      operationCoordinator: PersistenceOperationCoordinator(),
      clock: clock,
      idFactory: idFactory,
      freeKeptLimit: freeKeptLimit,
      freeReflectionLimit: freeReflectionLimit,
    );
    service = SavedReflectionsService(keptRepository: repository);
  }

  final InMemoryKeptStateStore store;
  late final KeptRepository repository;
  late final SavedReflectionsService service;

  /// Seeds [store] directly with [records] as the authoritative active
  /// records — for tests that need a deterministic "already kept" starting
  /// state without going through `keepOccurrence` (and its own generated
  /// id/mutationId/clock).
  void seed(List<KeptRecord> records) {
    store.envelope = KeptStateEnvelope(activeRecords: records);
  }
}
