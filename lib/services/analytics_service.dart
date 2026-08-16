import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'analytics_event.dart';

/// A transport for already-validated, parameter-free [AnalyticsEvent]s. The
/// only implementation shipped today ([DebugLogAnalyticsTransport]) never
/// leaves the device; a real privacy-reviewed backend can be wired in later
/// behind this same interface without any [AnalyticsService] call site
/// changing.
abstract interface class AnalyticsTransport {
  void track(AnalyticsEvent event);
}

/// Local-only placeholder transport: writes the event name to the debug
/// console via `dart:developer` and makes no network call of any kind. A
/// true no-op outside debug builds.
class DebugLogAnalyticsTransport implements AnalyticsTransport {
  const DebugLogAnalyticsTransport();

  @override
  void track(AnalyticsEvent event) {
    if (kDebugMode) {
      developer.log(event.eventName, name: 'analytics');
    }
  }
}

/// EAST. Phase 7 — the one production analytics surface.
///
/// Every public method corresponds 1:1 to exactly one [AnalyticsEvent] and
/// takes no parameters, so no call site can attach wisdom text, Reflection
/// text, Kept content, revealId/localId/CloudKit record identifiers,
/// account fingerprints, or daily-access timestamps to an event — there is
/// no parameter for any of those values to travel through. Each method is
/// called from its event's one authoritative "this already succeeded"
/// point (`HomeScreen.finishCommittedDailyWisdom`'s durable-new-reveal
/// branch; `SavedReflectionsService.toggle`/`saveReflection`'s
/// not-limit-blocked branches; `PurchaseService`'s purchase-attempt-started,
/// persisted-purchase, and persisted-restore points) — never duplicated
/// elsewhere, and never fired speculatively before that point.
///
/// Every method is fire-and-forget and failure-contained: a transport
/// failure is always swallowed here and never rethrown, so analytics can
/// never affect the ritual, Kept/Reflection saves, sync, or purchases.
class AnalyticsService {
  AnalyticsService({AnalyticsTransport? transport})
      : _transport = transport ?? const DebugLogAnalyticsTransport();

  final AnalyticsTransport _transport;

  void ritualCompleted() => _track(AnalyticsEvent.ritualCompleted);

  void keptSaved() => _track(AnalyticsEvent.keptSaved);

  void reflectionSaved() => _track(AnalyticsEvent.reflectionSaved);

  void keeperPurchaseStarted() => _track(AnalyticsEvent.keeperPurchaseStarted);

  void keeperPurchaseCompleted() =>
      _track(AnalyticsEvent.keeperPurchaseCompleted);

  void keeperRestoreCompleted() =>
      _track(AnalyticsEvent.keeperRestoreCompleted);

  void _track(AnalyticsEvent event) {
    try {
      _transport.track(event);
    } catch (_) {
      // Analytics must never affect product behavior.
    }
  }
}
