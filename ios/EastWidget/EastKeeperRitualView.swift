import SwiftUI
import WidgetKit

struct EastKeeperRitualView: View {
    let entry: EastKeeperRitualEntry

    @Environment(\.colorScheme) private var systemColorScheme

    private var presentation: EastWidgetPresentation { entry.snapshot.presentation }

    private var resolvedColorScheme: ColorScheme {
        switch presentation.appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemColorScheme
        }
    }

    private var eastStone: Color {
        resolvedColorScheme == .dark ? eastStoneDark : eastStoneLight
    }

    private var eastInk: Color {
        resolvedColorScheme == .dark ? eastInkDark : eastInkLight
    }

    private var localeTag: String {
        EastWidgetLocaleResolver.resolvedProductTag(
            localeOverrideTag: presentation.localeOverrideTag,
            preferredLanguages: Locale.preferredLanguages
        )
    }

    private var locale: Locale { Locale(identifier: localeTag) }

    private var layoutDirection: LayoutDirection {
        EastWidgetLocaleResolver.isRtl(productTag: localeTag) ? .rightToLeft : .leftToRight
    }

    var body: some View {
        interactiveSurface
            .environment(\.locale, locale)
            .environment(\.layoutDirection, layoutDirection)
            .modifier(EastWidgetBackground(color: eastStone))
    }

    @ViewBuilder
    private var interactiveSurface: some View {
        switch entry.snapshot.content {
        case .revealed:
            Link(destination: eastWidgetURL) { content }
                .buttonStyle(.plain)
        case .keeperRequired, .waiting:
            Link(destination: eastWidgetURL) { content }
                .buttonStyle(.plain)
        case .pause, .feel, .heart:
            if #available(iOSApplicationExtension 17.0, *) {
                Button(intent: EastKeeperRitualAdvanceIntent()) { content }
                    .buttonStyle(.plain)
            } else {
                Link(destination: eastWidgetURL) { content }
                    .buttonStyle(.plain)
            }
        }
    }

    private var content: some View {
        GeometryReader { geometry in
            mainText
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(y: -geometry.size.height * 0.045)
        }
        .padding(.horizontal, 22)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var mainText: some View {
        switch entry.snapshot.content {
        case .keeperRequired:
            eastText(localized("Available with Keeper."), size: 24)
        case .waiting:
            eastText(localized("Something waits in silence."), size: 24)
        case .pause:
            eastText(localized("Pause."), size: 31)
        case .feel:
            eastText(localized("Feel."), size: 31)
        case .heart:
            eastText(localized("Ask from your heart."), size: 28)
        case let .revealed(reveal):
            eastText(reveal.displayText, size: wisdomFontSize(for: reveal.displayText))
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: locale)
    }

    private func eastText(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.custom("EBGaramond-Regular", size: size))
            .foregroundStyle(eastInk)
            .lineSpacing(4)
            .lineLimit(5)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
            .modifier(EastWidgetAccent())
    }

    private func wisdomFontSize(for text: String) -> CGFloat {
        switch text.count {
        case 0...28: return 28
        case 29...48: return 23
        default: return 19
        }
    }
}

#if DEBUG
struct EastKeeperRitualView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            preview("Pause", content: .pause)
            preview("Feel", content: .feel)
            preview("Heart", content: .heart)
            preview(
                "Revealed",
                content: .revealed(EastKeeperRitualReveal(
                    candidateId: "east_wisdom_0001:1",
                    canonicalText: "Peace enters slowly.",
                    displayText: "Peace enters slowly.",
                    wisdomId: "east_wisdom_0001",
                    revealedAt: .now,
                    unlockAt: .now.addingTimeInterval(3600),
                    revealId: nil,
                    needsAppCommit: true
                ))
            )
        }
    }

    private static func preview(
        _ name: String,
        content: EastKeeperRitualContent
    ) -> some View {
        EastKeeperRitualView(entry: EastKeeperRitualEntry(
            date: .now,
            snapshot: EastKeeperRitualSnapshot(
                content: content,
                presentation: .systemDefault
            )
        ))
        .previewContext(WidgetPreviewContext(family: .systemMedium))
        .previewDisplayName(name)
    }
}
#endif
