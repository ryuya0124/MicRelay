// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay

final class SpectrumTests: XCTestCase {
    func testSineFrequencyAmplitudeAndSilence() {
        let fft = SpectrumFFT()
        let frequency = 48000.0 * 85 / 4096
        let sine = (0..<4096).map { Float(0.5 * sin(2 * Double.pi * frequency * Double($0) / 48000)) }
        let result = fft.spectrum(sine, sampleRate: 48000)
        XCTAssertEqual(result.dominantFrequency, frequency, accuracy: 0.001)
        XCTAssertEqual(result.db.max()!, -6.0206, accuracy: 0.1)
        XCTAssertTrue(fft.spectrum([Float](repeating: 0, count: 4096), sampleRate: 48000).db.allSatisfy { $0 == -120 })
    }

    func testEqualizerSettingsPersistenceAndInvalidFallback() {
        let name = "MicRelay.EQTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var value = EqualizerSettings()
        value.enabled = true
        value.bands[2].filter = .notch
        value.bands[2].frequency = 1234
        value.save(in: defaults)
        XCTAssertEqual(EqualizerSettings.load(in: defaults), value)
        value.bands[2].q = -1
        value.save(in: defaults)
        XCTAssertEqual(EqualizerSettings.load(in: defaults), EqualizerSettings())
    }
}
