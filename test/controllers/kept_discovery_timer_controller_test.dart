import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/kept_discovery_timer_controller.dart';

void main() {
  testWidgets('central breath preserves first, active and pause timings',
      (tester) async {
    final changes = <bool>[];
    final controller = KeptDiscoveryTimerController(
      centralFirstDelay: const Duration(milliseconds: 10),
      centralActiveDuration: const Duration(milliseconds: 20),
      centralPause: const Duration(milliseconds: 5),
    );

    controller.startCentralBreathing(
      onActiveChanged: changes.add,
      shouldContinue: () => true,
    );
    await tester.pump(const Duration(milliseconds: 9));
    expect(changes, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(changes, [true]);
    await tester.pump(const Duration(milliseconds: 20));
    expect(changes, [true, false]);
    await tester.pump(const Duration(milliseconds: 5));
    expect(changes, [true, false, true]);

    controller.dispose();
  });

  testWidgets(
      'central breath stops after the active interval when no longer owed',
      (tester) async {
    final changes = <bool>[];
    var shouldContinue = true;
    final controller = KeptDiscoveryTimerController(
      centralFirstDelay: Duration.zero,
      centralActiveDuration: const Duration(milliseconds: 10),
      centralPause: const Duration(milliseconds: 5),
    );

    controller.startCentralBreathing(
      onActiveChanged: changes.add,
      shouldContinue: () => shouldContinue,
    );
    await tester.pump();
    shouldContinue = false;
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));

    expect(changes, [true, false]);
    controller.dispose();
  });

  testWidgets('saved text hide is single-flight and replaceable',
      (tester) async {
    var hides = 0;
    final controller = KeptDiscoveryTimerController(
      savedTextDuration: const Duration(milliseconds: 10),
    );

    controller.scheduleSavedTextHide(() => hides++);
    await tester.pump(const Duration(milliseconds: 5));
    controller.scheduleSavedTextHide(() => hides++);
    await tester.pump(const Duration(milliseconds: 5));
    expect(hides, 0);
    await tester.pump(const Duration(milliseconds: 5));
    expect(hides, 1);

    controller.dispose();
  });

  testWidgets('nav breath loops independently and cancelNav stops it',
      (tester) async {
    final changes = <bool>[];
    final controller = KeptDiscoveryTimerController(
      navFirstDelay: const Duration(milliseconds: 10),
      navActiveDuration: const Duration(milliseconds: 20),
      navPause: const Duration(milliseconds: 5),
    );

    controller.startNavBreathing(
      onActiveChanged: changes.add,
      shouldContinue: () => true,
    );
    expect(controller.hasNavTimer, isTrue);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 5));
    expect(changes, [true, false, true]);

    controller.cancelNav();
    await tester.pump(const Duration(milliseconds: 50));
    expect(changes, [true, false, true]);
    expect(controller.hasNavTimer, isFalse);
    controller.dispose();
  });

  testWidgets('default nav breath begins without a first-delay pause',
      (tester) async {
    final changes = <bool>[];
    final controller = KeptDiscoveryTimerController();

    controller.startNavBreathing(
      onActiveChanged: changes.add,
      shouldContinue: () => true,
    );
    expect(changes, isEmpty);
    await tester.pump(const Duration(microseconds: 1));
    expect(changes, [true]);

    controller.dispose();
  });

  testWidgets('cancelAll invalidates every pending callback', (tester) async {
    final changes = <bool>[];
    var hides = 0;
    final controller = KeptDiscoveryTimerController(
      centralFirstDelay: const Duration(milliseconds: 10),
      savedTextDuration: const Duration(milliseconds: 10),
      navFirstDelay: const Duration(milliseconds: 10),
    );

    controller.startCentralBreathing(
      onActiveChanged: changes.add,
      shouldContinue: () => true,
    );
    controller.startNavBreathing(
      onActiveChanged: changes.add,
      shouldContinue: () => true,
    );
    controller.scheduleSavedTextHide(() => hides++);
    controller.cancelAll();
    await tester.pump(const Duration(milliseconds: 20));

    expect(changes, isEmpty);
    expect(hides, 0);
    expect(controller.hasNavTimer, isFalse);
    controller.dispose();
  });
}
