import SwiftUI
import WidgetKit

/// EAST.'s warm-stone and ink palette, matching the app's EB Garamond
/// typography exactly -- no new logo, no new font, no changed color values.
///
/// Visual-polish repair: iOS already labels this widget "EAST." below its
/// frame (the Home Screen widget/application label), so the interior no
/// longer repeats a ring or wordmark of its own -- only the phrase itself.
///
/// Appearance: EAST. 1.2 Slice 2B -- `.light`/`.dark` (`entry.snapshot
/// .presentation.appearanceMode`) now always win outright over the device's
/// system color scheme, honoring the in-app explicit override exactly as
/// product requires. `.system` continues to follow
/// `@Environment(\.colorScheme)` precisely as before this slice -- no
/// brightness observation or timeline reload logic was added; WidgetKit's
/// own color-scheme environment still drives that case natively. The light
/// values remain pinned to the app's own locked field/ink; the dark values
/// remain the app's locked Dark Mode field/ink (`east_design.dart`'s
/// `EastColorScheme.dark`).
let eastStoneLight = Color(red: 226.0 / 255.0, green: 224.0 / 255.0, blue: 217.0 / 255.0)
let eastInkLight = Color(red: 44.0 / 255.0, green: 41.0 / 255.0, blue: 36.0 / 255.0)
let eastStoneDark = Color(red: 28.0 / 255.0, green: 27.0 / 255.0, blue: 24.0 / 255.0)
let eastInkDark = Color(red: 216.0 / 255.0, green: 212.0 / 255.0, blue: 203.0 / 255.0)
let eastWidgetURL = URL(string: "eastwidget://open")!

struct EastWidgetView: View {
    let entry: EastWidgetEntry

    @Environment(\.colorScheme) private var systemColorScheme

    private var presentation: EastWidgetPresentation { entry.snapshot.presentation }

    /// `.light`/`.dark` always win outright; `.system` continues to follow
    /// `@Environment(\.colorScheme)` exactly as before this slice.
    private var resolvedColorScheme: ColorScheme {
        switch presentation.appearanceMode {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return systemColorScheme
        }
    }

    private var eastStone: Color {
        resolvedColorScheme == .dark ? eastStoneDark : eastStoneLight
    }

    private var eastInk: Color {
        resolvedColorScheme == .dark ? eastInkDark : eastInkLight
    }

    /// Resolved once per render, mirroring
    /// `EastWidgetLocaleResolver.resolvedProductTag` exactly: a valid
    /// explicit override (`presentation.localeOverrideTag`) always wins;
    /// otherwise the extension's own current system preferred languages
    /// (`Locale.preferredLanguages`, read live, never a value frozen at
    /// publish time) are used, falling back to reviewed English when
    /// unsupported.
    private var resolvedLocaleTag: String {
        EastWidgetLocaleResolver.resolvedProductTag(
            localeOverrideTag: presentation.localeOverrideTag,
            preferredLanguages: Locale.preferredLanguages
        )
    }

    private var resolvedLocale: Locale {
        Locale(identifier: resolvedLocaleTag)
    }

    /// `ar` is EAST.'s sole RTL product locale; every other resolved
    /// product tag renders left-to-right.
    private var resolvedLayoutDirection: LayoutDirection {
        EastWidgetLocaleResolver.isRtl(productTag: resolvedLocaleTag) ? .rightToLeft : .leftToRight
    }

    var body: some View {
        GeometryReader { geometry in
            mainText
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                // Optical, not mechanical, centering: a text block sitting
                // at true geometric center reads as slightly low (most of
                // its visual weight is above its own baseline), so this
                // nudges it up a touch from dead-center.
                .offset(y: -geometry.size.height * 0.045)
                // EAST. 1.2 Slice 2B -- applied narrowly to the widget
                // content only, never touching geometry, padding, or
                // anything above this point. `.multilineTextAlignment
                // (.leading)` inside `eastText(_:)` is unchanged -- "leading"
                // itself now follows whichever direction is set here.
                .environment(\.locale, resolvedLocale)
                .environment(\.layoutDirection, resolvedLayoutDirection)
        }
        .padding(.horizontal, 22)
        .widgetURL(eastWidgetURL)
        .modifier(EastWidgetBackground(color: eastStone))
    }

    @ViewBuilder
    private var mainText: some View {
        switch entry.snapshot.content {
        case .silence:
            eastText(silenceText)
                .accessibilityLabel(silenceText)
        case let .revealed(text, _):
            // Continues rendering exactly the already-Dart-resolved text
            // this content case carries -- no native wisdom lookup, and
            // text/date are never used as identity here or anywhere in this
            // view; only the resolved locale/layout direction above affect
            // how this already-final string is rendered.
            eastText(text)
                .accessibilityLabel(text)
        }
    }

    /// Resolved once per render through the shared `Localizable.xcstrings`
    /// catalog, using the explicit `resolvedLocale` (EAST. 1.2 Slice 2B)
    /// rather than the extension's ambient current locale -- `eastText(_:)`
    /// and `.accessibilityLabel(_:)` both take a plain `String` here, which
    /// bypasses SwiftUI's own literal-only `LocalizedStringKey` lookup, so
    /// this is the one place that must resolve localization explicitly. No
    /// translation was added or modified -- every one of the 15 product
    /// locales this key can resolve to already exists in
    /// `Localizable.xcstrings`.
    private var silenceText: String {
        String(localized: "Something waits in silence.", locale: resolvedLocale)
    }

    private func eastText(_ text: String) -> some View {
        Text(text)
            .font(.custom("EBGaramond-Regular", size: fontSize(for: text)))
            .foregroundStyle(eastInk)
            .lineSpacing(4)
            .lineLimit(5)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(EastWidgetAccent())
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

/// Keeps the iOS 17+ removable widget background contract while preserving
/// the identical full-surface stone background on iOS 15-16, where
/// `containerBackground(for:)` does not exist yet.
struct EastWidgetBackground: ViewModifier {
    let color: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(color, for: .widget)
        } else {
            content.background(color)
        }
    }
}

/// Accent participation was introduced in iOS 16. Earlier widgets retain
/// the exact same text rendering and simply omit that unavailable hint.
struct EastWidgetAccent: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 16.0, *) {
            content.widgetAccentable()
        } else {
            content
        }
    }
}

// MARK: - Previews
//
// Development aids only -- not automated tests. Provider/View correctness
// beyond compilation is validated by these previews and later physical-
// device QA, not by an automated SwiftUI rendering test harness.

#if DEBUG
struct EastWidgetView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            preview(
                "Silence",
                snapshot: EastWidgetSnapshot(content: .silence, presentation: .systemDefault)
            )
            preview(
                "Revealed -- shortest",
                snapshot: EastWidgetSnapshot(
                    content: .revealed(text: "Peace enters slowly.", unlockAt: .now.addingTimeInterval(3600)),
                    presentation: .systemDefault
                )
            )
            preview(
                "Revealed -- typical",
                snapshot: EastWidgetSnapshot(
                    content: .revealed(
                        text: "Let the heart be spacious enough to release.",
                        unlockAt: .now.addingTimeInterval(3600)
                    ),
                    presentation: .systemDefault
                )
            )
            preview(
                "Revealed -- longest",
                snapshot: EastWidgetSnapshot(
                    content: .revealed(
                        text: "Some guidance feels like losing interest in what once consumed you.",
                        unlockAt: .now.addingTimeInterval(3600)
                    ),
                    presentation: .systemDefault
                )
            )
            preview(
                "Explicit Light",
                snapshot: EastWidgetSnapshot(
                    content: .revealed(text: "Peace enters slowly.", unlockAt: .now.addingTimeInterval(3600)),
                    presentation: EastWidgetPresentation(appearanceMode: .light, localeOverrideTag: nil)
                )
            )
            preview(
                "Explicit Dark",
                snapshot: EastWidgetSnapshot(
                    content: .revealed(text: "Peace enters slowly.", unlockAt: .now.addingTimeInterval(3600)),
                    presentation: EastWidgetPresentation(appearanceMode: .dark, localeOverrideTag: nil)
                )
            )
            preview(
                "Arabic RTL",
                snapshot: EastWidgetSnapshot(
                    content: .revealed(text: "السلام يدخل ببطء.", unlockAt: .now.addingTimeInterval(3600)),
                    presentation: EastWidgetPresentation(appearanceMode: .system, localeOverrideTag: "ar")
                )
            )
        }
    }

    private static func preview(_ name: String, snapshot: EastWidgetSnapshot) -> some View {
        EastWidgetView(entry: EastWidgetEntry(date: .now, snapshot: snapshot))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName(name)
    }
}
#endif
