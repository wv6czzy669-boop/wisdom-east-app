import Foundation

/// The single WidgetKit widget kind EAST. ships, shared between the Runner
/// app (which reloads this kind's timelines after an authoritative reveal or
/// silence transition) and the EastWidgetExtension target (which declares
/// its `StaticConfiguration` under this exact same kind). One name, one
/// source of truth -- never duplicated as a string literal on either side.
enum EastWidgetKind {
    static let kind = "EASTWidget"
}
