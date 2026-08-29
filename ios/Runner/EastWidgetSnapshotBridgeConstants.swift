import Foundation

/// Channel/method/argument names for the widget-snapshot bridge, mirroring
/// `CloudKitSyncBridgeConstants`'s role for the CloudKit channel.
enum EastWidgetSnapshotBridgeConstants {
    static let methodChannelName = "com.dogukan.dailywisdom/widget_snapshot"

    static let methodPublishRevealed = "publishRevealed"
    static let methodPublishSilence = "publishSilence"
    static let methodReadKeeperRitualSnapshot = "readKeeperRitualSnapshot"
    static let methodSetKeeperEntitlement = "setKeeperEntitlement"
    static let methodPublishKeeperPrepared = "publishKeeperPrepared"
    static let methodPublishKeeperActive = "publishKeeperActive"

    static let argText = "text"
    static let argUnlockAtMillis = "unlockAtMillis"

    /// EAST. 1.2 Slice 2A -- both optional. Their presence (not merely a
    /// valid value) is what distinguishes a presentation-aware call from a
    /// legacy one -- see `EastWidgetSnapshotBridge.containsPresentationPayload`.
    static let argAppearanceMode = "appearanceMode"
    static let argLocaleOverrideTag = "localeOverrideTag"

    static let argIsKeeper = "isKeeper"
    static let argCandidateId = "candidateId"
    static let argCanonicalText = "canonicalText"
    static let argDisplayText = "displayText"
    static let argWisdomId = "wisdomId"
    static let argPreparedAtMillis = "preparedAtMillis"
    static let argActivationAtMillis = "activationAtMillis"
    static let argRevealedAtMillis = "revealedAtMillis"
    static let argRevealId = "revealId"
}
