import SwiftUI
import WidgetKit

struct EastWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: EastWidgetKind.kind, provider: EastWidgetProvider()) { entry in
            EastWidgetView(entry: entry)
        }
        .configurationDisplayName("EAST.")
        .description("A quiet space for the day's wisdom.")
        .supportedFamilies([.systemMedium])
    }
}

struct EastKeeperRitualWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: EastWidgetKind.keeperRitualKind,
            provider: EastKeeperRitualProvider()
        ) { entry in
            EastKeeperRitualView(entry: entry)
        }
        .configurationDisplayName("EAST. Keeper Ritual")
        .description("Pause. Feel. Ask from your heart.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct EastWidgetBundle: WidgetBundle {
    var body: some Widget {
        EastWidget()
        EastKeeperRitualWidget()
    }
}
