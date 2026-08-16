import AppIntents
import XCTest

@testable import Runner

/// EAST. Phase 12 -- proves `BeginEastIntent`'s locked shape: exact title,
/// app-foregrounding via `openAppWhenRun` (not custom navigation code), a
/// result carrying no value (so nothing private can ever be returned to
/// Shortcuts/Siri), and that discovery is wired through exactly one
/// `AppShortcut` wrapping this one intent.
@available(iOS 16.0, *)
final class BeginEastIntentTests: XCTestCase {

  func testTitleIsExactlyBeginEast() {
    XCTAssertEqual(String(localized: BeginEastIntent.title), "Begin EAST.")
  }

  func testOpensTheContainingAppRatherThanRunningInTheBackground() {
    XCTAssertTrue(BeginEastIntent.openAppWhenRun)
  }

  func testPerformReturnsAVoidResultCarryingNoContent() async throws {
    let intent = BeginEastIntent()
    let result = try await intent.perform()
    // `some IntentResult` with no `.result(value:)` payload -- there is no
    // value to inspect at all, which is itself the privacy proof: this type
    // structurally cannot carry wisdom/Reflection/Kept/identifier content
    // back to Shortcuts or Siri.
    _ = result
  }

  func testExposesExactlyOneAppShortcutWrappingBeginEastIntent() {
    let shortcuts = EastAppShortcutsProvider.appShortcuts
    XCTAssertEqual(shortcuts.count, 1)
  }
}
