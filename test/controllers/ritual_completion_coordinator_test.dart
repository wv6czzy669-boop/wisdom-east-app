import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/ritual_completion_coordinator.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';

void main() {
  group('RitualCompletionCoordinator', () {
    test('new reveal preserves every established effect and its order',
        () async {
      final events = <String>[];
      int? resolvedOrdinal;
      final unlockAt = DateTime.utc(2026, 8, 25, 12);
      final coordinator = RitualCompletionCoordinator(
        recordCompletedRitual: () async {
          events.add('rating');
          return 2;
        },
        trackRitualCompletion: () => events.add('analytics'),
        publishFreshWidgetReveal: ({
          required wisdomId,
          required text,
          required unlockAt,
        }) {
          events.add('widget:$wisdomId:$text:${unlockAt.toIso8601String()}');
        },
        refreshDailyAccessPresentation: () async => events.add('refresh'),
        scheduleWisdomUnlock: (unlockAt) async => events.add('notification'),
      );

      final result = coordinator.finish(
        DailyWisdomAccess(
          text: 'Be still.',
          isNew: true,
          unlockAt: unlockAt,
          wisdomId: 'wisdom-1',
          revealId: 'reveal-1',
        ),
        onRitualOrdinalResolved: (ordinal) => resolvedOrdinal = ordinal,
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.notificationOfferUnlockAt, unlockAt);
      expect(resolvedOrdinal, 2);
      expect(events, [
        'rating',
        'analytics',
        'widget:wisdom-1:Be still.:${unlockAt.toIso8601String()}',
        'refresh',
        'notification',
      ]);
    });

    test('existing reveal refreshes and schedules without new-reveal effects',
        () async {
      final events = <String>[];
      final unlockAt = DateTime.utc(2026, 8, 25, 12);
      final coordinator = RitualCompletionCoordinator(
        recordCompletedRitual: () async {
          events.add('rating');
          return 1;
        },
        trackRitualCompletion: () => events.add('analytics'),
        publishFreshWidgetReveal: ({
          required wisdomId,
          required text,
          required unlockAt,
        }) {
          events.add('widget');
        },
        refreshDailyAccessPresentation: () async => events.add('refresh'),
        scheduleWisdomUnlock: (_) async => events.add('notification'),
      );

      final result = coordinator.finish(
        DailyWisdomAccess(
          text: 'Already here.',
          isNew: false,
          unlockAt: unlockAt,
          wisdomId: 'wisdom-1',
        ),
        onRitualOrdinalResolved: (_) => events.add('ordinal'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.notificationOfferUnlockAt, isNull);
      expect(events, ['refresh', 'notification']);
    });

    test('missing wisdom identity skips only widget publication', () async {
      final events = <String>[];
      final coordinator = RitualCompletionCoordinator(
        recordCompletedRitual: () async => null,
        trackRitualCompletion: () => events.add('analytics'),
        publishFreshWidgetReveal: ({
          required wisdomId,
          required text,
          required unlockAt,
        }) {
          events.add('widget');
        },
        refreshDailyAccessPresentation: () async {},
        scheduleWisdomUnlock: (_) async => events.add('notification'),
      );

      coordinator.finish(
        DailyWisdomAccess(
          text: 'Legacy wisdom.',
          isNew: true,
          unlockAt: DateTime.utc(2026, 8, 25, 12),
        ),
        onRitualOrdinalResolved: (_) {},
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, ['analytics', 'notification']);
    });

    test('refresh failures remain isolated', () async {
      final coordinator = RitualCompletionCoordinator(
        recordCompletedRitual: () async => 1,
        trackRitualCompletion: () {},
        refreshDailyAccessPresentation: () =>
            Future<void>.error(StateError('refresh')),
        scheduleWisdomUnlock: (_) async {},
      );

      coordinator.finish(
        const DailyWisdomAccess(text: 'Persisted.', isNew: true),
        onRitualOrdinalResolved: (_) {},
      );
      await Future<void>.delayed(Duration.zero);
    });

    test('all asynchronous best-effort failures remain contained', () async {
      final unlockAt = DateTime.utc(2026, 8, 25, 12);
      final coordinator = RitualCompletionCoordinator(
        recordCompletedRitual: () =>
            Future<int?>.error(StateError('rating unavailable')),
        trackRitualCompletion: () {},
        refreshDailyAccessPresentation: () =>
            Future<void>.error(StateError('refresh unavailable')),
        scheduleWisdomUnlock: (_) =>
            Future<void>.error(StateError('notifications unavailable')),
      );

      expect(
        () => coordinator.finish(
          DailyWisdomAccess(
            text: 'Persisted.',
            isNew: true,
            unlockAt: unlockAt,
            wisdomId: 'wisdom-1',
          ),
          onRitualOrdinalResolved: (_) {},
        ),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
    });

    test('synchronous collaborator failures do not block later effects',
        () async {
      final events = <String>[];
      final unlockAt = DateTime.utc(2026, 8, 25, 12);
      final coordinator = RitualCompletionCoordinator(
        recordCompletedRitual: () => throw StateError('rating'),
        trackRitualCompletion: () => throw StateError('analytics'),
        publishFreshWidgetReveal: ({
          required wisdomId,
          required text,
          required unlockAt,
        }) {
          throw StateError('widget');
        },
        refreshDailyAccessPresentation: () {
          events.add('refresh-attempted');
          throw StateError('refresh');
        },
        scheduleWisdomUnlock: (_) {
          events.add('notification-attempted');
          throw StateError('notification');
        },
      );

      final result = coordinator.finish(
        DailyWisdomAccess(
          text: 'Persisted.',
          isNew: true,
          unlockAt: unlockAt,
          wisdomId: 'wisdom-1',
        ),
        onRitualOrdinalResolved: (_) {},
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.notificationOfferUnlockAt, unlockAt);
      expect(events, ['refresh-attempted', 'notification-attempted']);
    });
  });
}
