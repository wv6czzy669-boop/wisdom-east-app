import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/services/first_ritual_guidance_service.dart';
import 'package:wisdom_app/services/rating_request_service.dart';

class _ThrowingAdapter extends StoragePreferencesAdapter {
  @override
  Future<bool?> getBool(String key) async {
    throw const PersistenceException('simulated read failure');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a genuinely new install receives first-ritual guidance', () async {
    expect(await FirstRitualGuidanceService().shouldShow(), isTrue);
  });

  test('completion persists and permanently suppresses guidance', () async {
    final service = FirstRitualGuidanceService();
    await service.markCompleted();

    expect(await service.shouldShow(), isFalse);
    expect(await FirstRitualGuidanceService().shouldShow(), isFalse);
  });

  test('an existing user is migrated without seeing onboarding again',
      () async {
    SharedPreferences.setMockInitialValues({
      RatingRequestService.completedRitualCountKey: 2,
    });

    expect(await FirstRitualGuidanceService().shouldShow(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(FirstRitualGuidanceService.completedKey),
      isTrue,
    );
  });

  test('optional guidance fails closed when preferences cannot be read',
      () async {
    final service = FirstRitualGuidanceService(storage: _ThrowingAdapter());

    expect(await service.shouldShow(), isFalse);
  });
}
