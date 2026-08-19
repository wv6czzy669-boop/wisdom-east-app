// Build 26 Phase 4H-6: KeptStateRevisionNotifier -- the neutral,
// platform-neutral broadcast signal bridging IncomingKeptSyncCoordinator's
// durable incoming-apply path to any mounted Kept/Reflections UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/services/kept_state_revision_notifier.dart';

void main() {
  late KeptStateRevisionNotifier notifier;

  setUp(() {
    notifier = KeptStateRevisionNotifier();
  });

  test('starts at revision 0 and never calls a listener on construction', () {
    expect(notifier.revision, 0);
  });

  test('notify() calls every registered listener exactly once', () {
    var firstCallCount = 0;
    var secondCallCount = 0;
    notifier.addListener(() => firstCallCount++);
    notifier.addListener(() => secondCallCount++);

    notifier.notify();

    expect(firstCallCount, 1);
    expect(secondCallCount, 1);
  });

  test('notify() increments revision by exactly one per call', () {
    notifier.notify();
    expect(notifier.revision, 1);
    notifier.notify();
    expect(notifier.revision, 2);
  });

  test('removeListener stops future notify() calls from reaching it', () {
    var callCount = 0;
    void listener() => callCount++;

    notifier.addListener(listener);
    notifier.notify();
    expect(callCount, 1);

    notifier.removeListener(listener);
    notifier.notify();
    expect(callCount, 1, reason: 'removed listener must not be called again');
  });

  test(
      'a listener that throws never prevents remaining listeners from '
      'running, and never propagates out of notify()', () {
    var secondCallCount = 0;
    notifier.addListener(() => throw StateError('boom'));
    notifier.addListener(() => secondCallCount++);

    expect(() => notifier.notify(), returnsNormally);
    expect(secondCallCount, 1);
  });

  test(
      'a listener that adds another listener mid-callback does not corrupt '
      'the current notify() iteration (snapshot semantics)', () {
    var addedListenerCallCount = 0;
    void addedLater() => addedListenerCallCount++;

    notifier.addListener(() {
      notifier.addListener(addedLater);
    });

    notifier.notify();
    expect(addedListenerCallCount, 0,
        reason: 'a listener added during this notify() call must not be '
            'invoked by that same call');

    notifier.notify();
    expect(addedListenerCallCount, 1,
        reason: 'the listener added last time must run on the next call');
  });

  test(
      'a listener that removes another listener mid-callback does not '
      'corrupt the current notify() iteration', () {
    var removedListenerCallCount = 0;
    void toBeRemoved() => removedListenerCallCount++;
    notifier.addListener(toBeRemoved);
    notifier.addListener(() => notifier.removeListener(toBeRemoved));

    // Registration order: toBeRemoved is called before the listener that
    // removes it fires, so this first notify() still counts one call.
    notifier.notify();
    expect(removedListenerCallCount, 1);

    // It is genuinely gone from any future notify() call.
    notifier.notify();
    expect(removedListenerCallCount, 1);
  });

  test('clearListenersForTest() removes every listener', () {
    var callCount = 0;
    notifier.addListener(() => callCount++);
    notifier.addListener(() => callCount++);

    notifier.clearListenersForTest();
    notifier.notify();

    expect(callCount, 0);
  });
}
