import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/ritual_access_coordinator.dart';
import 'package:wisdom_app/controllers/ritual_access_view_state.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';

void main() {
  group('RitualAccessCoordinator', () {
    test('maps the current authoritative status', () async {
      final coordinator = RitualAccessCoordinator(
        loadStatus: () async => const DailyWisdomStatus(
          isReady: false,
          remaining: Duration(hours: 3, minutes: 58, seconds: 1),
          lockedText: 'Remain.',
          revealId: 'reveal-1',
        ),
      );

      final state = await coordinator.refresh();

      expect(state?.availability, RitualAccessAvailability.locked);
      expect(state?.countdownDuration?.hhmm, '03:59');
      expect(state?.wisdom?.text, 'Remain.');
      expect(state?.wisdom?.revealId, 'reveal-1');
    });

    test('a slower earlier refresh cannot overwrite a newer result', () async {
      final first = Completer<DailyWisdomStatus>();
      final second = Completer<DailyWisdomStatus>();
      var calls = 0;
      final coordinator = RitualAccessCoordinator(
        loadStatus: () => calls++ == 0 ? first.future : second.future,
      );

      final earlierRefresh = coordinator.refresh();
      final newerRefresh = coordinator.refresh();
      second.complete(
        DailyWisdomStatus(
          isReady: true,
          unlockAt: DateTime.utc(2026, 8, 24),
        ),
      );
      final newerState = await newerRefresh;
      first.complete(
        const DailyWisdomStatus(
          isReady: false,
          remaining: Duration(hours: 1),
          lockedText: 'Stale.',
        ),
      );

      expect(newerState?.availability, RitualAccessAvailability.ready);
      expect(newerState?.showReadyMessage, isTrue);
      expect(await earlierRefresh, isNull);
    });

    test('current load failure becomes an unresolved retryable state',
        () async {
      final coordinator = RitualAccessCoordinator(
        loadStatus: () => Future<DailyWisdomStatus>.error(StateError('load')),
      );

      final state = await coordinator.refresh();

      expect(state?.availability, RitualAccessAvailability.unresolved);
      expect(state?.isResolved, isFalse);
    });

    test('dispose invalidates an in-flight refresh and all later calls',
        () async {
      final pending = Completer<DailyWisdomStatus>();
      final coordinator = RitualAccessCoordinator(
        loadStatus: () => pending.future,
      );

      final inFlight = coordinator.refresh();
      coordinator.dispose();
      pending.complete(const DailyWisdomStatus(isReady: true));

      expect(await inFlight, isNull);
      expect(await coordinator.refresh(), isNull);
    });
  });
}
