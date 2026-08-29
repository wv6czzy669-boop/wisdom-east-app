import AppIntents
import WidgetKit

@available(iOS 17.0, *)
struct EastKeeperRitualAdvanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Begin EAST."
    static var description = IntentDescription("A quiet space for the day's wisdom.")

    func perform() async throws -> some IntentResult {
        let isKeeper = await EastKeeperEntitlementAuthority.currentEntitlement()
        let entitlementChanged = EastKeeperRitualStore.setKeeperEntitlement(isKeeper)

        guard isKeeper else {
            if entitlementChanged {
                WidgetCenter.shared.reloadTimelines(ofKind: EastWidgetKind.keeperRitualKind)
            }
            return .result()
        }

        let result = EastKeeperRitualStore.advance(now: Date())
        if let reveal = result.newlyRevealed {
            _ = EastWidgetSnapshotStore.publishRevealed(
                text: reveal.displayText,
                unlockAt: reveal.unlockAt,
                presentation: result.snapshot.presentation
            )
            WidgetCenter.shared.reloadTimelines(ofKind: EastWidgetKind.kind)
        }
        if entitlementChanged || result.changed {
            WidgetCenter.shared.reloadTimelines(ofKind: EastWidgetKind.keeperRitualKind)
        }
        return .result()
    }
}
