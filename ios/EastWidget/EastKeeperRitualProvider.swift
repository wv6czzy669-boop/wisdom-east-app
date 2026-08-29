import WidgetKit

struct EastKeeperRitualEntry: TimelineEntry {
    let date: Date
    let snapshot: EastKeeperRitualSnapshot
}

struct EastKeeperRitualProvider: TimelineProvider {
    func placeholder(in context: Context) -> EastKeeperRitualEntry {
        EastKeeperRitualEntry(
            date: .now,
            snapshot: EastKeeperRitualSnapshot(
                content: .pause,
                presentation: .systemDefault
            )
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (EastKeeperRitualEntry) -> Void
    ) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(currentEntry())
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<EastKeeperRitualEntry>) -> Void
    ) {
        let entry = currentEntry()
        let policy: TimelineReloadPolicy
        switch entry.snapshot.content {
        case let .revealed(reveal):
            policy = .after(reveal.unlockAt)
        case let .waiting(activationAt):
            policy = activationAt.map(TimelineReloadPolicy.after) ?? .never
        case .keeperRequired, .pause, .feel, .heart:
            policy = .never
        }
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func currentEntry() -> EastKeeperRitualEntry {
        let now = Date()
        return EastKeeperRitualEntry(
            date: now,
            snapshot: EastKeeperRitualStore.resolvedSnapshot(now: now)
        )
    }
}
