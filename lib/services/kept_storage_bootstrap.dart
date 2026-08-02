import '../models/kept_bootstrap_result.dart';
import '../utils/kept_diagnostics.dart';
import 'kept_migration_coordinator.dart';

/// Narrow, platform-store-free typedefs isolating [KeptStorageBootstrapper]
/// from every concrete platform dependency (SharedPreferences, the
/// filesystem, native file protection). Production wiring (`app_services.dart`)
/// supplies real closures over the real stores; tests supply fakes/spies —
/// neither side needs a broader dependency-injection mechanism than these
/// three function types.
typedef KeptMigrationRunner = Future<KeptMigrationResult> Function();
typedef KeptRepositoryFactory<R> = R Function(KeptBootstrapResult bootstrap);
typedef KeptServiceFactory<R, S> = S Function(R repository);

/// The immutable outcome of one [KeptStorageBootstrapper.run] call.
///
/// Deliberately generic over the repository/service types so this file has
/// no compile-time dependency on `KeptRepository` or
/// `SavedReflectionsService` — it only sequences *whatever* [R]/[S] the
/// caller's factories produce.
class KeptStorageBootstrapResult<R, S> {
  const KeptStorageBootstrapResult({
    required this.bootstrap,
    required this.repository,
    required this.service,
  });

  final KeptBootstrapResult bootstrap;
  final R repository;
  final S service;
}

/// Pure sequencing of the Build 26 Phase 3D-C Kept storage bootstrap:
/// run migration exactly once, map its outcome (success or failure) to a
/// content-safe [KeptBootstrapResult], and only then construct the
/// repository and service via the injected factories — never before
/// migration has resolved, and never a second time.
///
/// This class knows nothing about `SharedPreferences`, the filesystem, or
/// native file protection: [migrate] is an opaque callback, and
/// [buildRepository]/[buildService] are opaque factories. That is what
/// makes it directly unit-testable without touching real Application
/// Support storage — production (`app_services.dart`) supplies real
/// closures over the real stores; tests supply fakes.
///
/// [migrate] is awaited with no `.timeout(...)` applied here — a slow
/// migration is awaited to a definite conclusion (success or a thrown
/// [KeptMigrationException]/other error), never abandoned partway with a
/// synthesized failure.
class KeptStorageBootstrapper<R, S> {
  KeptStorageBootstrapper({
    required KeptMigrationRunner migrate,
    required KeptRepositoryFactory<R> buildRepository,
    required KeptServiceFactory<R, S> buildService,
  })  : _migrate = migrate,
        _buildRepository = buildRepository,
        _buildService = buildService;

  final KeptMigrationRunner _migrate;
  final KeptRepositoryFactory<R> _buildRepository;
  final KeptServiceFactory<R, S> _buildService;

  Future<KeptStorageBootstrapResult<R, S>>? _cached;

  /// Idempotent: the first call performs the real migration attempt and
  /// construction; every later call (including one made concurrently,
  /// before the first has resolved) awaits that exact same attempt rather
  /// than running migration again or re-mapping its result.
  Future<KeptStorageBootstrapResult<R, S>> run() {
    return _cached ??= _runOnce();
  }

  Future<KeptStorageBootstrapResult<R, S>> _runOnce() async {
    final bootstrap = await _resolveBootstrapResult();

    // Construction always happens, on both success and failure — a failed
    // migration still yields a usable (if `unavailable`) repository/service
    // pair, never a null or missing one. Deliberately outside the migration
    // try/catch above (that catch has already returned by the time control
    // reaches here): a `_buildRepository`/`_buildService` factory failure
    // must propagate as-is, never be reinterpreted as a migration failure
    // and silently downgraded to `KeptBootstrapResult.unavailable('unknown')`.
    final repository = _buildRepository(bootstrap);
    final service = _buildService(repository);
    return KeptStorageBootstrapResult<R, S>(
      bootstrap: bootstrap,
      repository: repository,
      service: service,
    );
  }

  /// Runs the migration attempt exactly once and maps its outcome to a
  /// content-safe [KeptBootstrapResult] — success or failure, never a thrown
  /// exception or stack trace beyond this point. Each branch `return`s
  /// directly rather than assigning a shared local, so the compiler can see
  /// every path definitely returns exactly once (the prior assign-from-
  /// try/both-catches shape left a `final` local that definite-assignment
  /// analysis could not prove was singly assigned, which is what the real
  /// compiler's "might already be assigned" error was about).
  Future<KeptBootstrapResult> _resolveBootstrapResult() async {
    keptDiagnostic('bootstrap-begin');
    try {
      await _migrate();
      keptDiagnostic('bootstrap-result: isReady=true');
      return const KeptBootstrapResult.ready();
    } on KeptMigrationException catch (error) {
      keptDiagnostic(
        'bootstrap-result: isReady=false errorCode=${error.stage} '
        'errorType=${error.runtimeType} message=${error.message}',
      );
      await persistKeptDiagnosticLast(
        stage: 'bootstrap',
        errorType: error.runtimeType.toString(),
        errorCode: error.stage,
        message: error.message,
      );
      return KeptBootstrapResult.unavailable(error.stage);
    } catch (error) {
      keptDiagnostic(
        'bootstrap-result: isReady=false errorCode=unknown '
        'errorType=${error.runtimeType}',
      );
      await persistKeptDiagnosticLast(
        stage: 'bootstrap',
        errorType: error.runtimeType.toString(),
        errorCode: 'unknown',
      );
      return KeptBootstrapResult.unavailable('unknown');
    }
  }
}
