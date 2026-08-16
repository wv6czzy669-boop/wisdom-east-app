import AppIntents

/// EAST. Phase 12 -- the single App Intent this app exposes. A doorway into
/// the existing ritual, never a shortcut around it: `perform()` does nothing
/// beyond signaling success. `openAppWhenRun` alone is what brings EAST. to
/// the foreground, through the exact same launch path a normal tap on the
/// app icon takes -- Flutter's own `DailyWisdomAccessService`-driven
/// `HomeScreen` state remains the sole authority on what the user then sees.
///
/// This intent never selects, reveals, or mutates anything, and returns no
/// wisdom/private content to Shortcuts or Siri -- `.result()` carries no
/// value at all.
@available(iOS 16.0, *)
struct BeginEastIntent: AppIntent {
    static var title: LocalizedStringResource = "Begin EAST."
    static var description = IntentDescription("Opens EAST.")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
