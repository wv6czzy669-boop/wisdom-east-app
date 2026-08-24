import 'dart:async';

enum ReflectionPersistResult { saved, limitReached }

typedef ReadReflectionText = String Function();
typedef PersistReflectionText = Future<ReflectionPersistResult> Function(
  String text,
);
typedef ReflectionAutosaveCallback = void Function();
typedef ReflectionAutosaveDiagnostic = void Function(String stage);

/// Owns Reflection's debounce, newest-edit drain, and flush-before-leave rules.
class ReflectionAutosaveCoordinator {
  ReflectionAutosaveCoordinator({
    required this.debounce,
    required this.readText,
    required this.persistText,
    String? initialPersistedText,
    this.onLimitReached,
    this.onPersistFailure,
    this.onDiagnostic,
    this.maximumFlushAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 120),
  }) : _lastPersistedText = initialPersistedText?.trim();

  final Duration debounce;
  final ReadReflectionText readText;
  final PersistReflectionText persistText;
  final ReflectionAutosaveCallback? onLimitReached;
  final ReflectionAutosaveCallback? onPersistFailure;
  final ReflectionAutosaveDiagnostic? onDiagnostic;
  final int maximumFlushAttempts;
  final Duration retryDelay;

  Timer? _debounceTimer;
  Future<void>? _inFlightPersist;
  bool _persistPending = false;
  bool _disposed = false;
  String? _lastPersistedText;
  int _editRevision = 0;
  int _persistedRevision = 0;

  /// Whether the editor currently contains a revision that has not yet
  /// completed its durable local write. Reflection uses this only to decide
  /// whether iOS may use its native interactive pop gesture directly or
  /// must take the guarded flush-before-pop path.
  bool get hasUnpersistedChanges => _editRevision > _persistedRevision;

  void handleTextChanged() {
    if (_disposed) return;
    _editRevision += 1;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(_persist());
    });
  }

  /// Cancels the debounce and durably catches up to the current edit.
  Future<bool> flush() {
    if (_disposed) return Future<bool>.value(false);
    onDiagnostic?.call('reflection-screen: flush-begin');
    cancelPending();
    return _persist(retryOnFailure: true);
  }

  void cancelPending() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelPending();
  }

  Future<bool> _persist({bool retryOnFailure = false}) {
    final requestedRevision = _editRevision;
    final existing = _inFlightPersist;
    if (existing != null) {
      _persistPending = true;
      return existing.then((_) => _persistedRevision >= requestedRevision);
    }

    late final Future<void> run;
    run = _runPersistLoop(retryOnFailure: retryOnFailure).whenComplete(() {
      if (identical(_inFlightPersist, run)) {
        _inFlightPersist = null;
      }
    });
    _inFlightPersist = run;
    return run.then((_) => _persistedRevision >= requestedRevision);
  }

  Future<void> _runPersistLoop({required bool retryOnFailure}) async {
    while (true) {
      _persistPending = false;
      final revisionBeingAttempted = _editRevision;
      final text = readText();
      final trimmed = text.trim();
      if (trimmed.isNotEmpty && trimmed != _lastPersistedText) {
        final succeeded = await _attemptPersist(
          text: text,
          trimmed: trimmed,
          retryOnFailure: retryOnFailure,
        );
        if (succeeded) _markPersisted(revisionBeingAttempted);
      } else {
        _markPersisted(revisionBeingAttempted);
      }
      if (!_persistPending) return;
    }
  }

  void _markPersisted(int revision) {
    if (revision > _persistedRevision) _persistedRevision = revision;
  }

  Future<bool> _attemptPersist({
    required String text,
    required String trimmed,
    required bool retryOnFailure,
  }) async {
    final attempts = retryOnFailure ? maximumFlushAttempts : 1;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      onDiagnostic?.call(
        'reflection-screen: local-write-begin attempt=$attempt/$attempts',
      );
      try {
        final result = await persistText(text);
        if (result == ReflectionPersistResult.limitReached) {
          onDiagnostic?.call(
            'reflection-screen: local-write-limit-reached attempt=$attempt',
          );
          onLimitReached?.call();
        } else {
          onDiagnostic?.call(
            'reflection-screen: local-write-success attempt=$attempt',
          );
          _lastPersistedText = trimmed;
        }
        return true;
      } catch (error) {
        onDiagnostic?.call(
          'reflection-screen: local-write-failed attempt=$attempt/$attempts '
          'errorType=${error.runtimeType}',
        );
        if (attempt == attempts) {
          onDiagnostic?.call('reflection-screen: local-write-exhausted');
          onPersistFailure?.call();
          return false;
        }
        await Future<void>.delayed(retryDelay);
      }
    }
    return false;
  }
}
