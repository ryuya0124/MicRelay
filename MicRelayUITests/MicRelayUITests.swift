// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import XCTest
import UIKit

final class MicRelayUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }


    private var japaneseArguments: [String] { ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"] }
    private func japaneseApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = japaneseArguments
        return app
    }

    func testEnglishLocalizationAcrossScreens() {
        checkLocalizedScreens(language: "en", locale: "en_US", start: "Start monitoring", initial: "Connect headphones or an HDMI device",
            equalizer: "Equalizer", bypass: "EQ OFF · Filters bypassed", gain: "Gain limit", save: "Save",
            invalid: "Enter a valid number greater than zero.", licenses: "Licenses", backup: "Backup and restore", export: "Export settings")
    }

    func testJapaneseLocalizationAcrossScreens() {
        checkLocalizedScreens(language: "ja", locale: "ja_JP", start: "モニターを開始", initial: "イヤホンまたはHDMI機器を接続してください",
            equalizer: "イコライザー", bypass: "EQ OFF · フィルターをバイパス", gain: "ゲイン上限", save: "保存",
            invalid: "0より大きい有効な数値を入力してください。", licenses: "ライセンス", backup: "バックアップと復元", export: "設定を書き出す")
    }

    private func checkLocalizedScreens(language: String, locale: String, start: String, initial: String,
        equalizer: String, bypass: String, gain: String, save: String, invalid: String, licenses: String, backup: String, export: String) {
        let app = XCUIApplication()
        let arguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["monitorToggle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["monitorToggle"].label, start)
        XCTAssertEqual(app.staticTexts["monitorStatus"].label, initial)
        screenshot("localization-\(language)-monitor")
        app.terminate()

        app.launchArguments = arguments + ["--show-equalizer"]
        app.launch()
        XCTAssertTrue(app.navigationBars[equalizer].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[bypass].exists)
        screenshot("localization-\(language)-equalizer")
        app.terminate()

        app.launchArguments = arguments + ["--show-gain-settings"]
        app.launch()
        XCTAssertTrue(app.navigationBars[gain].waitForExistence(timeout: 10))
        let input = app.textFields["gainLimitInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["saveGainLimit"].label, save)
        #if targetEnvironment(simulator)
        input.tap()
        let old = input.value as? String ?? ""
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "0")
        app.buttons["saveGainLimit"].tap()
        XCTAssertTrue(app.staticTexts[invalid].waitForExistence(timeout: 5))
        screenshot("localization-\(language)-gain-error")
        #else
        screenshot("localization-\(language)-gain")
        #endif
        app.terminate()

        app.launchArguments = arguments + ["--show-licenses"]
        app.launch()
        XCTAssertTrue(app.navigationBars[licenses].waitForExistence(timeout: 10))
        screenshot("localization-\(language)-licenses")
        app.terminate()

        app.launchArguments = arguments + ["--show-backup"]
        app.launch()
        XCTAssertTrue(app.navigationBars[backup].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["exportSettings"].label, export)
        screenshot("localization-\(language)-backup")
        app.terminate()
    }

    func testLaunchAndSafeDefault() {
        let app = japaneseApp()
        app.launch()
        XCTAssertTrue(app.staticTexts["MicRelay"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["monitorToggle"].exists)
        // No headphones are attached in this validation environment.
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertFalse(app.buttons["monitorToggle"].isEnabled)
        } else {
            XCTAssertFalse(app.switches["speakerToggle"].value as? String == "1")
        }
        screenshot("01-default-headphone-guard")
    }

    func testLiveMicrophoneAndBackground() throws {
        let app = japaneseApp()
        app.launchArguments = japaneseArguments + [UIDevice.current.userInterfaceIdiom == .pad ? "--validate-headphones" : "--validate-speaker", "--expand-diagnostics", "--automatic-mode"]
        addUIInterruptionMonitor(withDescription: "Microphone permission") { alert in
            for title in ["許可", "Allow", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap(); return true
            }
            return false
        }
        app.launch()
        if XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists { app.tap() }
        let status = app.staticTexts["monitorStatus"]
        expectation(for: NSPredicate(format: "label == %@", "モニター中"), evaluatedWith: status)
        waitForExpectations(timeout: 15)
        Thread.sleep(forTimeInterval: 2)
        let waveform = app.staticTexts["liveDiagnostics"]
        XCTAssertTrue(waveform.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(counter("処理フレーム", in: waveform), 0)
        XCTAssertEqual(counter("エラー", in: waveform), 0)
        screenshot("02-live-input-waveform")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 12)
        app.activate()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertGreaterThan(counter("背景フレーム", in: waveform), counter("サンプルレート", in: waveform) * 8)
        XCTAssertEqual(counter("エラー", in: waveform), 0)
        XCTAssertGreaterThan(counter("入力ピーク", in: waveform), -96)
        XCTAssertGreaterThan(counter("出力ピーク", in: waveform), -96)
        screenshot("03-after-background")
        let report = XCTAttachment(string: waveform.label)
        report.name = "real-device-audio-counters"
        report.lifetime = .keepAlways
        add(report)
        app.terminate()
    }

    private func counter(_ name: String, in element: XCUIElement) -> Int64 {
        let values = element.label.components(separatedBy: "、")
        let text = values.first { $0.hasPrefix(name) } ?? ""
        let number = text.dropFirst(name.count).filter { "-0123456789".contains($0) }
        return Int64(number) ?? Int64.min
    }

    func testDedicatedLicenseScreenAndDependencyText() {
        let app = japaneseApp()
        app.launchArguments = japaneseArguments + ["--show-licenses"]
        app.launch()
        XCTAssertTrue(app.navigationBars["ライセンス"].waitForExistence(timeout: 5))
        let dependency = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "CFPropertyList ")).firstMatch
        XCTAssertTrue(dependency.waitForExistence(timeout: 5))
        screenshot("04-dedicated-license-screen")
        app.terminate()
        app.launchArguments = japaneseArguments + ["--show-licenses", "--show-dependency-license=CFPropertyList"]
        app.launch()
        XCTAssertTrue(app.navigationBars["CFPropertyList"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Copyright")).firstMatch.exists)
        screenshot("05-dependency-license-full-text")
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRealInputSpectrum() {
        let app = japaneseApp()
        app.launchArguments = japaneseArguments + [UIDevice.current.userInterfaceIdiom == .pad ? "--validate-headphones" : "--validate-speaker", "--show-equalizer", "--automatic-mode"]
        app.launch()
        let plot = app.otherElements["frequencySpectrum"]
        XCTAssertTrue(plot.waitForExistence(timeout: 15))
        expectation(for: NSPredicate { _, _ in
            let value = plot.value as? String ?? ""
            let count = value.components(separatedBy: "、").first?.filter { "0123456789".contains($0) } ?? ""
            return (Int(count) ?? 0) > 10
        }, evaluatedWith: plot)
        waitForExpectations(timeout: 18)
        let value = plot.value as? String ?? ""
        let count = value.components(separatedBy: "、").first?.filter { "0123456789".contains($0) } ?? ""
        XCTAssertGreaterThan(Int(count) ?? 0, 10)
        screenshot("06-real-microphone-frequency-spectrum")
        app.terminate()
        app.launchArguments.append("--validate-eq")
        app.launch()
        XCTAssertTrue(plot.waitForExistence(timeout: 15))
        expectation(for: NSPredicate { _, _ in
            let value = plot.value as? String ?? ""
            let text = value.components(separatedBy: "、").first { $0.hasPrefix("差分") } ?? ""
            return (Int(text.filter { "0123456789".contains($0) }) ?? 0) > 3
        }, evaluatedWith: plot)
        waitForExpectations(timeout: 18)
        let filteredValue = plot.value as? String ?? ""
        let differenceText = filteredValue.components(separatedBy: "、").first { $0.hasPrefix("差分") } ?? ""
        XCTAssertGreaterThan(Int(differenceText.filter { "0123456789".contains($0) }) ?? 0, 3)
        screenshot("07-real-microphone-equalizer-on")
        app.terminate()
    }


    func testEnglishStoreScreenshots() {
        let app = XCUIApplication()
        for (name, extra) in [("store-01-monitor", [String]()), ("store-02-equalizer", ["--show-equalizer"]), ("store-03-gain", ["--show-gain-settings"])] {
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--store-capture"] + extra
            app.launch()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
            screenshot(name)
            app.terminate()
        }
    }

    func testStoreScreenshots() {
        let app = japaneseApp()
        for (name, extra) in [("store-01-monitor", [String]()), ("store-02-equalizer", ["--show-equalizer", "--validate-eq"]), ("store-03-gain", ["--show-gain-settings"])] {
            app.launchArguments = japaneseArguments + [UIDevice.current.userInterfaceIdiom == .pad ? "--validate-headphones" : "--validate-speaker", "--store-capture"] + extra
            app.launch()
            Thread.sleep(forTimeInterval: 10)
            screenshot(name)
            app.terminate()
        }
    }
}
