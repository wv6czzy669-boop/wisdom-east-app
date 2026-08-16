import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/services/rating_request_service.dart';

void main() {
  late _FakeRatingRequestPlatform platform;
  late RatingRequestService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    platform = _FakeRatingRequestPlatform();
    service = RatingRequestService(platform: platform);
  });

  test('rituals 1-3 never request rating', () async {
    await service.recordCompletedRitual();
    await service.maybeRequestReview();
    await service.recordCompletedRitual();
    await service.maybeRequestReview();
    await service.recordCompletedRitual();
    await service.maybeRequestReview();

    expect(platform.requestCount, 0);
  });

  test('the 4th successfully completed ritual becomes eligible', () async {
    await service.recordCompletedRitual();
    await service.recordCompletedRitual();
    await service.recordCompletedRitual();
    await service.recordCompletedRitual();

    await service.maybeRequestReview();

    expect(platform.requestCount, 1);
  });

  test('an unrecorded (interrupted/incomplete) ritual never counts', () async {
    // Three genuinely completed rituals, plus repeated calls to the
    // eligibility check itself -- none of which is a completion -- must
    // never advance the count.
    await service.recordCompletedRitual();
    await service.recordCompletedRitual();
    await service.recordCompletedRitual();
    for (var i = 0; i < 5; i++) {
      await service.maybeRequestReview();
    }

    expect(platform.requestCount, 0);

    await service.recordCompletedRitual();
    await service.maybeRequestReview();

    expect(platform.requestCount, 1);
  });

  test('repeated eligibility checks after the request never repeat it',
      () async {
    for (var i = 0; i < 4; i++) {
      await service.recordCompletedRitual();
    }
    await service.maybeRequestReview();
    expect(platform.requestCount, 1);

    // Further completed rituals and further checks -- simulating
    // rebuild/resume across many later sessions -- must never re-request.
    for (var i = 0; i < 10; i++) {
      await service.recordCompletedRitual();
      await service.maybeRequestReview();
    }

    expect(platform.requestCount, 1);
  });

  test('a fresh service instance backed by the same persisted state never '
      're-requests (survives process restart)', () async {
    for (var i = 0; i < 4; i++) {
      await service.recordCompletedRitual();
    }
    await service.maybeRequestReview();
    expect(platform.requestCount, 1);

    final restarted = RatingRequestService(platform: platform);
    await restarted.maybeRequestReview();

    expect(platform.requestCount, 1);
  });

  test('a native request failure is contained and never rethrown, and never '
      'causes a retry', () async {
    platform.shouldThrow = true;
    for (var i = 0; i < 4; i++) {
      await service.recordCompletedRitual();
    }

    await expectLater(service.maybeRequestReview(), completes);
    expect(platform.requestCount, 1);

    // A second call after the failed attempt must not retry.
    await service.maybeRequestReview();
    expect(platform.requestCount, 1);
  });

  test('a local persistence failure while recording never throws', () async {
    final throwingAdapter = _ThrowingIntPreferencesAdapter();
    final resilientService = RatingRequestService(
      platform: platform,
      preferencesAdapter: throwingAdapter,
    );

    await expectLater(resilientService.recordCompletedRitual(), completes);
    await expectLater(resilientService.maybeRequestReview(), completes);
    expect(platform.requestCount, 0);
  });
}

class _FakeRatingRequestPlatform implements RatingRequestPlatform {
  int requestCount = 0;
  bool shouldThrow = false;

  @override
  Future<void> requestReview() async {
    requestCount += 1;
    if (shouldThrow) {
      throw StateError('native rating prompt unavailable');
    }
  }
}

class _ThrowingIntPreferencesAdapter extends StoragePreferencesAdapter {
  @override
  Future<int?> getInt(String key) async {
    throw StateError('read failure');
  }

  @override
  Future<void> setInt(String key, int value) async {
    throw StateError('write failure');
  }
}
