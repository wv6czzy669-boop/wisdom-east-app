/// Build 26 Phase 4H-6 (live incoming Kept UI refresh): a small,
/// platform-neutral broadcast signal that bridges
/// `IncomingKeptSyncCoordinator`'s durable incoming-apply path (see that
/// class's own `onIncomingStateChanged` constructor callback) to any mounted
/// Kept/Reflections UI.
///
/// Lives in `lib/services/` -- deliberately never in `lib/sync_integration/`
/// -- specifically so it can be safely imported by both a screen
/// (`HomeScreen`/`SavedReflectionsScreen`) and `app_services.dart`'s
/// composition-root wiring, without either `lib/sync_integration/` importing
/// UI code or a screen importing `lib/sync_integration/` (both forbidden by
/// `test/sync_integration/sync_integration_layering_test.dart`'s existing
/// structural guards). `IncomingKeptSyncCoordinator` itself never references
/// this class by name -- it only ever calls a plain, argument-free
/// `void Function()?` callback, exactly like
/// `KeptSyncIntegrationCoordinator.onMutationCommitted` already does;
/// `app_services.dart` alone wires that callback to this notifier's
/// [notify] method.
///
/// Deliberately NOT a `ChangeNotifier`: this class carries no widget-tree
/// lifecycle assumptions (no "used after dispose" assertion, no dependency
/// on `Listenable`'s own semantics), because it is constructed exactly once
/// as a long-lived global (`app_services.keptStateRevisionNotifier`) and is
/// itself never disposed -- only individual screens add/remove their own
/// listener in `initState`/`dispose`.
///
/// [notify] is called only after a successful, durable local Kept-envelope
/// replace whose content actually differs from what was there immediately
/// before -- never for a no-op, a token-only checkpoint, or a failed apply.
/// See `IncomingKeptSyncCoordinator._applyOnce`'s own gating logic.
final class KeptStateRevisionNotifier {
  final List<void Function()> _listeners = <void Function()>[];

  /// Monotonically increases by exactly one on every [notify] call.
  /// Exposed only as an inspectable fact for tests -- no production caller
  /// depends on its value, only on receiving the listener callback itself.
  int get revision => _revision;
  int _revision = 0;

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// Invokes every currently-registered listener synchronously, in
  /// registration order, over a snapshot copy of the listener list -- so a
  /// listener that adds or removes another listener mid-callback can never
  /// corrupt this iteration. Never throws: an individual listener's own
  /// exception is contained so it can never prevent the remaining listeners
  /// from running, mirroring the defensive-containment discipline
  /// `KeptSyncIntegrationCoordinator._notifyIfIntentWasWritten` already uses
  /// for its own outward callback.
  void notify() {
    _revision++;
    for (final listener in List<void Function()>.of(_listeners)) {
      try {
        listener();
      } catch (_) {
        // Intentionally contained -- see the doc comment above.
      }
    }
  }

  /// Test-only convenience: removes every listener. Never called by
  /// production code.
  void clearListenersForTest() {
    _listeners.clear();
  }
}
