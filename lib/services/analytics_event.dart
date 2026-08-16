/// EAST. Phase 7 — the closed, privacy-safe analytics event allow-list.
///
/// Every emittable event name is a member of this enum — there is no other
/// way to construct or reference an analytics event anywhere in this app.
/// See [AnalyticsService](analytics_service.dart) for the one call site per
/// event, and for why every event is (deliberately, always) parameter-free:
/// no wisdom/reflection text, no Kept content, no revealId/localId/CloudKit
/// record identifier, no account fingerprint, and no daily-access timestamp
/// can ever be attached to an event, because none of those values are ever
/// passed to one.
enum AnalyticsEvent {
  ritualCompleted('ritual_completed'),
  keptSaved('kept_saved'),
  reflectionSaved('reflection_saved'),
  keeperPurchaseStarted('keeper_purchase_started'),
  keeperPurchaseCompleted('keeper_purchase_completed'),
  keeperRestoreCompleted('keeper_restore_completed');

  const AnalyticsEvent(this.eventName);

  /// The wire event name — stable, lowercase, snake_case, and exactly one
  /// of the six names EAST.'s privacy rules allow-list. Never derived from,
  /// or combined with, any other value.
  final String eventName;
}
