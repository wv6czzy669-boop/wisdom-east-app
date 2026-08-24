import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/ritual_access_view_state.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/utils/countdown_formatter.dart';

void main() {
  group('RitualAccessViewState', () {
    test('unresolved state cannot expose ready or locked presentation', () {
      const state = RitualAccessViewState.unresolved();

      expect(state.availability, RitualAccessAvailability.unresolved);
      expect(state.isResolved, isFalse);
      expect(state.isLocked, isFalse);
      expect(state.showReadyMessage, isFalse);
      expect(state.countdownDuration, isNull);
      expect(state.wisdom, isNull);
    });

    test('ready state preserves whether a completed occurrence exists', () {
      const firstUse = RitualAccessViewState.ready(showReadyMessage: false);
      const completed = RitualAccessViewState.ready(showReadyMessage: true);

      expect(firstUse.isResolved, isTrue);
      expect(firstUse.isLocked, isFalse);
      expect(firstUse.showReadyMessage, isFalse);
      expect(completed.showReadyMessage, isTrue);
      expect(completed.countdownDuration, isNull);
      expect(completed.wisdom, isNull);
    });

    test('locked state keeps countdown and optional wisdom identity together',
        () {
      final revealedAt = DateTime.utc(2026, 8, 24, 12);
      final wisdom = LockedWisdomReference(
        text: 'Stay close to what is quiet.',
        revealId: 'reveal-1',
        revealedAt: revealedAt,
        wisdomId: 'wisdom-1',
      );
      final state = RitualAccessViewState.locked(
        countdownDuration: const CountdownDuration(hours: 19, minutes: 4),
        wisdom: wisdom,
      );

      expect(state.isResolved, isTrue);
      expect(state.isLocked, isTrue);
      expect(state.showReadyMessage, isFalse);
      expect(state.countdownDuration?.hhmm, '19:04');
      expect(state.wisdom, same(wisdom));
      expect(state.wisdom?.revealId, 'reveal-1');
      expect(state.wisdom?.revealedAt, revealedAt);
      expect(state.wisdom?.wisdomId, 'wisdom-1');
    });

    test('locked state supports corrupt-record recovery without a wisdom', () {
      const state = RitualAccessViewState.locked(
        countdownDuration: CountdownDuration(hours: 0, minutes: 1),
      );

      expect(state.isResolved, isTrue);
      expect(state.isLocked, isTrue);
      expect(state.wisdom, isNull);
      expect(state.countdownDuration?.hhmm, '00:01');
    });

    test('maps a first-use ready status without the post-reveal message', () {
      final state = RitualAccessViewState.fromStatus(
        const DailyWisdomStatus(isReady: true),
      );

      expect(state.isResolved, isTrue);
      expect(state.isLocked, isFalse);
      expect(state.showReadyMessage, isFalse);
    });

    test('maps completed ready status with the post-reveal message', () {
      final state = RitualAccessViewState.fromStatus(
        DailyWisdomStatus(
          isReady: true,
          unlockAt: DateTime.utc(2026, 8, 24, 12),
        ),
      );

      expect(state.showReadyMessage, isTrue);
      expect(state.countdownDuration, isNull);
    });

    test('maps locked status with countdown and authoritative identity', () {
      final revealedAt = DateTime.utc(2026, 8, 24, 12);
      final state = RitualAccessViewState.fromStatus(
        DailyWisdomStatus(
          isReady: false,
          remaining: const Duration(hours: 19, minutes: 3, seconds: 1),
          lockedText: '  Keep the original spacing.  ',
          revealId: 'reveal-2',
          revealedAt: revealedAt,
          wisdomId: 'wisdom-2',
        ),
      );

      expect(state.isLocked, isTrue);
      expect(state.countdownDuration?.hhmm, '19:04');
      expect(state.wisdom?.text, '  Keep the original spacing.  ');
      expect(state.wisdom?.revealId, 'reveal-2');
      expect(state.wisdom?.revealedAt, revealedAt);
      expect(state.wisdom?.wisdomId, 'wisdom-2');
    });

    test('corrupt sentinel remains a countdown and never becomes a wisdom', () {
      final state = RitualAccessViewState.fromStatus(
        const DailyWisdomStatus(
          isReady: false,
          remaining: Duration(minutes: 1),
          lockedText: DailyWisdomAccessService.corruptRecordRecoveryText,
          revealId: 'must-not-travel',
          wisdomId: 'must-not-travel',
        ),
      );

      expect(state.isLocked, isTrue);
      expect(state.countdownDuration?.hhmm, '00:01');
      expect(state.wisdom, isNull);
    });
  });
}
