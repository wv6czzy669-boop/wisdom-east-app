import WidgetKit

struct EastWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: EastWidgetSnapshot
}

/// EAST. Phase 11, extended in 1.2 Slice 2B -- resolves every entry from
/// `EastWidgetSnapshotStore` alone. This provider never selects, generates,
/// or reveals wisdom itself; Flutter's `DailyWisdomAccessService` is the
/// sole authority, and this type only ever reads what
/// `EastWidgetSnapshotBridge` (running inside the app) most recently
/// published. Carrying the full `EastWidgetSnapshot` (content +
/// presentation) instead of content alone changes nothing about timing --
/// every timeline-expiry decision below is still driven exclusively by
/// `snapshot.content`, exactly as it always was; presentation travels along
/// for `EastWidgetView` to read, never influencing this provider's own
/// logic.
struct EastWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EastWidgetEntry {
        EastWidgetEntry(date: Date(), snapshot: .placeholderSilence)
    }

    func getSnapshot(in context: Context, completion: @escaping (EastWidgetEntry) -> Void) {
        if context.isPreview {
            completion(EastWidgetEntry(date: Date(), snapshot: .placeholderSilence))
            return
        }
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EastWidgetEntry>) -> Void) {
        let entry = currentEntry()
        switch entry.snapshot.content {
        case .silence:
            // Nothing to wake up for on its own -- the app is the only thing
            // that ever moves this widget out of silence, by publishing a
            // fresh reveal and reloading this kind's timelines itself.
            completion(Timeline(entries: [entry], policy: .never))
        case let .revealed(_, unlockAt):
            // Native-scheduled expiry: WidgetKit itself re-invokes this
            // provider at `unlockAt`, at which point `currentEntry()` --
            // re-reading the self-healing store -- naturally resolves back
            // to `.silence`. No countdown is ever computed or shown in
            // between, and this stays correct even if the exact refresh
            // fires a little late: `EastWidgetSnapshotStore.resolvedSnapshot`
            // (via `resolvedState`) never trusts a "revealed" flag past its
            // own `unlockAt`.
            completion(Timeline(entries: [entry], policy: .after(unlockAt)))
        }
    }

    private func currentEntry() -> EastWidgetEntry {
        EastWidgetEntry(date: Date(), snapshot: EastWidgetSnapshotStore.resolvedSnapshot(now: Date()))
    }
}

private extension EastWidgetSnapshot {
    /// Used only for `placeholder`/preview-context entries -- never a real
    /// resolved value, exactly matching this provider's pre-1.2 placeholder
    /// behavior (`.silence`), paired with System Default presentation.
    static let placeholderSilence = EastWidgetSnapshot(content: .silence, presentation: .systemDefault)
}
