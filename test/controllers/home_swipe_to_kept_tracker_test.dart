import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/home_swipe_to_kept_tracker.dart';

void main() {
  group('HomeSwipeToKeptTracker', () {
    test('LTR opens Kept for an eligible left swipe at the distance boundary',
        () {
      final tracker = HomeSwipeToKeptTracker()
        ..start()
        ..update(dx: -60, dy: 10);

      expect(
        tracker.shouldOpenKept(
          velocityX: 0,
          isRtl: false,
          isEligible: true,
        ),
        isTrue,
      );
    });

    test('RTL mirrors the direction without changing thresholds', () {
      final tracker = HomeSwipeToKeptTracker()
        ..start()
        ..update(dx: 60, dy: 10);

      expect(
        tracker.shouldOpenKept(
          velocityX: 0,
          isRtl: true,
          isEligible: true,
        ),
        isTrue,
      );
    });

    test('velocity threshold can qualify a shorter horizontal swipe', () {
      final tracker = HomeSwipeToKeptTracker()
        ..start()
        ..update(dx: -20, dy: 5);

      expect(
        tracker.shouldOpenKept(
          velocityX: -320,
          isRtl: false,
          isEligible: true,
        ),
        isTrue,
      );
    });

    test('wrong direction, vertical gesture, and ineligible state stay silent',
        () {
      final wrongDirection = HomeSwipeToKeptTracker()
        ..start()
        ..update(dx: 80, dy: 0);
      final vertical = HomeSwipeToKeptTracker()
        ..start()
        ..update(dx: -80, dy: 51);
      final ineligible = HomeSwipeToKeptTracker()
        ..start()
        ..update(dx: -80, dy: 0);

      expect(
        wrongDirection.shouldOpenKept(
          velocityX: 400,
          isRtl: false,
          isEligible: true,
        ),
        isFalse,
      );
      expect(
        vertical.shouldOpenKept(
          velocityX: -400,
          isRtl: false,
          isEligible: true,
        ),
        isFalse,
      );
      expect(
        ineligible.shouldOpenKept(
          velocityX: -400,
          isRtl: false,
          isEligible: false,
        ),
        isFalse,
      );
    });

    test('one gesture can trigger navigation only once', () {
      final tracker = HomeSwipeToKeptTracker()
        ..start()
        ..update(dx: -80, dy: 0);

      expect(
        tracker.shouldOpenKept(
          velocityX: -400,
          isRtl: false,
          isEligible: true,
        ),
        isTrue,
      );
      expect(
        tracker.shouldOpenKept(
          velocityX: -400,
          isRtl: false,
          isEligible: true,
        ),
        isFalse,
      );
    });

    test('start resets accumulated geometry and the handled guard', () {
      final tracker = HomeSwipeToKeptTracker()
        ..start()
        ..update(dx: -80, dy: 0);
      expect(
        tracker.shouldOpenKept(
          velocityX: -400,
          isRtl: false,
          isEligible: true,
        ),
        isTrue,
      );

      tracker
        ..start()
        ..update(dx: -80, dy: 0);
      expect(
        tracker.shouldOpenKept(
          velocityX: -400,
          isRtl: false,
          isEligible: true,
        ),
        isTrue,
      );
    });
  });
}
