import SwiftUI
import WidgetKit

/// EAST.'s own cream-on-black palette, matching the app's own
/// `CormorantGaramond-Light` typography exactly -- no new logo, no new
/// font.
///
/// Visual-polish repair: iOS already labels this widget "EAST." below its
/// frame (the Home Screen widget/application label), so the interior no
/// longer repeats a ring or wordmark of its own -- only the phrase itself.
private let eastCream = Color(red: 244.0 / 255.0, green: 240.0 / 255.0, blue: 232.0 / 255.0)
private let eastBlack = Color(red: 4.0 / 255.0, green: 4.0 / 255.0, blue: 4.0 / 255.0)
private let eastWidgetURL = URL(string: "eastwidget://open")

struct EastWidgetView: View {
    let entry: EastWidgetEntry

    var body: some View {
        GeometryReader { geometry in
            mainText
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                // Optical, not mechanical, centering: a text block sitting
                // at true geometric center reads as slightly low (most of
                // its visual weight is above its own baseline), so this
                // nudges it up a touch from dead-center.
                .offset(y: -geometry.size.height * 0.045)
        }
        .padding(.horizontal, 22)
        .widgetURL(eastWidgetURL)
        .containerBackground(for: .widget) {
            eastBlack
        }
    }

    @ViewBuilder
    private var mainText: some View {
        switch entry.state {
        case .silence:
            eastText("Something waits in silence.")
                .accessibilityLabel("Something waits in silence.")
        case let .revealed(text, _):
            eastText(text)
                .accessibilityLabel(text)
        }
    }

    private func eastText(_ text: String) -> some View {
        Text(text)
            .font(.custom("CormorantGaramond-Light", size: fontSize(for: text)))
            .foregroundStyle(eastCream)
            .lineSpacing(4)
            .lineLimit(5)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .widgetAccentable()
    }

    /// A short phrase reads as more confident/editorial at a larger scale;
    /// a long one steps down in controlled tiers so it never needs
    /// `minimumScaleFactor` to do more than a small final safety
    /// adjustment -- never an ellipsis, never clipping, never microscopic
    /// type, across the real corpus's shortest/typical/longest entries.
    private func fontSize(for text: String) -> CGFloat {
        switch text.count {
        case 0...28:
            return 28
        case 29...48:
            return 23
        default:
            return 19
        }
    }
}

// MARK: - Previews

#Preview("Silence", as: .systemMedium) {
    EastWidget()
} timeline: {
    EastWidgetEntry(date: .now, state: .silence)
}

#Preview("Revealed -- shortest", as: .systemMedium) {
    EastWidget()
} timeline: {
    EastWidgetEntry(
        date: .now,
        state: .revealed(text: "Peace enters slowly.", unlockAt: .now.addingTimeInterval(3600))
    )
}

#Preview("Revealed -- typical", as: .systemMedium) {
    EastWidget()
} timeline: {
    EastWidgetEntry(
        date: .now,
        state: .revealed(
            text: "Let the heart be spacious enough to release.",
            unlockAt: .now.addingTimeInterval(3600)
        )
    )
}

#Preview("Revealed -- longest", as: .systemMedium) {
    EastWidget()
} timeline: {
    EastWidgetEntry(
        date: .now,
        state: .revealed(
            text: "Some guidance feels like losing interest in what once consumed you.",
            unlockAt: .now.addingTimeInterval(3600)
        )
    )
}
