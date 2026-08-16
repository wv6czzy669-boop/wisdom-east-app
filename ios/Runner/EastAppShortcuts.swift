import AppIntents

/// EAST. Phase 12 -- makes `BeginEastIntent` discoverable in the Shortcuts
/// app and other system surfaces (Siri, Spotlight). One shortcut, two
/// restrained, natural phrases -- no content-specific or motivational
/// language, matching this phase's locked scope.
@available(iOS 16.0, *)
struct EastAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BeginEastIntent(),
            phrases: [
                "Begin \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: "Begin EAST.",
            systemImageName: "circle"
        )
    }
}
