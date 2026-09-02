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
            duration: ritualTransitionDuration,
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

    /// The app lets the final wisdom arrive more slowly than the preceding
    /// ritual beats. Keep the widget responsive through Pause, Feel, and Ask,
    /// then give only the Ask -> wisdom transition the same quiet weight.
    /// There is deliberately no artificial blank state or delayed action.
    private var ritualTransitionDuration: TimeInterval {
        switch entry.snapshot.content {
        case .revealed:
            return 1.2
        case .keeperRequired, .waiting, .pause, .feel, .heart:
            return 0.55
        }
    }
}

/// WidgetKit animates App Intent driven data changes on iOS 17 and later.
/// The ritual uses only a restrained opacity transition: no scale, slide,
/// ring, or progress-like motion. Reduce Motion removes even that fade.
private struct EastKeeperRitualTransition: ViewModifier {
    let value: String
    let duration: TimeInterval
    let reduceMotion: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content
                .contentTransition(reduceMotion ? .identity : .opacity)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: duration),
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
        // Generated Cartesian matrix: 15 product locales x Light/Dark x
        // every visible state. The revealed cell uses a deliberately long
        // reviewed wisdom in that script, making clipping, bad wrapping,
        // RTL regressions, or accidental color drift visible in one canvas.
        ForEach(EastKeeperRitualPreviewScenario.all) { scenario in
            preview(scenario)
        }
    }

    private static func preview(_ scenario: EastKeeperRitualPreviewScenario) -> some View {
        EastKeeperRitualView(entry: EastKeeperRitualEntry(
            date: EastKeeperRitualPreviewScenario.now,
            snapshot: EastKeeperRitualSnapshot(
                content: scenario.content,
                presentation: scenario.presentation
            )
        ))
        .previewContext(WidgetPreviewContext(family: .systemMedium))
        .previewDisplayName(scenario.name)
    }
}

private struct EastKeeperRitualPreviewScenario: Identifiable {
    fileprivate static let now = Date(timeIntervalSince1970: 1_777_777_000)

    private static let localeTags = EastWidgetLocaleResolver.validProductTags.sorted()
    private static let appearances: [EastWidgetAppearanceMode] = [.light, .dark]

    /// Long reviewed catalog entries are intentional layout stress cases.
    private static let longWisdoms: [String: String] = [
        "en": "Some guidance feels like losing interest in what once consumed you.",
        "tr": "Ruh, tekrarın açığa çıkarmaya çalıştığı şeyi fark eder.",
        "ja": "かつて心を占め尽くしたものに興味を失うことが、導きに感じられるときもある。",
        "de": "Manches Ende gibt dir die Kraft zurück, von der du vergessen hattest, dass sie deine war.",
        "fr": "Une lumière n’entre parfois qu’après l’adaptation des yeux à l’obscurité.",
        "ko": "자아가 소유할 수 없는 것 때문에 정신이 혼란스러워지는 것은 아니다.",
        "zh-Hant": "不是所有移動都是進展，也不是所有靜止都是停滯。",
        "ar": "لا تُفتح بعض الأبواب إلا حين يحل الامتنان محل المطالبة.",
        "es": "Lo que no puedes controlar quizá aún te esté cuidando.",
        "pt-BR": "Algumas verdades não são explicações; são libertações.",
        "it": "Alcune persone arrivano in silenzio e cambiano per sempre la tua direzione.",
        "th": "ไม่ใช่ทุกการเคลื่อนไหวคือความก้าวหน้า และไม่ใช่ทุกความนิ่งคือการติดอยู่",
        "nl": "Sommige seizoenen zijn bedoeld om voor het verkeerde onzichtbaar te worden.",
        "pl": "Twój spokój jest częścią ścieżki, nie nagrodą na końcu.",
        "vi": "Không phải mọi chuyển động đều tiến bộ, cũng không phải mọi tĩnh tại đều mắc kẹt.",
    ]

    static let all: [EastKeeperRitualPreviewScenario] = localeTags.flatMap { localeTag in
        appearances.flatMap { appearance in
            EastKeeperRitualPreviewState.allCases.map { state in
                EastKeeperRitualPreviewScenario(
                    localeTag: localeTag,
                    appearance: appearance,
                    state: state
                )
            }
        }
    }

    let localeTag: String
    let appearance: EastWidgetAppearanceMode
    let state: EastKeeperRitualPreviewState

    var id: String { "\(localeTag)-\(appearance.rawValue)-\(state.rawValue)" }
    var name: String { "\(localeTag) · \(appearance.rawValue) · \(state.rawValue)" }

    var presentation: EastWidgetPresentation {
        EastWidgetPresentation(
            appearanceMode: appearance,
            localeOverrideTag: localeTag
        )
    }

    var content: EastKeeperRitualContent {
        switch state {
        case .keeperRequired:
            return .keeperRequired
        case .waiting:
            return .waiting(activationAt: nil)
        case .pause:
            return .pause
        case .feel:
            return .feel
        case .heart:
            return .heart
        case .revealed:
            // Intentionally fail a DEBUG preview if a future product locale
            // is added without its own long-script layout stress sample.
            let displayText = Self.longWisdoms[localeTag]!
            return .revealed(EastKeeperRitualReveal(
                candidateId: "preview-\(localeTag)",
                canonicalText: Self.longWisdoms["en"]!,
                displayText: displayText,
                wisdomId: "east_wisdom_0001",
                revealedAt: Self.now,
                unlockAt: Self.now.addingTimeInterval(3600),
                revealId: nil,
                needsAppCommit: true
            ))
        }
    }
}

private enum EastKeeperRitualPreviewState: String, CaseIterable {
    case keeperRequired
    case waiting
    case pause
    case feel
    case heart
    case revealed
}
#endif
