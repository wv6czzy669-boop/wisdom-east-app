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

@main
struct EastWidgetBundle: WidgetBundle {
    var body: some Widget {
        EastWidget()
    }
}
