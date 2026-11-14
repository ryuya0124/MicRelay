// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay

final class LocalizationTests: XCTestCase {
    private func localizedBundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    func testCompiledCatalogsResolveJapaneseAndEnglish() throws {
        let japanese = try localizedBundle("ja"), english = try localizedBundle("en")
        XCTAssertEqual(String(localized: "monitor.action.start", bundle: japanese), "モニターを開始")
        XCTAssertEqual(String(localized: "monitor.action.start", bundle: english), "Start monitoring")
        XCTAssertEqual(String(localized: "audio.mode.automatic", bundle: english), "Automatic")
        XCTAssertEqual(String(localized: "eq.filter.notch", bundle: english), "Notch (band stop)")
        XCTAssertEqual(String(localized: "eq.enable_band", defaultValue: "バンド \(3) を使う", bundle: english), "Use band 3")
        let prompt = english.localizedString(forKey: "NSMicrophoneUsageDescription", value: nil, table: "InfoPlist")
        XCTAssertTrue(prompt.contains("microphone audio"))
        XCTAssertFalse(prompt.contains("NSMicrophoneUsageDescription"))
    }

    func testGainLimitUsesRegionalDecimalSeparatorWithoutChangingItsValue() {
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "ja_JP"), Locale(identifier: "de_DE"), Locale(identifier: "fr_FR")] {
            let text = MonitorPreferences.gainLimitInput(2.505, locale: locale)
            XCTAssertEqual(MonitorPreferences.parseGainLimit(text, locale: locale) ?? 0, 250.5, accuracy: 0.000001)
            for percent in [1e9, 1e100] {
                let large = MonitorPreferences.gainLimitInput(percent / 100, locale: locale)
                XCTAssertEqual((MonitorPreferences.parseGainLimit(large, locale: locale) ?? 0) / percent, 1, accuracy: 0.000001)
            }
        }
        XCTAssertEqual(MonitorPreferences.parseGainLimit("250,5", locale: Locale(identifier: "de_DE")), 250.5)
        XCTAssertNil(MonitorPreferences.parseGainLimit("0"))
        XCTAssertNil(MonitorPreferences.parseGainLimit("-25"))
        XCTAssertNil(MonitorPreferences.parseGainLimit("invalid"))
        XCTAssertNil(MonitorPreferences.parseGainLimit("250abc"))
    }
}
