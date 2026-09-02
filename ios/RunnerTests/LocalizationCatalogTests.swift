import XCTest

/// EAST. Phase 5D -- validates `EastShared/Localizable.xcstrings`, the
/// String Catalog shared by the Runner and EastWidgetExtension targets for
/// native App Intent / Shortcut / widget copy. Reads the catalog straight
/// from source (via `#filePath`) rather than through a compiled bundle, so
/// it exercises exactly what a translator/reviewer edits -- no WidgetKit or
/// AppIntents framework dependency required.
final class LocalizationCatalogTests: XCTestCase {
    /// The exact 15 product locales this phase supports -- see the Flutter
    /// runtime's own locale list in `lib/l10n`, which this must mirror.
    private static let expectedLocales: Set<String> = [
        "en", "tr", "ja", "de", "fr", "ko", "zh-Hant", "ar", "es",
        "pt-BR", "it", "th", "nl", "pl", "vi",
    ]

    /// Locales that must never be exposed as native product locales, even
    /// though close relatives of them are supported.
    private static let forbiddenLocales: Set<String> = [
        "zh-Hans", "zh-CN", "zh", "pt-PT", "pt",
    ]

    private static var catalogURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RunnerTests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("EastShared/Localizable.xcstrings")
    }

    private func loadStrings() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: Self.catalogURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["sourceLanguage"] as? String, "en")
        return try XCTUnwrap(json["strings"] as? [String: [String: Any]])
    }

    private func localizations(of entry: [String: Any]) throws -> [String: [String: Any]] {
        try XCTUnwrap(entry["localizations"] as? [String: [String: Any]])
    }

    private func value(_ localization: [String: Any]) throws -> String {
        let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }

    func testCatalogIsNotEmpty() throws {
        XCTAssertFalse(try loadStrings().isEmpty)
    }

    func testEveryKeyCoversExactlyTheFifteenProductLocales() throws {
        for (key, entry) in try loadStrings() {
            let locales = Set(try localizations(of: entry).keys)
            XCTAssertEqual(
                locales, Self.expectedLocales,
                "\"\(key)\" does not cover exactly the 15 product locales (found: \(locales.sorted()))"
            )
        }
    }

    func testNoForbiddenLocalesAppearAnywhere() throws {
        for (key, entry) in try loadStrings() {
            let locales = try localizations(of: entry)
            for forbidden in Self.forbiddenLocales {
                XCTAssertNil(locales[forbidden], "\"\(key)\" must not expose locale '\(forbidden)'")
            }
        }
    }

    func testEveryLocalizationIsMarkedTranslated() throws {
        for (key, entry) in try loadStrings() {
            for (locale, localization) in try localizations(of: entry) {
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
                XCTAssertEqual(
                    unit["state"] as? String, "translated",
                    "\"\(key)\"/\(locale) is not marked translated"
                )
            }
        }
    }

    func testEastBrandTokenNeverTranslatedOrDropped() throws {
        for (key, entry) in try loadStrings() where key.contains("EAST.") {
            for (locale, localization) in try localizations(of: entry) {
                let text = try value(localization)
                XCTAssertTrue(
                    text.contains("EAST."),
                    "\"\(key)\"/\(locale) dropped or translated the EAST. brand token: \(text)"
                )
            }
        }
    }

    func testShortcutPhrasesPreserveTheApplicationNamePlaceholder() throws {
        for key in ["Begin ${applicationName}", "Open ${applicationName}"] {
            let entry = try XCTUnwrap(try loadStrings()[key], "missing key \(key)")
            for (locale, localization) in try localizations(of: entry) {
                let text = try value(localization)
                XCTAssertTrue(
                    text.contains("${applicationName}"),
                    "\"\(key)\"/\(locale) dropped the app-name placeholder: \(text)"
                )
            }
        }
    }

    /// Mirrors lib/l10n/app_*.arb's already-reviewed "notificationBody" --
    /// the widget's pre-reveal silence copy must never independently drift
    /// from that wording.
    func testSilenceTextMatchesReviewedFlutterTranslations() throws {
        let expected: [String: String] = [
            "en": "Something waits in silence.",
            "tr": "Sessizlikte bir şey bekliyor.",
            "ja": "静けさの中で、何かが待っています。",
            "de": "Etwas wartet in der Stille.",
            "fr": "Quelque chose attend dans le silence.",
            "ko": "고요 속에서 무언가 기다립니다.",
            "zh-Hant": "有什麼在寂靜中等待。",
            "ar": "شيء ما ينتظر في الصمت.",
            "es": "Algo espera en el silencio.",
            "pt-BR": "Algo espera no silêncio.",
            "it": "Qualcosa attende nel silenzio.",
            "th": "มีบางสิ่งรออยู่ในความเงียบ.",
            "nl": "Iets wacht in de stilte.",
            "pl": "Coś czeka w ciszy.",
            "vi": "Có điều gì đó đang chờ trong tĩnh lặng.",
        ]

        let entry = try XCTUnwrap(try loadStrings()["Something waits in silence."])
        let locales = try localizations(of: entry)

        for (locale, expectedText) in expected {
            let localization = try XCTUnwrap(locales[locale], "missing locale \(locale)")
            XCTAssertEqual(try value(localization), expectedText, "silence text drifted for \(locale)")
        }
    }

    func testKeeperWidgetGalleryNameIsLocalizedForEveryProductLocale() throws {
        let expected: [String: String] = [
            "en": "EAST. Keeper Ritual",
            "tr": "EAST. Keeper Ritüeli",
            "ja": "EAST. Keeperの儀式",
            "de": "EAST. Keeper-Ritual",
            "fr": "Rituel Keeper d’EAST.",
            "ko": "EAST. Keeper 의식",
            "zh-Hant": "EAST. Keeper 儀式",
            "ar": "طقس Keeper في EAST.",
            "es": "Ritual Keeper de EAST.",
            "pt-BR": "Ritual Keeper do EAST.",
            "it": "Rituale Keeper di EAST.",
            "th": "พิธีกรรม Keeper ของ EAST.",
            "nl": "EAST. Keeper-ritueel",
            "pl": "Rytuał Keeper w EAST.",
            "vi": "Nghi thức Keeper của EAST.",
        ]

        let entry = try XCTUnwrap(try loadStrings()["EAST. Keeper Ritual"])
        let locales = try localizations(of: entry)
        XCTAssertEqual(Set(locales.keys), Self.expectedLocales)
        for (locale, expectedText) in expected {
            let localization = try XCTUnwrap(locales[locale], "missing locale \(locale)")
            XCTAssertEqual(try value(localization), expectedText)
        }
    }

    func testKeeperWidgetGalleryDescriptionMatchesItsThreeRitualPhases() throws {
        let strings = try loadStrings()
        let description = try localizations(of: XCTUnwrap(
            strings["Pause. Feel. Ask from your heart."]
        ))
        let pause = try localizations(of: XCTUnwrap(strings["Pause."]))
        let feel = try localizations(of: XCTUnwrap(strings["Feel."]))
        let heart = try localizations(of: XCTUnwrap(strings["Ask from your heart."]))

        for locale in Self.expectedLocales {
            let separator = ["ja", "zh-Hant"].contains(locale) ? "" : " "
            let expected = try [pause, feel, heart]
                .map { try value(XCTUnwrap($0[locale], "missing locale \(locale)")) }
                .joined(separator: separator)
            XCTAssertEqual(
                try value(XCTUnwrap(description[locale], "missing locale \(locale)")),
                expected,
                "Keeper widget gallery description drifted from its ritual phases for \(locale)"
            )
        }
    }
}
