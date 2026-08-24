import XCTest

@testable import Runner

/// EAST. 1.2 Slice 2B -- `EastWidgetLocaleResolver` is Foundation-only and
/// deterministic (no App Group, no `UserDefaults`, no real device
/// preferred-language list is ever read here -- every `preferredLanguages`
/// input is a literal array this suite controls), so every test below is a
/// pure function call.
final class EastWidgetLocaleResolverTests: XCTestCase {
    // MARK: - 1/2: explicit override allowlist

    // 1. All 15 exact explicit overrides are accepted.
    func testAllFifteenExplicitOverridesAreAccepted() {
        let canonicalTags = [
            "en", "tr", "ja", "de", "fr", "ko", "zh-Hant", "ar", "es",
            "pt-BR", "it", "th", "nl", "pl", "vi",
        ]
        for tag in canonicalTags {
            XCTAssertEqual(
                EastWidgetLocaleResolver.validatedOverrideTag(tag), tag,
                "tag \(tag) must be accepted exactly"
            )
        }
    }

    // 2. Bare `pt`, bare `zh`, wrong-case, malformed, and unknown explicit
    // overrides are rejected.
    func testInvalidExplicitOverridesAreRejected() {
        let invalidTags = ["pt", "zh", "PT-BR", "TR", "zh-hant", "fr-FR", "xx", ""]
        for tag in invalidTags {
            XCTAssertNil(
                EastWidgetLocaleResolver.validatedOverrideTag(tag),
                "invalid tag '\(tag)' must be rejected"
            )
        }
        XCTAssertNil(EastWidgetLocaleResolver.validatedOverrideTag(nil))
    }

    // MARK: - 3/4/5: resolution precedence and empty/unsupported fallback

    // 3. A valid explicit override wins regardless of system preference.
    func testValidExplicitOverrideWinsRegardlessOfSystemPreference() {
        let resolved = EastWidgetLocaleResolver.resolvedProductTag(
            localeOverrideTag: "ja",
            preferredLanguages: ["de-DE", "fr-FR"]
        )
        XCTAssertEqual(resolved, "ja")
    }

    // 4. Empty preferred-language list -> English.
    func testEmptyPreferredLanguageListResolvesToEnglish() {
        let resolved = EastWidgetLocaleResolver.resolvedProductTag(
            localeOverrideTag: nil,
            preferredLanguages: []
        )
        XCTAssertEqual(resolved, "en")
    }

    // 5. Unsupported preferred language -> English.
    func testUnsupportedPreferredLanguageResolvesToEnglish() {
        let resolved = EastWidgetLocaleResolver.resolvedProductTag(
            localeOverrideTag: nil,
            preferredLanguages: ["ru-RU"]
        )
        XCTAssertEqual(resolved, "en")
    }

    // MARK: - 6/7: ordinary language/region resolution

    // 6. `en-US` -> en.
    func testEnUsResolvesToEn() {
        let resolved = EastWidgetLocaleResolver.resolvedProductTag(
            localeOverrideTag: nil,
            preferredLanguages: ["en-US"]
        )
        XCTAssertEqual(resolved, "en")
    }

    // 7. Regional variants of tr/de/fr/ko/ar/es/it/th/nl/pl/vi resolve to
    // their base product tag.
    func testRegionalVariantsResolveToTheirBaseProductTag() {
        let cases: [(identifier: String, expected: String)] = [
            ("tr-TR", "tr"),
            ("de-AT", "de"),
            ("fr-CA", "fr"),
            ("ko-KR", "ko"),
            ("ar-EG", "ar"),
            ("es-MX", "es"),
            ("it-CH", "it"),
            ("th-TH", "th"),
            ("nl-BE", "nl"),
            ("pl-PL", "pl"),
            ("vi-VN", "vi"),
        ]
        for testCase in cases {
            let resolved = EastWidgetLocaleResolver.resolvedProductTag(
                localeOverrideTag: nil,
                preferredLanguages: [testCase.identifier]
            )
            XCTAssertEqual(
                resolved, testCase.expected,
                "\(testCase.identifier) must resolve to \(testCase.expected)"
            )
        }
    }

    // MARK: - 8/9/10: Chinese script/region rules

    // 8. `zh-Hant` -> zh-Hant.
    func testZhHantResolvesToZhHant() {
        let resolved = EastWidgetLocaleResolver.resolvedProductTag(
            localeOverrideTag: nil,
            preferredLanguages: ["zh-Hant"]
        )
        XCTAssertEqual(resolved, "zh-Hant")
    }

    // 9. `zh-TW`, `zh-HK`, `zh-MO` -> zh-Hant.
    func testTraditionalChineseRegionsResolveToZhHant() {
        for identifier in ["zh-TW", "zh-HK", "zh-MO"] {
            let resolved = EastWidgetLocaleResolver.resolvedProductTag(
                localeOverrideTag: nil,
                preferredLanguages: [identifier]
            )
            XCTAssertEqual(resolved, "zh-Hant", "\(identifier) must resolve to zh-Hant")
        }
    }

    // 10. `zh-Hans`, `zh-CN`, and generic `zh` -> English.
    func testSimplifiedOrGenericChineseResolvesToEnglish() {
        for identifier in ["zh-Hans", "zh-CN", "zh"] {
            let resolved = EastWidgetLocaleResolver.resolvedProductTag(
                localeOverrideTag: nil,
                preferredLanguages: [identifier]
            )
            XCTAssertEqual(resolved, "en", "\(identifier) must resolve to English")
        }
    }

    // MARK: - 11/12: Portuguese region rules

    // 11. `pt-BR` -> pt-BR.
    func testPtBrResolvesToPtBr() {
        let resolved = EastWidgetLocaleResolver.resolvedProductTag(
            localeOverrideTag: nil,
            preferredLanguages: ["pt-BR"]
        )
        XCTAssertEqual(resolved, "pt-BR")
    }

    // 12. `pt-PT` and generic `pt` -> English.
    func testPortugalOrGenericPortugueseResolvesToEnglish() {
        for identifier in ["pt-PT", "pt"] {
            let resolved = EastWidgetLocaleResolver.resolvedProductTag(
                localeOverrideTag: nil,
                preferredLanguages: [identifier]
            )
            XCTAssertEqual(resolved, "en", "\(identifier) must resolve to English")
        }
    }

    // MARK: - 13: RTL identification

    // 13. Arabic is identifiable as the sole RTL product locale.
    func testArabicIsTheSoleRtlProductLocale() {
        XCTAssertTrue(EastWidgetLocaleResolver.isRtl(productTag: "ar"))

        let nonRtlTags = EastWidgetLocaleResolver.validProductTags.subtracting(["ar"])
        for tag in nonRtlTags {
            XCTAssertFalse(EastWidgetLocaleResolver.isRtl(productTag: tag), "\(tag) must not be RTL")
        }
    }

    // MARK: - 14: Locale construction preserves canonical components

    // 14. Locale creation preserves canonical `zh-Hant` and `pt-BR`
    // components. Inspected via `components(of:)` below rather than the
    // deprecated `Locale.languageCode`/`scriptCode`/`regionCode` instance
    // properties directly.
    func testLocaleCreationPreservesCanonicalComponents() {
        let zhHantLocale = EastWidgetLocaleResolver.locale(
            localeOverrideTag: "zh-Hant",
            preferredLanguages: []
        )
        let zhComponents = components(of: zhHantLocale)
        XCTAssertEqual(zhComponents.language, "zh")
        XCTAssertEqual(zhComponents.script, "Hant")

        let ptBrLocale = EastWidgetLocaleResolver.locale(
            localeOverrideTag: "pt-BR",
            preferredLanguages: []
        )
        let ptComponents = components(of: ptBrLocale)
        XCTAssertEqual(ptComponents.language, "pt")
        XCTAssertEqual(ptComponents.region, "BR")
    }

    /// Test-only inspection helper, mirroring
    /// `EastWidgetLocaleResolver.identifierComponents(_:)`'s own dual-path
    /// shape exactly: the modern, non-deprecated `Locale.Components(locale:)`
    /// on iOS 16+, and a dedicated `@available(iOS, deprecated: 16.0)`
    /// helper (so its own internal use of the deprecated
    /// `Locale.languageCode`/`scriptCode`/`regionCode` produces no warning)
    /// reachable only on iOS 15, the Runner minimum deployment target.
    private func components(of locale: Locale) -> (language: String?, script: String?, region: String?) {
        if #available(iOS 16, *) {
            let parsed = Locale.Components(locale: locale)
            return (
                parsed.languageComponents.languageCode?.identifier,
                parsed.languageComponents.script?.identifier,
                parsed.languageComponents.region?.identifier
            )
        } else {
            // The explicit `else` (not a bare trailing statement after the
            // `if`) is what lets the compiler narrow this branch to the
            // pre-iOS-16 availability context, so calling the deliberately
            // `@available(iOS, deprecated: 16.0)` `legacyComponents(of:)`
            // from here produces no warning.
            return legacyComponents(of: locale)
        }
    }

    @available(iOS, deprecated: 16.0, message: "Only reached on iOS < 16, via components(of:)'s #available guard.")
    private func legacyComponents(of locale: Locale) -> (language: String?, script: String?, region: String?) {
        (locale.languageCode, locale.scriptCode, locale.regionCode)
    }

    // MARK: - 15: store delegation returns identical canonical results

    // 15. Store validation still returns the same canonical results after
    // delegation to this resolver.
    func testStoreValidationMatchesResolverAfterDelegation() {
        let sampleTags = [
            "en", "zh-Hant", "pt-BR", "ar", "pt", "zh", "xx", "", "PT-BR",
        ]
        for tag in sampleTags {
            let fromResolver = EastWidgetLocaleResolver.validatedOverrideTag(tag)
            let fromStore = EastWidgetSnapshotStore.validatedPresentation(
                appearanceModeRaw: nil,
                localeOverrideTagRaw: tag
            ).localeOverrideTag
            XCTAssertEqual(
                fromResolver, fromStore,
                "store validation for '\(tag)' must exactly match the resolver's own result"
            )
        }
    }
}
