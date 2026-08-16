import WidgetKit

struct EastWidgetEntry: TimelineEntry {
    let date: Date
    let state: EastWidgetState
}

/// EAST. Phase 11 -- resolves every entry from `EastWidgetSnapshotStore`
/// alone. This provider never selects, generates, or reveals wisdom itself;
/// Flutter's `DailyWisdomAccessService` is the sole authority, and this type
/// only ever reads what `EastWidgetSnapshotBridge` (running inside the app)
/// most recently published.
struct EastWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EastWidgetEntry {
        EastWidgetEntry(date: Date(), state: .silence)
    }

    func getSnapshot(in context: Context, completion: @escaping (EastWidgetEntry) -> Void) {
        if context.isPreview {
            completion(EastWidgetEntry(date: Date(), state: .silence))
            return
        }
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EastWidgetEntry>) -> Void) {
        let entry = currentEntry()
        switch entry.state {
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
            // fires a little late: `EastWidgetSnapshotStore.resolvedState`
            // never trusts a "revealed" flag past its own `unlockAt`.
            completion(Timeline(entries: [entry], policy: .after(unlockAt)))
        }
    }

    private func currentEntry() -> EastWidgetEntry {
        EastWidgetEntry(date: Date(), state: EastWidgetSnapshotStore.resolvedState(now: Date()))
    }
}
