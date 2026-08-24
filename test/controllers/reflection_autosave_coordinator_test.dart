import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/reflection_autosave_coordinator.dart';

void main() {
  testWidgets('unpersisted state is false until an edit and clears on flush',
      (tester) async {
    var text = 'Already durable';
    final coordinator = ReflectionAutosaveCoordinator(
      debounce: const Duration(seconds: 5),
      initialPersistedText: text,
      readText: () => text,
      persistText: (_) async => ReflectionPersistResult.saved,
    );

    expect(coordinator.hasUnpersistedChanges, isFalse);
    text = 'A new edit';
    coordinator.handleTextChanged();
    expect(coordinator.hasUnpersistedChanges, isTrue);

    expect(await coordinator.flush(), isTrue);
    expect(coordinator.hasUnpersistedChanges, isFalse);
    coordinator.dispose();
  });

  testWidgets('debounce coalesces typing into the latest text', (tester) async {
    var text = '';
    final writes = <String>[];
    final coordinator = ReflectionAutosaveCoordinator(
      debounce: const Duration(milliseconds: 200),
      readText: () => text,
      persistText: (value) async {
        writes.add(value);
        return ReflectionPersistResult.saved;
      },
    );

    text = 'one';
    coordinator.handleTextChanged();
    await tester.pump(const Duration(milliseconds: 100));
    text = 'latest';
    coordinator.handleTextChanged();
    await tester.pump(const Duration(milliseconds: 199));
    expect(writes, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(writes, ['latest']);
    coordinator.dispose();
  });

  testWidgets('flush bypasses debounce and waits for durable persistence',
      (tester) async {
    var text = 'leave safely';
    final writes = <String>[];
    final coordinator = ReflectionAutosaveCoordinator(
      debounce: const Duration(seconds: 5),
      readText: () => text,
      persistText: (value) async {
        writes.add(value);
        return ReflectionPersistResult.saved;
      },
    );
    coordinator.handleTextChanged();

    expect(await coordinator.flush(), isTrue);
    expect(writes, ['leave safely']);
    await tester.pump(const Duration(seconds: 5));
    expect(writes, hasLength(1));
    coordinator.dispose();
  });

  testWidgets('an edit during a write drains the newest revision next',
      (tester) async {
    var text = 'first';
    final firstWrite = Completer<ReflectionPersistResult>();
    final writes = <String>[];
    final coordinator = ReflectionAutosaveCoordinator(
      debounce: const Duration(milliseconds: 10),
      readText: () => text,
      persistText: (value) {
        writes.add(value);
        if (writes.length == 1) return firstWrite.future;
        return Future.value(ReflectionPersistResult.saved);
      },
    );

    coordinator.handleTextChanged();
    await tester.pump(const Duration(milliseconds: 10));
    text = 'second';
    coordinator.handleTextChanged();
    await tester.pump(const Duration(milliseconds: 10));
    firstWrite.complete(ReflectionPersistResult.saved);
    await tester.pump();
    await tester.pump();

    expect(writes, ['first', 'second']);
    coordinator.dispose();
  });

  testWidgets('flush retries transient failures up to the existing limit',
      (tester) async {
    var attempts = 0;
    final coordinator = ReflectionAutosaveCoordinator(
      debounce: Duration.zero,
      retryDelay: const Duration(milliseconds: 10),
      readText: () => 'retry me',
      persistText: (_) async {
        attempts += 1;
        if (attempts < 3) throw StateError('transient');
        return ReflectionPersistResult.saved;
      },
    );
    coordinator.handleTextChanged();

    final result = coordinator.flush();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
    expect(await result, isTrue);
    expect(attempts, 3);
    coordinator.dispose();
  });

  testWidgets('exhausted flush stays false and reports one failure',
      (tester) async {
    var attempts = 0;
    var failures = 0;
    final coordinator = ReflectionAutosaveCoordinator(
      debounce: Duration.zero,
      retryDelay: const Duration(milliseconds: 10),
      readText: () => 'cannot save',
      persistText: (_) async {
        attempts += 1;
        throw StateError('disk');
      },
      onPersistFailure: () => failures += 1,
    );
    coordinator.handleTextChanged();

    final result = coordinator.flush();
    await tester.pump(const Duration(milliseconds: 20));
    expect(await result, isFalse);
    expect(attempts, 3);
    expect(failures, 1);
    coordinator.dispose();
  });
}
