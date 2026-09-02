import SwiftUI
import WidgetKit

struct EastKeeperRitualView: View {
    let entry: EastKeeperRitualEntry

    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        ZStack {
            mainText
                .id(contentIdentity)
                .transition(reduceMotion ? .identity : .opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .modifier(EastKeeperRitualTransition(
            value: contentIdentity,
            reduceMotion: reduceMotion
        ))
    }

    @ViewBuilder
    private var mainText: some View {
        switch entry.snapshot.content {
        case .keeperRequired:
            eastText(
                localized("Available with Keeper."),
                size: 23,
                lineLimit: 3
            )
        case .waiting:
            eastText(
                localized("Something waits in silence."),
                size: 23,
                lineLimit: 3
            )
        case .pause:
            eastText(localized("Pause."), size: 36, lineLimit: 1)
        case .feel:
            VStack(spacing: 12) {
                eastText(
                    localized("Pause."),
                    size: 34,
                    color: eastInk.opacity(0.28),
                    lineLimit: 1
                )
                eastText(localized("Feel."), size: 36, lineLimit: 1)
            }
        case .heart:
            eastText(
                localized("Ask from your heart."),
                size: 29,
                lineLimit: 2,
                maximumWidth: 282
            )
        case let .revealed(reveal):
            eastText(
                reveal.displayText,
                size: wisdomFontSize(for: reveal.displayText),
                lineLimit: 5
            )
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: locale)
    }

    private func eastText(
        _ text: String,
        size: CGFloat,
        color: Color? = nil,
        lineLimit: Int,
        maximumWidth: CGFloat? = nil
    ) -> some View {
        Text(text)
            .font(.custom("EBGaramond-Regular", size: size))
            .fontWeight(.regular)
            .foregroundStyle(color ?? eastInk)
            .lineSpacing(3)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maximumWidth ?? .infinity, alignment: .center)
            .modifier(EastWidgetAccent())
    }

    private func wisdomFontSize(for text: String) -> CGFloat {
        let baseSize: CGFloat
        switch text.count {
        case 0...28: baseSize = 27
        case 29...52: baseSize = 24
        default: baseSize = 22
        }

        // Keep unusually long Latin-script words intact by giving them a
        // little more horizontal room before SwiftUI needs its final scale
        // safety. CJK text intentionally follows its native character-wrap
        // behavior because it doesn't contain word-separating whitespace.
        let words = text.split(whereSeparator: { $0.isWhitespace })
        let longestWord = words.map(\.count).max() ?? 0
        guard words.count > 1, longestWord > 17 else { return baseSize }
        return max(20, baseSize - 2)
    }

    private var accessibilityText: String {
        switch entry.snapshot.content {
        case .keeperRequired:
            return localized("Available with Keeper.")
        case .waiting:
            return localized("Something waits in silence.")
        case .pause:
            return localized("Pause.")
        case .feel:
            return "\(localized("Pause.")) \(localized("Feel."))"
        case .heart:
            return localized("Ask from your heart.")
        case let .revealed(reveal):
            return reveal.displayText
        }
    }

    private var contentIdentity: String {
        switch entry.snapshot.content {
        case .keeperRequired: return "keeper-required"
        case .waiting: return "waiting"
        case .pause: return "pause"
        case .feel: return "feel"
        case .heart: return "heart"
        case let .revealed(reveal): return "revealed-\(reveal.candidateId)"
        }
    }
}

/// WidgetKit animates App Intent driven data changes on iOS 17 and later.
/// The ritual uses only a restrained opacity transition: no scale, slide,
/// ring, or progress-like motion. Reduce Motion removes even that fade.
private struct EastKeeperRitualTransition: ViewModifier {
    let value: String
    let reduceMotion: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content
                .contentTransition(reduceMotion ? .identity : .opacity)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.55),
                    value: value
                )
        } else {
            content
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
            preview(
                "Revealed -- long",
                content: .revealed(EastKeeperRitualReveal(
                    candidateId: "east_wisdom_0002:1",
                    canonicalText: "Some guidance arrives only after certainty softens.",
                    displayText: "Some guidance arrives only after certainty softens.",
                    wisdomId: "east_wisdom_0002",
                    revealedAt: .now,
                    unlockAt: .now.addingTimeInterval(3600),
                    revealId: nil,
                    needsAppCommit: true
                ))
            )
            preview(
                "Arabic",
                content: .heart,
                presentation: EastWidgetPresentation(
                    appearanceMode: .light,
                    localeOverrideTag: "ar"
                )
            )
            preview(
                "Dark",
                content: .feel,
                presentation: EastWidgetPresentation(
                    appearanceMode: .dark,
                    localeOverrideTag: "en"
                )
            )
        }
    }

    private static func preview(
        _ name: String,
        content: EastKeeperRitualContent,
        presentation: EastWidgetPresentation = .systemDefault
    ) -> some View {
        EastKeeperRitualView(entry: EastKeeperRitualEntry(
            date: .now,
            snapshot: EastKeeperRitualSnapshot(
                content: content,
                presentation: presentation
            )
        ))
        .previewContext(WidgetPreviewContext(family: .systemMedium))
        .previewDisplayName(name)
    }
}
#endif
