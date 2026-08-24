import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/ritual_commit_coordinator.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';

void main() {
  const access = DailyWisdomAccess(
    text: 'Persisted wisdom.',
    isNew: true,
    revealId: 'reveal-1',
    wisdomId: 'wisdom-1',
  );

  test('successful commit returns the authoritative access', () async {
    const coordinator = RitualCommitCoordinator(
      timeout: Duration(seconds: 1),
    );

    final attempt = await coordinator.run(Future.value(access));

    expect(attempt, isA<RitualCommitCompleted>());
    final resolution = (attempt as RitualCommitCompleted).resolution;
    expect(resolution, isA<RitualCommitSucceeded>());
    expect((resolution as RitualCommitSucceeded).access, same(access));
  });

  test('operation failure is contained as a typed resolution', () async {
    const coordinator = RitualCommitCoordinator(
      timeout: Duration(seconds: 1),
    );

    final attempt = await coordinator.run(
      Future<DailyWisdomAccess>.error(StateError('synthetic failure')),
    );

    expect(attempt, isA<RitualCommitCompleted>());
    expect(
      (attempt as RitualCommitCompleted).resolution,
      isA<RitualCommitFailed>(),
    );
  });

  test('timeout preserves a later successful authoritative result', () async {
    final completer = Completer<DailyWisdomAccess>();
    const coordinator = RitualCommitCoordinator(timeout: Duration.zero);

    final attempt = await coordinator.run(completer.future);
    expect(attempt, isA<RitualCommitTimedOut>());

    completer.complete(access);
    final resolution =
        await (attempt as RitualCommitTimedOut).eventualResolution;
    expect(resolution, isA<RitualCommitSucceeded>());
    expect((resolution as RitualCommitSucceeded).access, same(access));
  });

  test('timeout contains a later failure without an uncaught future error',
      () async {
    final completer = Completer<DailyWisdomAccess>();
    const coordinator = RitualCommitCoordinator(timeout: Duration.zero);

    final attempt = await coordinator.run(completer.future);
    completer.completeError(StateError('late synthetic failure'));

    final resolution =
        await (attempt as RitualCommitTimedOut).eventualResolution;
    expect(resolution, isA<RitualCommitFailed>());
  });
}
