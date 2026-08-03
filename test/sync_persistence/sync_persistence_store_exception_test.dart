// Build 26 Phase 4D-1 (privacy-boundary correction): SyncPersistenceStoreException
// -- direct, isolated tests of this exception type's rendering contract,
// independent of any particular store call site. Synthetic values only.
//
// The confirmed Mac defect: `toString()` used to interpolate `.cause`
// directly, so an underlying infrastructure exception's own text (which can
// itself carry an absolute filesystem path, e.g. a real
// `PathNotFoundException`'s `path = '/Users/.../east_sync_state/...'`) leaked
// through the public, typed exception. `.cause` must remain accessible for
// programmatic inspection (and tests), but must never be rendered.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_store.dart';

/// A minimal synthetic "underlying exception" whose own [toString] embeds
/// exactly the kinds of sensitive content this store must never render --
/// used only to prove that content never survives into
/// [SyncPersistenceStoreException.toString], no matter what an underlying
/// cause happens to say.
class _SyntheticSensitiveCause {
  const _SyntheticSensitiveCause(this.text);

  final String text;

  @override
  String toString() => text;
}

void main() {
  test(
      'toString renders only the stable "[stage]: message" shape when there '
      'is no cause', () {
    const exception = SyncPersistenceStoreException(
      'some-stage',
      'A static, content-safe message.',
    );
    expect(
      exception.toString(),
      'SyncPersistenceStoreException[some-stage]: A static, content-safe '
      'message.',
    );
  });

  test('toString never renders the cause, even when one is present', () {
    const exception = SyncPersistenceStoreException(
      'some-stage',
      'A static, content-safe message.',
      'a raw underlying error whose own text must never be rendered',
    );
    expect(
      exception.toString(),
      'SyncPersistenceStoreException[some-stage]: A static, content-safe '
      'message.',
    );
    expect(exception.toString(), isNot(contains('a raw underlying error')));
  });

  test('.cause remains accessible for programmatic inspection', () {
    final cause = Exception('synthetic underlying failure');
    final exception = SyncPersistenceStoreException(
      'some-stage',
      'A static, content-safe message.',
      cause,
    );
    expect(exception.cause, same(cause));
  });

  test(
      'a synthetic cause carrying a token, fingerprint, record name and raw '
      'JSON payload is retained in .cause but never appears in toString, '
      'across every stage this store currently throws', () {
    const sensitiveToken = 'b3BhcXVlLXNlbnNpdGl2ZS10b2tlbg==';
    const sensitiveFingerprint =
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
    const sensitiveRecordName =
        'east-kept-aaaaaaaa-1111-4111-8111-111111111111';
    const sensitiveMutationId = 'aaaa0000-0000-4000-8000-000000000099';
    final sensitiveJson = '{"serverChangeToken":"$sensitiveToken",'
        '"recordName":"$sensitiveRecordName",'
        '"mutationId":"$sensitiveMutationId"}';
    final syntheticCause = _SyntheticSensitiveCause(
      'FileSystemException: failed for path=/Users/example/Library/'
      'Application Support/east_sync_state/east_sync_state_v1.json '
      'account=$sensitiveFingerprint record=$sensitiveRecordName '
      'mutation=$sensitiveMutationId token=$sensitiveToken '
      'json=$sensitiveJson',
    );

    // Every stage this store's production code currently throws (kept in
    // sync manually with `lib/sync_persistence/protected_sync_persistence_store.dart`
    // -- not derived from it -- since the exception type itself has no
    // enumerable stage list).
    const allKnownStages = [
      'load-read',
      'load-decode',
      'load-protect',
      'load-recover-list',
      'load-recover-write-temp',
      'load-recover-protect-temp',
      'load-recover-verify-temp',
      'load-recover-rename',
      'load-recover-protect-final',
      'load-recover-verify-final',
      'replace-write-temp',
      'replace-protect-temp',
      'replace-verify-temp',
      'replace-backup',
      'replace-rename',
      'replace-verify-final',
      'replace-post-rename',
      'replace-rollback-verify',
      'replace-rollback',
      'directory-resolve',
      'directory-create',
      'directory-protect',
      'system-fields-no-account-state',
      'store-token-no-account-state',
    ];

    for (final stage in allKnownStages) {
      final exception = SyncPersistenceStoreException(
        stage,
        'A static, content-safe message for this stage.',
        syntheticCause,
      );

      // Retained internally for programmatic inspection...
      expect(exception.cause, same(syntheticCause));

      // ...but never rendered.
      final rendered = exception.toString();
      expect(rendered, contains('[$stage]'));
      expect(rendered, isNot(contains(sensitiveToken)));
      expect(rendered, isNot(contains(sensitiveFingerprint)));
      expect(rendered, isNot(contains(sensitiveRecordName)));
      expect(rendered, isNot(contains(sensitiveMutationId)));
      expect(rendered, isNot(contains(sensitiveJson)));
      expect(rendered, isNot(contains('FileSystemException')));
      expect(rendered, isNot(contains('east_sync_state')));
    }
  });
}
