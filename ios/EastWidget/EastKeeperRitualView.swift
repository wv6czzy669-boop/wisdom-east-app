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
        ZStack {
            content
                .accessibilityHidden(true)
            interactionTarget
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.locale, locale)
        .environment(\.layoutDirection, layoutDirection)
        .modifier(EastWidgetBackground(color: eastStone))
    }

    @ViewBuilder
    private var interactionTarget: some View {
        switch entry.snapshot.content {
        case .revealed:
            Link(destination: eastWidgetURL) { clearInteractionSurface }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityText)
        case .keeperRequired, .waiting:
            Link(destination: eastWidgetURL) { clearInteractionSurface }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityText)
        case .pause, .feel, .heart:
            if #available(iOSApplicationExtension 17.0, *) {
                Button(intent: EastKeeperRitualAdvanceIntent()) {
                    clearInteractionSurface
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityText)
            } else {
                Link(destination: eastWidgetURL) { clearInteractionSurface }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityText)
            }
        }
    }

    private var clearInteractionSurface: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }

    private var content: some View {
        ZStack {
            ritualLayer(opacity: keeperRequiredOpacity) {
                eastText(
                    localized("Available with Keeper."),
                    size: 23,
                    lineLimit: 3
                )
            }
            ritualLayer(opacity: waitingOpacity) {
                eastText(
                    localized("Something waits in silence."),
                    size: 23,
                    lineLimit: 3
                )
            }
            ritualLayer(opacity: pauseOpacity) {
                eastText(localized("Pause."), size: 36, lineLimit: 1)
            }
            ritualLayer(opacity: feelOpacity, offsetY: 44) {
                eastText(localized("Feel."), size: 36, lineLimit: 1)
            }
            ritualLayer(opacity: heartOpacity) {
                eastText(
                    localized("Ask from your heart."),
                    size: 29,
                    lineLimit: 2,
                    maximumWidth: 282
                )
            }
            ritualLayer(opacity: revealedOpacity) {
                eastText(
                    revealedText,
                    size: wisdomFontSize(for: revealedText),
                    lineLimit: 5
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .modifier(EastKeeperRitualInvalidation(
            invalidatable: isInteractiveRitualPhase
        ))
    }

    private func ritualLayer<Layer: View>(
        opacity: Double,
        offsetY: CGFloat = 0,
        @ViewBuilder content: () -> Layer
    ) -> some View {
        content()
            .offset(y: offsetY)
            .opacity(opacity)
            .modifier(EastKeeperRitualLayerAnimation(
                value: contentIdentity,
                duration: ritualAnimationDuration,
                reduceMotion: reduceMotion
            ))
    }

    private var keeperRequiredOpacity: Double {
        if case .keeperRequired = entry.snapshot.content { return 1 }
        return 0
    }

    private var waitingOpacity: Double {
        if case .waiting = entry.snapshot.content { return 1 }
        return 0
    }

    /// Pause owns one fixed optical axis in both of its visible states.
    /// Feel arrives 44pt below it without recentering the pair, matching the
    /// app ritual instead of making Pause jump upward on the first tap.
    private var pauseOpacity: Double {
        switch entry.snapshot.content {
        case .pause: return 1
        case .feel: return 0.28
        case .keeperRequired, .waiting, .heart, .revealed: return 0
        }
    }

    private var feelOpacity: Double {
        if case .feel = entry.snapshot.content { return 1 }
        return 0
    }

    private var heartOpacity: Double {
        if case .heart = entry.snapshot.content { return 1 }
        return 0
    }

    private var revealedOpacity: Double {
        if case .revealed = entry.snapshot.content { return 1 }
        return 0
    }

    private var revealedText: String {
        guard case let .revealed(reveal) = entry.snapshot.content else {
            return ""
        }
        return reveal.displayText
    }

    private var isInteractiveRitualPhase: Bool {
        switch entry.snapshot.content {
        case .pause, .feel, .heart: return true
        case .keeperRequired, .waiting, .revealed: return false
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: locale)
    }

    private func eastText(
        _ text: String,
        size: CGFloat,
        lineLimit: Int,
        maximumWidth: CGFloat? = nil
    ) -> some View {
        Text(text)
            .font(.custom("EBGaramond-Regular", size: size))
            .fontWeight(.regular)
            .foregroundStyle(eastInk)
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

    /// WidgetKit updates are snapshots, not a continuously running app view.
    /// A short ease-out acknowledges each tap immediately; only the wisdom is
    /// given a slightly longer arrival. Both remain well below the system's
    /// two-second animation ceiling and avoid the sluggish 1.2s whole-view
    /// dissolve that previously followed the App Intent round trip.
    private var ritualAnimationDuration: TimeInterval {
        switch entry.snapshot.content {
        case .revealed:
            return 0.72
        case .keeperRequired, .waiting, .pause, .feel, .heart:
            return 0.52
        }
    }
}

/// The visible hierarchy is intentionally stable across every timeline entry.
/// Only layer opacity changes, so WidgetKit never combines an identity swap,
/// insertion transition, and content transition for the same ritual beat.
private struct EastKeeperRitualLayerAnimation: ViewModifier {
    let value: String
    let duration: TimeInterval
    let reduceMotion: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content
                .contentTransition(.identity)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: duration),
                    value: value
                )
        } else {
            content
        }
    }
}

/// App Intents necessarily complete in the widget extension before WidgetKit
/// installs the next entry. Mark only the changing ritual text invalidatable,
/// not the background or the whole widget, so iOS can acknowledge the tap at
/// once without introducing a spinner, progress UI, or decorative animation.
private struct EastKeeperRitualInvalidation: ViewModifier {
    let invalidatable: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.invalidatableContent(invalidatable)
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
