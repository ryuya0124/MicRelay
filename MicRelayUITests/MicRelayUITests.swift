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

    func testJapaneseManualSettingsRejectMismatchAndRestore() throws {
        try checkManualRejection(language: "ja", locale: "ja_JP", title: "手動I/O設定", manual: "完全手動",
            automatic: "自動", error: "設定を適用できませんでした", mismatch: "要求値と実際の値が一致しません。", rollback: "元の設定に戻しました。")
    }

    func testEnglishManualSettingsRejectMismatchAndRestore() throws {
        try checkManualRejection(language: "en", locale: "en_US", title: "Manual I/O settings", manual: "Fully manual",
            automatic: "Automatic", error: "Could not apply settings", mismatch: "The actual settings differ from your request.", rollback: "Restored the previous settings.")
    }

    func testManualMenuPresentation() {
        let app = japaneseApp()
        app.launchArguments = japaneseArguments + ["--show-manual-io"]
        app.launch()
        XCTAssertTrue(app.navigationBars["手動I/O設定"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["manualFramesPicker"].exists)
        XCTAssertTrue(app.buttons["manualRatePicker"].exists)
        XCTAssertTrue(app.buttons["manualModePicker"].exists)
        XCTAssertFalse(app.textFields.firstMatch.exists)
        screenshot("manual-device-dropdowns")
        app.terminate()
    }

    private func checkManualRejection(language: String, locale: String, title: String, manual: String,
        automatic: String, error: String, mismatch: String, rollback: String) throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This test changes simulator audio preferences; physical-device validation is separate.")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale, "--allow-speaker-for-validation"]
        app.launch()
        let picker = app.buttons["audioModePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        if !picker.label.contains(automatic) && !(picker.value as? String ?? "").contains(automatic) {
            picker.tap(); app.buttons[automatic].tap()
        }
        let gainSlider = app.sliders["gainSlider"]
        let gain = gainSlider.exists ? gainSlider.value as? String : nil
        picker.tap(); app.buttons[manual].tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
        let frames = app.buttons["manualFramesPicker"], rate = app.buttons["manualRatePicker"]
        XCTAssertTrue(frames.waitForExistence(timeout: 5))
        let oldFrames = frames.label + (frames.value as? String ?? ""), oldRate = rate.label + (rate.value as? String ?? "")
        XCTAssertFalse(app.textFields.firstMatch.exists)
        frames.tap()
        XCTAssertTrue(app.buttons["manualFramesPreset12"].waitForExistence(timeout: 5))
        app.buttons["manualFramesPreset12"].tap()
        rate.tap()
        XCTAssertTrue(app.buttons["manualRatePreset96000"].waitForExistence(timeout: 5))
        app.buttons["manualRatePreset96000"].tap()
        let apply = app.buttons["applyManualAudio"]
        for _ in 0..<8 where !apply.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35)))
        }
        apply.tap()
        let alert = app.alerts[error]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", mismatch, rollback)).firstMatch.exists)
        screenshot("manual-\(language)-mismatch-rollback")
        alert.buttons["OK"].tap()
        for _ in 0..<8 where !frames.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8)))
        }
        XCTAssertEqual(frames.label + (frames.value as? String ?? ""), oldFrames)
        XCTAssertEqual(rate.label + (rate.value as? String ?? ""), oldRate)
        screenshot("manual-\(language)-restored-fields")
        app.buttons["BackButton"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains(automatic) || (picker.value as? String ?? "").contains(automatic))
        if let gain { XCTAssertEqual(gainSlider.value as? String, gain) }
        app.terminate()
        #endif
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

    func testJapaneseWindControls() { checkWindControls(language: "ja", locale: "ja_JP", title: "風切り音低減") }
    func testJapaneseTapGateControls() { checkTapGateControls(language: "ja", locale: "ja_JP", title: "タップ音ゲート") }
    func testEnglishTapGateControls() { checkTapGateControls(language: "en", locale: "en_US", title: "Tap gate") }
    private func checkTapGateControls(language: String, locale: String, title: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale, "--show-equalizer", "--validate-tap-gate"]
        app.launch()
        let toggle = app.switches["tapGateToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let bandBeforeScroll = app.buttons["equalizerBand0"].label
        revealEqualizerControl(toggle, app: app)
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(app.buttons["equalizerBand0"].label, bandBeforeScroll)
        XCTAssertTrue(toggle.label.contains(title))
        XCTAssertEqual(toggle.value as? String,"0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String,"1")
        let source = app.buttons["tapGateDetectionSource"]
        revealEqualizerControl(source, app: app)
        let beforeFilter = language == "ja" ? "フィルター前の入力" : "Input before filters"
        source.tap()
        XCTAssertTrue(app.buttons[beforeFilter].waitForExistence(timeout: 5))
        app.buttons[beforeFilter].tap()
        XCTAssertTrue(source.label.contains(beforeFilter) || (source.value as? String ?? "").contains(beforeFilter))
        let duration = app.sliders["tapGateDurationSlider"]
        revealEqualizerControl(duration, app: app)
        duration.adjust(toNormalizedSliderPosition: 0.6)
        let field = app.textFields["tapGateDuration"]
        let time = field.value as? String
        let rise = app.sliders["tapGateRiseSlider"]
        revealEqualizerControl(rise, app: app)
        rise.adjust(toNormalizedSliderPosition: 0.7)
        let difference = app.staticTexts["tapGateRiseValue"].label
        revealEqualizerControl(toggle, app: app)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String,"0")
        XCTAssertFalse(duration.exists)
        revealEqualizerControl(toggle, app: app)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String,"1")
        revealEqualizerControl(rise, app: app)
        XCTAssertEqual(field.value as? String,time)
        XCTAssertEqual(app.staticTexts["tapGateRiseValue"].label,difference)
        XCTAssertTrue(source.label.contains(beforeFilter) || (source.value as? String ?? "").contains(beforeFilter))
        screenshot("tap-gate-\(language)-controls")
        app.terminate()
    }
    private func revealEqualizerControl(_ element: XCUIElement, app: XCUIApplication) {
        // isHittable can remain true after a fast flick overshoots a row on the short Duo screen.
        for _ in 0..<24 {
            let bounds = app.frame, target = element.frame
            if target.minY >= bounds.minY + 100 && target.maxY <= bounds.maxY - 40 { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            let end = start.withOffset(CGVector(dx: 0, dy: target.midY > bounds.midY ? -80 : 80))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        screenshot("unrevealed-equalizer-control")
        XCTFail("Could not reveal the equalizer control: \(element.frame), viewport: \(app.frame)")
    }
    func testSpectrumTapHorizontalDragAndVerticalScroll() {
        let app = japaneseApp()
        app.launchArguments += ["--show-equalizer", "--validate-tap-gate"]
        app.launch()
        let plot = app.otherElements["frequencySpectrum"], band = app.buttons["equalizerBand0"]
        XCTAssertTrue(plot.waitForExistence(timeout: 10))
        revealEqualizerControl(plot, app: app)
        let initial = band.label
        plot.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        let afterTap = band.label
        XCTAssertNotEqual(afterTap,initial)
        plot.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: plot.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.15)
        let afterDrag = band.label, beforeY = plot.frame.minY
        XCTAssertNotEqual(afterDrag,afterTap)
        plot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05,
            thenDragTo: plot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)), withVelocity: .slow, thenHoldForDuration: 0.15)
        XCTAssertEqual(band.label,afterDrag)
        // The large iPad can fit the whole collapsed page; the short phone viewport must scroll.
        if UIDevice.current.userInterfaceIdiom != .pad { XCTAssertLessThan(plot.frame.minY,beforeY) }
        screenshot("spectrum-vertical-scroll-keeps-frequency")
        app.terminate()
    }
    func testEnglishWindControls() { checkWindControls(language: "en", locale: "en_US", title: "Wind noise reduction") }
    private func checkWindControls(language: String, locale: String, title: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale, "--validate-wind"]
        app.launch()
        let toggle = app.switches["windNoiseToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.label.contains(title))
        XCTAssertEqual(toggle.value as? String,"1")
        let slider = app.sliders["windNoiseSlider"]
        for _ in 0..<5 where !slider.isHittable { app.swipeUp() }
        slider.adjust(toNormalizedSliderPosition: 0.8)
        let before = app.staticTexts["windNoiseCutoff"].label
        XCTAssertTrue(before.contains("Hz"))
        for _ in 0..<5 where !toggle.isHittable { app.swipeDown() }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String,"0")
        XCTAssertFalse(slider.exists)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String,"1")
        XCTAssertEqual(app.staticTexts["windNoiseCutoff"].label,before)
        screenshot("wind-\(language)-enabled")
        app.terminate()
    }

    func testJapaneseRangeFilters() {
        checkRangeFilters(language: "ja", locale: "ja_JP", stop: "バンドストップ（範囲をカット）", pass: "バンドパス（範囲だけ通す）")
    }

    func testEnglishRangeFilters() {
        checkRangeFilters(language: "en", locale: "en_US", stop: "Band stop (cut a range)", pass: "Band pass (pass a range)")
    }

    private func checkRangeFilters(language: String, locale: String, stop: String, pass: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale, "--show-equalizer", "--validate-range-eq"]
        app.launch()
        let lower = app.textFields["equalizerLowerFrequency"], upper = app.textFields["equalizerUpperFrequency"]
        XCTAssertTrue(lower.waitForExistence(timeout: 10))
        let picker = app.buttons["equalizerFilter"]
        for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.label.contains(stop) || (picker.value as? String ?? "").contains(stop))
        screenshot("range-\(language)-stop")
        let lowerSlider = app.sliders["equalizerLowerSlider"], upperSlider = app.sliders["equalizerUpperSlider"]
        for _ in 0..<5 where !upperSlider.isHittable { app.swipeUp() }
        lowerSlider.adjust(toNormalizedSliderPosition: 0.4)
        upperSlider.adjust(toNormalizedSliderPosition: 0.8)
        let beforeLower = lower.value as? String, beforeUpper = upper.value as? String
        XCTAssertNotEqual(beforeLower,beforeUpper)
        for _ in 0..<5 where !picker.isHittable { app.swipeDown() }
        picker.tap()
        XCTAssertTrue(app.buttons[pass].waitForExistence(timeout: 5))
        app.buttons[pass].tap()
        XCTAssertTrue(picker.label.contains(pass) || (picker.value as? String ?? "").contains(pass))
        XCTAssertEqual(lower.value as? String,beforeLower)
        XCTAssertEqual(upper.value as? String,beforeUpper)
        XCTAssertFalse(app.sliders["Q"].exists)
        screenshot("range-\(language)-pass")
        app.terminate()
    }

    func testRealInputRangeSpectrum() {
        let app = japaneseApp()
        app.launchArguments = japaneseArguments + [UIDevice.current.userInterfaceIdiom == .pad ? "--validate-headphones" : "--validate-speaker",
            "--show-equalizer", "--validate-range-eq", "--automatic-mode", "--diagnostic-seconds=30"]
        app.launch()
        let plot = app.otherElements["frequencySpectrum"]
        XCTAssertTrue(plot.waitForExistence(timeout: 15))
        expectation(for: NSPredicate { _, _ in
            let value = plot.value as? String ?? ""
            let components = value.components(separatedBy: "、")
            let frames = Int(components.first?.filter { "0123456789".contains($0) } ?? "") ?? 0
            let difference = Int((components.first { $0.hasPrefix("差分") } ?? "").filter { "0123456789".contains($0) }) ?? 0
            return frames > 10 && difference > 3
        }, evaluatedWith: plot)
        waitForExpectations(timeout: 18)
        screenshot("range-real-input-spectrum")
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


    func testEnglishStoreScreenshots() { captureStoreScreenshots(language: "en", locale: "en_US") }
    func testStoreScreenshots() { captureStoreScreenshots(language: "ja", locale: "ja_JP") }

    private func captureStoreScreenshots(language: String, locale: String) {
        let device = XCUIDevice.shared
        let previousOrientation = device.orientation
        defer { device.orientation = previousOrientation }
        device.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        for (name, extra) in [("store-01-monitor", [String]()), ("store-02-equalizer", ["--show-equalizer"]), ("store-03-gain", ["--show-gain-settings"])] {
            // Capture the real, stopped app in a consistent appearance; never synthesize audio values.
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                "-AppleInterfaceStyle", "Dark", "--store-capture"] + extra
            app.launch()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
            let capture = XCUIScreen.main.screenshot()
            let image = capture.image
            // UIImage drawing applies imageOrientation before PNG encoding strips that metadata.
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale; format.opaque = true
            let normalized = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
            let attachment = XCTAttachment(data: normalized.pngData()!, uniformTypeIdentifier: "public.png")
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            let metadata = XCTAttachment(string: "orientation=\(image.imageOrientation.rawValue), size=\(image.size), scale=\(image.scale), deviceOrientation=\(device.orientation.rawValue)")
            metadata.name = "capture-info-\(name)"; metadata.lifetime = .keepAlways; add(metadata)
            app.terminate()
        }
    }
}
