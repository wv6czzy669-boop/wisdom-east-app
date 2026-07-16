import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';

void main() {
  test('same resource mutation slot clears only after operation completes',
      () async {
    final coordinator = PersistenceOperationCoordinator();
    final gate = Completer<void>();
    final events = <String>[];

    final first = coordinator.runMutation<int>(
      resourceKey: 'daily',
      operationKey: 'write',
      operation: () async {
        events.add('first-start');
        await gate.future;
        events.add('first-end');
        return 1;
      },
    );
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.isMutating('daily'), isTrue);
    expect(events, ['first-start']);

    gate.complete();
    expect(await first, 1);
    expect(coordinator.isMutating('daily'), isFalse);

    final second = await coordinator.runMutation<int>(
      resourceKey: 'daily',
      operationKey: 'write',
      operation: () async {
        events.add('second-start');
        return 2;
      },
    );

    expect(second, 2);
    expect(events, ['first-start', 'first-end', 'second-start']);
  });

  test('different resource keys may proceed independently', () async {
    final coordinator = PersistenceOperationCoordinator();
    final dailyGate = Completer<int>();
    var favoriteStarted = false;

    final daily = coordinator.runMutation<int>(
      resourceKey: 'daily',
      operationKey: 'write',
      operation: () => dailyGate.future,
    );
    final favorite = coordinator.runMutation<int>(
      resourceKey: 'favorites',
      operationKey: 'write',
      operation: () async {
        favoriteStarted = true;
        return 7;
      },
    );

    expect(await favorite, 7);
    expect(favoriteStarted, isTrue);
    expect(coordinator.isMutating('daily'), isTrue);

    dailyGate.complete(3);
    expect(await daily, 3);
  });

  test('caller timeout does not release unresolved mutation', () async {
    final coordinator = PersistenceOperationCoordinator();
    final gate = Completer<int>();

    final mutation = coordinator.runMutation<int>(
      resourceKey: 'daily',
      operationKey: 'prepare',
      operation: () => gate.future,
    );

    await expectLater(
      coordinator.observeWithUiTimeout(
        operation: mutation,
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(coordinator.isMutating('daily'), isTrue);
    expect(
      coordinator.runMutation<int>(
        resourceKey: 'daily',
        operationKey: 'prepare',
        operation: () async => 9,
      ),
      same(mutation),
    );

    gate.complete(4);
    expect(await mutation, 4);
    expect(coordinator.isMutating('daily'), isFalse);
  });

  test('conflicting unresolved mutation does not start', () async {
    final coordinator = PersistenceOperationCoordinator();
    final gate = Completer<void>();
    var conflictingStarted = false;

    coordinator.runMutation<void>(
      resourceKey: 'daily',
      operationKey: 'prepare',
      operation: () => gate.future,
    );

    await expectLater(
      coordinator.runMutation<void>(
        resourceKey: 'daily',
        operationKey: 'finalize',
        operation: () async {
          conflictingStarted = true;
        },
      ),
      throwsStateError,
    );

    expect(conflictingStarted, isFalse);
    gate.complete();
  });

  test('late completion resolves all observers safely', () async {
    final coordinator = PersistenceOperationCoordinator();
    final gate = Completer<String>();

    final first = coordinator.runMutation<String>(
      resourceKey: 'daily',
      operationKey: 'prepare',
      operation: () => gate.future,
    );
    final second = coordinator.runMutation<String>(
      resourceKey: 'daily',
      operationKey: 'prepare',
      operation: () async => 'different',
    );

    expect(second, same(first));

    gate.complete('wisdom');
    expect(await Future.wait([first, second]), ['wisdom', 'wisdom']);
  });

  test('thrown operation clears resource slot', () async {
    final coordinator = PersistenceOperationCoordinator();

    await expectLater(
      coordinator.runMutation<void>(
        resourceKey: 'daily',
        operationKey: 'write',
        operation: () async {
          throw StateError('boom');
        },
      ),
      throwsStateError,
    );

    expect(coordinator.isMutating('daily'), isFalse);
    expect(
      await coordinator.runMutation<int>(
        resourceKey: 'daily',
        operationKey: 'write',
        operation: () async => 2,
      ),
      2,
    );
  });

  test('coordinator instances do not share hidden static state', () async {
    final first = PersistenceOperationCoordinator();
    final second = PersistenceOperationCoordinator();
    final gate = Completer<void>();

    first.runMutation<void>(
      resourceKey: 'daily',
      operationKey: 'write',
      operation: () => gate.future,
    );

    expect(first.isMutating('daily'), isTrue);
    expect(second.isMutating('daily'), isFalse);
    expect(
      await second.runMutation<int>(
        resourceKey: 'daily',
        operationKey: 'write',
        operation: () async => 5,
      ),
      5,
    );

    gate.complete();
  });

  test('operation error propagates to all observers', () async {
    final coordinator = PersistenceOperationCoordinator();
    final gate = Completer<int>();

    final first = coordinator.runMutation<int>(
      resourceKey: 'daily',
      operationKey: 'prepare',
      operation: () => gate.future,
    );
    final second = coordinator.runMutation<int>(
      resourceKey: 'daily',
      operationKey: 'prepare',
      operation: () async => 2,
    );

    gate.completeError(StateError('failed'));

    await expectLater(first, throwsStateError);
    await expectLater(second, throwsStateError);
  });

  test('read waits for active mutation on the same resource', () async {
    final coordinator = PersistenceOperationCoordinator();
    final mutationGate = Completer<void>();
    final mutationStarted = Completer<void>();
    var readStarted = false;

    final mutation = coordinator.runMutation<int>(
      resourceKey: 'daily',
      operationKey: 'write',
      operation: () async {
        mutationStarted.complete();
        await mutationGate.future;
        return 1;
      },
    );
    await mutationStarted.future;

    final read = coordinator.runRead<int>(
      resourceKey: 'daily',
      operation: () async {
        readStarted = true;
        return 2;
      },
    );

    expect(readStarted, isFalse);

    mutationGate.complete();
    expect(await mutation, 1);
    expect(await read, 2);
    expect(readStarted, isTrue);
  });

  test('mutation waits for active read on the same resource', () async {
    final coordinator = PersistenceOperationCoordinator();
    final readGate = Completer<void>();
    final readStarted = Completer<void>();
    var mutationStarted = false;

    final read = coordinator.runRead<int>(
      resourceKey: 'daily',
      operation: () async {
        readStarted.complete();
        await readGate.future;
        return 1;
      },
    );
    await readStarted.future;

    final mutation = coordinator.runMutation<int>(
      resourceKey: 'daily',
      operationKey: 'write',
      operation: () async {
        mutationStarted = true;
        return 2;
      },
    );

    expect(mutationStarted, isFalse);

    readGate.complete();
    expect(await read, 1);
    expect(await mutation, 2);
    expect(mutationStarted, isTrue);
  });

  test('exception during read releases resource', () async {
    final coordinator = PersistenceOperationCoordinator();

    await expectLater(
      coordinator.runRead<void>(
        resourceKey: 'daily',
        operation: () async {
          throw StateError('read failed');
        },
      ),
      throwsStateError,
    );

    expect(
      await coordinator.runMutation<int>(
        resourceKey: 'daily',
        operationKey: 'write',
        operation: () async => 3,
      ),
      3,
    );
  });

  test('stale completion cannot clear newer resource tail', () async {
    final coordinator = PersistenceOperationCoordinator();
    final firstGate = Completer<void>();
    final firstStarted = Completer<void>();
    final readGate = Completer<void>();
    final readStarted = Completer<void>();
    var secondMutationStarted = false;

    final first = coordinator.runMutation<int>(
      resourceKey: 'daily',
      operationKey: 'first',
      operation: () async {
        firstStarted.complete();
        await firstGate.future;
        return 1;
      },
    );
    await firstStarted.future;

    final read = coordinator.runRead<int>(
      resourceKey: 'daily',
      operation: () async {
        readStarted.complete();
        await readGate.future;
        return 2;
      },
    );

    firstGate.complete();
    expect(await first, 1);
    await readStarted.future;

    final second = coordinator.runMutation<int>(
      resourceKey: 'daily',
      operationKey: 'second',
      operation: () async {
        secondMutationStarted = true;
        return 3;
      },
    );

    expect(secondMutationStarted, isFalse);

    readGate.complete();
    expect(await read, 2);
    expect(await second, 3);
    expect(secondMutationStarted, isTrue);
  });
}
