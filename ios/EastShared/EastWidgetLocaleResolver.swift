import Foundation

/// EAST. 1.2 Slice 2B -- the one native product-locale catalog and mapping
/// authority, shared by Runner and EastWidgetExtension. Foundation-only, no
/// UIKit/SwiftUI dependency, so it compiles unchanged into both targets.
///
/// This is the authoritative Swift-side mirror of
/// `lib/localization/east_locale_registry.dart`'s `EastLocaleRegistry
/// .productLocaleOrNull`/`.resolveProductLocale` and
/// `lib/controllers/locale_preference_controller.dart`'s
/// `LocalePreferenceController.resolveSystemLocale` -- the same precedent
/// already established by `CloudKitRecordIdentity.swift` mirroring
/// `deriveKeptWisdomRecordName`: the algorithm, not merely one
/// implementation of it, is specified once and mirrored exactly on both
/// sides of the Dart/Swift boundary. `EastWidgetSnapshotStore` delegates its
/// own locale-override validation here rather than keeping a second,
/// independent allowlist.
///
/// Never selects, generates, reveals, or identifies a wisdom occurrence --
/// this type resolves presentation (which language to render in) only.
enum EastWidgetLocaleResolver {
    /// EAST.'s 15 reviewed product locales -- the single native allowlist.
    static let validProductTags: Set<String> = [
        "en", "tr", "ja", "de", "fr", "ko", "zh-Hant", "ar", "es",
        "pt-BR", "it", "th", "nl", "pl", "vi",
    ]

    /// The only RTL product locale.
    private static let rtlProductTags: Set<String> = ["ar"]

    /// Absent, a bare technical fallback tag (`"pt"`, `"zh"`), a case
    /// variant, or any tag outside `validProductTags` all resolve to `nil`
    /// -- never guessed, never a crash.
    static func validatedOverrideTag(_ raw: String?) -> String? {
        guard let raw, validProductTags.contains(raw) else { return nil }
        return raw
    }

    /// A valid explicit override wins outright, regardless of system
    /// preference. Otherwise, the first system preferred-language
    /// identifier is mapped through the same product rules
    /// `EastLocaleRegistry.productLocaleOrNull` uses; an empty
    /// preferred-language list, or a preferred language with no product
    /// mapping, resolves to English -- mirroring `resolveProductLocale`'s
    /// own `?? english.locale` fallback exactly. (`resolveSystemLocale`'s
    /// own supported-list membership check is always satisfied in
    /// practice, since its `supportedLocales` argument is always exactly
    /// `EastLocaleRegistry.runtimeSupported` -- the same 15 tags this
    /// resolver already validates against -- so mirroring
    /// `resolveProductLocale` directly here is behaviorally identical.)
    static func resolvedProductTag(
        localeOverrideTag: String?,
        preferredLanguages: [String]
    ) -> String {
        if let explicit = validatedOverrideTag(localeOverrideTag) {
            return explicit
        }
        guard let identifier = preferredLanguages.first else { return "en" }
        return productTag(forIdentifier: identifier) ?? "en"
    }

    /// The full `Locale` for the resolved product tag, for narrow rendering
    /// use only (RTL/layout direction, and the widget's own
    /// `Localizable.xcstrings` lookup) -- never used to select, generate,
    /// or identify a wisdom occurrence.
    static func locale(
        localeOverrideTag: String?,
        preferredLanguages: [String]
    ) -> Locale {
        Locale(identifier: resolvedProductTag(
            localeOverrideTag: localeOverrideTag,
            preferredLanguages: preferredLanguages
        ))
    }

    /// `true` only for EAST.'s sole RTL product locale (`ar`).
    static func isRtl(productTag: String) -> Bool {
        rtlProductTags.contains(productTag)
    }

    // MARK: - Identifier -> product tag mapping

    /// Mirrors `EastLocaleRegistry.productLocaleOrNull` exactly: parses a
    /// BCP-47-ish identifier into language/script/region, applies EAST.'s
    /// reviewed Chinese/Portuguese region rules first, then falls back to a
    /// bare language-code match against the 15 product locales. Returns
    /// `nil` (never English here -- that fallback belongs to the caller,
    /// exactly as `productLocaleOrNull` returns `nil` and only
    /// `resolveProductLocale` applies the `?? english` fallback) when no
    /// product mapping exists.
    ///
    /// Parsing itself is delegated to `identifierComponents(_:)` below,
    /// which uses the modern, warning-free `Locale.Components(identifier:)`
    /// API on iOS 16+ and a `#available`-gated, warning-free fallback to
    /// the older `Locale.components(fromIdentifier:)` on iOS 15 -- the
    /// Runner minimum deployment target. Both paths produce identical
    /// language/script/region values for every identifier this resolver is
    /// ever given, so the mapping rules below are unaffected by which path
    /// actually ran.
    private static func productTag(forIdentifier identifier: String) -> String? {
        let parsed = identifierComponents(identifier)
        let language = parsed.language.lowercased()
        let script = parsed.script?.lowercased()
        let region = parsed.region?.uppercased()

        guard !language.isEmpty else { return nil }

        if language == "zh" {
            if script == "hant" || region == "TW" || region == "HK" || region == "MO" {
                return "zh-Hant"
            }
            return nil
        }
        if language == "pt" {
            return region == "BR" ? "pt-BR" : nil
        }

        // Ordinary supported languages with regions resolve to their
        // reviewed base product tag -- mirrors `targets`' own bare-language
        // match (e.g. `de-AT` -> `de`, `fr-CA` -> `fr`).
        return validProductTags.contains(language) ? language : nil
    }

    /// Parses a BCP-47-ish identifier into raw language/script/region
    /// strings. iOS 16+ uses `Locale.Components(identifier:)` (the modern,
    /// non-deprecated API) directly -- no deprecation warning. iOS 15 (the
    /// Runner minimum deployment target, where the modern API does not
    /// exist) falls through to `legacyIdentifierComponents(_:)`, a
    /// dedicated helper marked `@available(iOS, deprecated: 16.0)` itself
    /// so calling the deprecated `Locale.components(fromIdentifier:)` from
    /// inside it produces no warning either -- Swift does not warn when a
    /// deprecated API is called from a caller that is itself marked
    /// deprecated at the same or an earlier version, and this helper is
    /// only ever reached via the `#available(iOS 16, *)` guard below, never
    /// on iOS 16+. This is not a raised deployment target -- both paths
    /// remain fully supported back to iOS 15.
    private static func identifierComponents(
        _ identifier: String
    ) -> (language: String, script: String?, region: String?) {
        if #available(iOS 16, *) {
            let components = Locale.Components(identifier: identifier)
            return (
                components.languageComponents.languageCode?.identifier ?? "",
                components.languageComponents.script?.identifier,
                components.languageComponents.region?.identifier
            )
        } else {
            // This branch is only ever compiled/reached on iOS < 16, so
            // calling the deliberately `@available(iOS, deprecated: 16.0)`
            // `legacyIdentifierComponents(_:)` from here produces no
            // warning -- the explicit `else` (not a bare trailing
            // statement after the `if`) is what lets the compiler narrow
            // this branch to the pre-iOS-16 availability context.
            return legacyIdentifierComponents(identifier)
        }
    }

    /// The pre-iOS-16 fallback path. Deliberately marked deprecated itself
    /// (see `identifierComponents(_:)`'s doc comment) so its own internal
    /// use of `Locale.components(fromIdentifier:)` produces no compiler
    /// warning, while remaining fully reachable and correct on iOS 15 --
    /// the Runner minimum deployment target this project must keep
    /// supporting.
    @available(iOS, deprecated: 16.0, message: "Only reached on iOS < 16, via identifierComponents(_:)'s #available guard.")
    private static func legacyIdentifierComponents(
        _ identifier: String
    ) -> (language: String, script: String?, region: String?) {
        let components = Locale.components(fromIdentifier: identifier)
        return (
            components[NSLocale.Key.languageCode.rawValue] ?? "",
            components[NSLocale.Key.scriptCode.rawValue],
            components[NSLocale.Key.countryCode.rawValue]
        )
    }
}
