import AppIntents
import WidgetKit

@available(iOS 17.0, *)
struct EastKeeperRitualAdvanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Begin EAST."
    static var description = IntentDescription("A quiet space for the day's wisdom.")

    func perform() async throws -> some IntentResult {
        let startedAt = Date()
        let isKeeper: Bool
        let entitlementPresentationChanged: Bool
        if EastKeeperRitualStore.hasFreshVerifiedKeeperEntitlement(now: startedAt) {
            // Pause, Feel, and Ask are one short interaction session. The
            // first verified beat grants a bounded lease so later taps do not
            // wait on the same StoreKit query again.
            isKeeper = true
            entitlementPresentationChanged = false
        } else {
            let beforeVerification = EastKeeperRitualStore.resolvedSnapshot(now: startedAt)
            isKeeper = await EastKeeperEntitlementAuthority.currentEntitlement()
            let verifiedAt = Date()
            _ = EastKeeperRitualStore.recordVerifiedKeeperEntitlement(
                isKeeper,
                now: verifiedAt
            )
            entitlementPresentationChanged = beforeVerification
                != EastKeeperRitualStore.resolvedSnapshot(now: verifiedAt)
        }

        guard isKeeper else {
            if entitlementPresentationChanged {
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
        if entitlementPresentationChanged || result.changed {
            WidgetCenter.shared.reloadTimelines(ofKind: EastWidgetKind.keeperRitualKind)
        }
        return .result()
    }
}
