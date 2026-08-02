import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/utils/kept_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('keptDiagnostic', () {
    test('1. never throws for an ordinary message', () {
      expect(() => keptDiagnostic('stage-begin: some-stage'), returnsNormally);
    });

    test('2. never throws for an empty message', () {
      expect(() => keptDiagnostic(''), returnsNormally);
    });
  });

  group('persistKeptDiagnosticLast', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
        '3. persists stage and errorType, joined with the documented '
        'separator, when only those are supplied', () async {
      final adapter = StoragePreferencesAdapter();

      await persistKeptDiagnosticLast(
        stage: 'directory-protect',
        errorType: 'MissingPluginException',
        preferencesAdapter: adapter,
      );

      final stored = await adapter.getString(keptDiagnosticLastKey);
      expect(stored, isNotNull);
      expect(stored, contains('stage=directory-protect'));
      expect(stored, contains('errorType=MissingPluginException'));
      expect(stored, isNot(contains('errorCode=')));
      expect(stored, isNot(contains('message=')));
    });

    test('4. persists errorCode and message when both are supplied', () async {
      final adapter = StoragePreferencesAdapter();

      await persistKeptDiagnosticLast(
        stage: 'replace-verify-temp',
        errorType: 'KeptStateStoreException',
        errorCode: 'replace-verify-temp',
        message: 'Temporary kept-state file did not match the intended '
            'envelope.',
        preferencesAdapter: adapter,
      );

      final stored = await adapter.getString(keptDiagnosticLastKey);
      expect(stored, contains('stage=replace-verify-temp'));
      expect(stored, contains('errorType=KeptStateStoreException'));
      expect(stored, contains('errorCode=replace-verify-temp'));
      expect(
        stored,
        contains(
          'message=Temporary kept-state file did not match the intended '
          'envelope.',
        ),
      );
    });

    test(
        '5. a later call overwrites the prior breadcrumb (only the single '
        'most recent diagnostic is ever retained)', () async {
      final adapter = StoragePreferencesAdapter();

      await persistKeptDiagnosticLast(
        stage: 'first-stage',
        errorType: 'FirstError',
        preferencesAdapter: adapter,
      );
      await persistKeptDiagnosticLast(
        stage: 'second-stage',
        errorType: 'SecondError',
        preferencesAdapter: adapter,
      );

      final stored = await adapter.getString(keptDiagnosticLastKey);
      expect(stored, isNot(contains('first-stage')));
      expect(stored, contains('second-stage'));
      expect(stored, contains('SecondError'));
    });

    test(
        '6. a failure in the underlying preferences adapter is swallowed, '
        'never rethrown (best-effort only)', () async {
      final failingAdapter = StoragePreferencesAdapter(
        preferencesProvider: () async =>
            throw StateError('simulated preferences failure'),
      );

      await expectLater(
        persistKeptDiagnosticLast(
          stage: 'any-stage',
          errorType: 'AnyError',
          preferencesAdapter: failingAdapter,
        ),
        completes,
      );
    });

    test(
        '7. the persisted key is clearly named as temporary and distinct '
        'from every real production Kept-state/migration key', () {
      expect(keptDiagnosticLastKey, contains('TEMPORARY'));
      expect(
          keptDiagnosticLastKey,
          isNot('east_kept_storage_migration_v3_'
              'journal'));
      expect(keptDiagnosticLastKey, isNot('favorites'));
    });
  });

  group('keptDiagnosticLogPrefix', () {
    test('8. is the exact stable prefix documented for real-device capture',
        () {
      expect(keptDiagnosticLogPrefix, 'EAST_KEPT_DIAGNOSTIC');
    });
  });

  group('kDebugMode gating (documentation-level check)', () {
    test(
        '9. kDebugMode is true under flutter test, so this suite exercises '
        'the real (non-no-op) code paths above — not a false-positive '
        'pass from an early return', () {
      expect(kDebugMode, isTrue);
    });
  });
}
