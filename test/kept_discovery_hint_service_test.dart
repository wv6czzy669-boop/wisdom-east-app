import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/services/kept_discovery_hint_service.dart';

/// A `StoragePreferencesAdapter` whose bool/int writes always throw, used to
/// prove the service's documented "a persistence failure is non-critical"
/// behavior without needing a real plugin-level failure.
class _ThrowingWriteAdapter extends StoragePreferencesAdapter {
  @override
  Future<void> setBool(String key, bool value) async {
    throw const PersistenceException('simulated bool write failure');
  }

  @override
  Future<void> setInt(String key, int value) async {
    throw const PersistenceException('simulated int write failure');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('KeptDiscoveryHintService — defaults', () {
    test(
        'a missing count defaults to 0 and a missing completion flag '
        'defaults to false, with no migration required', () async {
      final service = KeptDiscoveryHintService();

      expect(await service.displayCount(), 0);
      expect(await service.isCompleted(), isFalse);
      expect(await service.isEligible(), isTrue);
    });
  });

  group('KeptDiscoveryHintService — display cap', () {
    test('is eligible for the first two displays, then never again', () async {
      final service = KeptDiscoveryHintService();

      expect(await service.isEligible(), isTrue);
      await service.recordDisplayShown();
      expect(await service.displayCount(), 1);
      expect(await service.isEligible(), isTrue);

      await service.recordDisplayShown();
      expect(await service.displayCount(), 2);
      expect(await service.isEligible(), isFalse);

      // A count already at (or somehow beyond) the cap remains ineligible.
      await service.recordDisplayShown();
      expect(await service.displayCount(), 3);
      expect(await service.isEligible(), isFalse);
    });

    test(
        'the display count persists across a fresh service instance backed '
        'by the same SharedPreferences store', () async {
      final first = KeptDiscoveryHintService();
      await first.recordDisplayShown();

      final second = KeptDiscoveryHintService();
      expect(await second.displayCount(), 1);
      expect(await second.isEligible(), isTrue);
    });
  });

  group('KeptDiscoveryHintService — completion', () {
    test('marking completed makes the service permanently ineligible',
        () async {
      final service = KeptDiscoveryHintService();

      await service.markCompleted();
      expect(await service.isCompleted(), isTrue);
      expect(await service.isEligible(), isFalse);
    });

    test(
        'completion persists across a fresh service instance backed by the '
        'same SharedPreferences store', () async {
      final first = KeptDiscoveryHintService();
      await first.markCompleted();

      final second = KeptDiscoveryHintService();
      expect(await second.isCompleted(), isTrue);
      expect(await second.isEligible(), isFalse);
    });

    test('completed takes priority over display count when both are set',
        () async {
      SharedPreferences.setMockInitialValues({
        KeptDiscoveryHintService.hintCountKey: 1,
        KeptDiscoveryHintService.completedKey: true,
      });
      final service = KeptDiscoveryHintService();

      expect(await service.isEligible(), isFalse);
    });
  });

  group('KeptDiscoveryHintService — persistence-failure resilience', () {
    test(
        'a failed completion write never throws, and the in-memory flag '
        'still prevents the hint from reappearing in this process', () async {
      final service =
          KeptDiscoveryHintService(storage: _ThrowingWriteAdapter());

      // Must not throw, even though the underlying write fails.
      await service.markCompleted();

      expect(await service.isCompleted(), isTrue);
      expect(await service.isEligible(), isFalse);
    });

    test(
        'a failed display-count write never throws, and the in-memory '
        'count still advances for the remainder of this process', () async {
      final service =
          KeptDiscoveryHintService(storage: _ThrowingWriteAdapter());

      await service.recordDisplayShown();
      await service.recordDisplayShown();

      expect(await service.displayCount(), 2);
      expect(await service.isEligible(), isFalse);
    });
  });
}
