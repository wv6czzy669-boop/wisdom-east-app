class PersistenceOperationCoordinator {
  final Map<String, Future<void>> _resourceTails = {};
  final Map<String, _PersistenceMutation> _mutations = {};

  Future<T> runRead<T>({
    required String resourceKey,
    required Future<T> Function() operation,
  }) {
    final predecessor = _resourceTails[resourceKey];

    late final Future<T> read;
    read = () async {
      if (predecessor != null) {
        try {
          await predecessor;
        } catch (_) {
          // The operation that owns predecessor has already delivered its
          // error to its caller. A read waits for exclusivity, not success.
        }
      }

      return operation();
    }();

    _trackResourceTail(resourceKey, read);
    return read;
  }

  Future<T> runMutation<T>({
    required String resourceKey,
    required Future<T> Function() operation,
    Object? operationKey,
  }) {
    final existingMutation = _mutations[resourceKey];
    if (existingMutation != null) {
      if (operationKey != null &&
          existingMutation.operationKey != null &&
          existingMutation.operationKey != operationKey) {
        return Future<T>.error(
          StateError('Conflicting persistence mutation is already active.'),
        );
      }

      return existingMutation.future as Future<T>;
    }

    final predecessor = _resourceTails[resourceKey];

    final operationFuture = () async {
      if (predecessor != null) {
        try {
          await predecessor;
        } catch (_) {
          // The previous resource operation has already reported its own
          // failure. This mutation waits for the slot to become exclusive.
        }
      }

      return operation();
    }();

    late final Future<T> mutation;
    mutation = operationFuture.whenComplete(() {
      final current = _mutations[resourceKey];
      if (current != null && identical(current.future, mutation)) {
        _mutations.remove(resourceKey);
      }
    });
    _mutations[resourceKey] = _PersistenceMutation(
      future: mutation,
      operationKey: operationKey,
    );
    _trackResourceTail(resourceKey, mutation);

    return mutation;
  }

  Future<T> runExclusive<T>({
    required String resourceKey,
    required Future<T> Function() operation,
  }) {
    final predecessor = _resourceTails[resourceKey];

    final operationFuture = () async {
      if (predecessor != null) {
        try {
          await predecessor;
        } catch (_) {
          // The previous resource operation has already reported its own
          // failure. This operation waits for serialization only.
        }
      }

      return operation();
    }();

    _trackResourceTail(resourceKey, operationFuture);
    return operationFuture;
  }

  void _trackResourceTail(String resourceKey, Future<Object?> operation) {
    final tail = () async {
      try {
        await operation;
      } catch (_) {
        // Tails only serialize later operations. Errors belong to the original
        // operation future.
      }
    }();

    _resourceTails[resourceKey] = tail;
    tail.whenComplete(() {
      final current = _resourceTails[resourceKey];
      if (identical(current, tail)) {
        _resourceTails.remove(resourceKey);
      }
    });
  }

  Future<T> observeWithUiTimeout<T>({
    required Future<T> operation,
    required Duration timeout,
  }) {
    return operation.timeout(timeout);
  }

  Future<void> waitForIdle(String resourceKey) async {
    final tail = _resourceTails[resourceKey];
    if (tail == null) return;

    try {
      await tail;
    } catch (_) {
      // Waiting for idle observes completion only; callers perform their own
      // operation-specific error handling after the slot clears.
    }
  }

  bool isMutating(String resourceKey) {
    return _mutations.containsKey(resourceKey);
  }
}

class _PersistenceMutation {
  const _PersistenceMutation({
    required this.future,
    required this.operationKey,
  });

  final Future<Object?> future;
  final Object? operationKey;
}
