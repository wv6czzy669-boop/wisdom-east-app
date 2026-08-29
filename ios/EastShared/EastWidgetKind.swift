import Foundation

/// WidgetKit kinds shared by Runner and the extension. The original kind is
/// intentionally unchanged so existing free widgets keep their identity and
/// configuration across the Keeper-widget addition.
enum EastWidgetKind {
    static let kind = "EASTWidget"
    static let keeperRitualKind = "EASTKeeperRitualWidget"
}
