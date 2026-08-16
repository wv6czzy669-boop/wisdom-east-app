import Foundation

/// Channel/method/argument names for the widget-snapshot bridge, mirroring
/// `CloudKitSyncBridgeConstants`'s role for the CloudKit channel.
enum EastWidgetSnapshotBridgeConstants {
    static let methodChannelName = "com.dogukan.dailywisdom/widget_snapshot"

    static let methodPublishRevealed = "publishRevealed"
    static let methodPublishSilence = "publishSilence"

    static let argText = "text"
    static let argUnlockAtMillis = "unlockAtMillis"
}
