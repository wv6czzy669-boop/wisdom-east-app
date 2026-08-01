import '../models/kept_migration_recovery_artifact.dart';
import '../models/kept_migration_snapshot.dart';

/// Boundary onto the two kinds of protected, immutable migration artifacts:
/// the pre-migration snapshot (retry authority for legacy data) and the
/// recovery artifact (undecodable/conflicting legacy entries).
///
/// Deliberately narrow — this is not a general artifact/database framework.
/// Both artifact kinds are write-once: once a named file has been written
/// and verified, it is never overwritten, only ever re-read.
abstract interface class KeptMigrationArtifactStore {
  Future<KeptMigrationSnapshot?> loadSnapshot(String fileName);

  Future<void> writeSnapshot(String fileName, KeptMigrationSnapshot snapshot);

  Future<KeptMigrationRecoveryArtifact?> loadRecoveryArtifact(
    String fileName,
  );

  Future<void> writeRecoveryArtifact(
    String fileName,
    KeptMigrationRecoveryArtifact artifact,
  );
}
