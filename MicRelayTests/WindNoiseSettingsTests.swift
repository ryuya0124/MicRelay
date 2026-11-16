// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay

final class WindNoiseSettingsTests: XCTestCase {
    func testDefaultIsOffAndSettingsPersistIncludingWhenDisabled() throws {
        let name = "MicRelay.WindTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(WindNoiseSettings.load(in: defaults), .init(enabled: false, cutoff: 120))
        var value = WindNoiseSettings(enabled: true, cutoff: 340)
        value.save(in: defaults)
        XCTAssertEqual(WindNoiseSettings.load(in: defaults), value)
        value.enabled = false; value.save(in: defaults)
        XCTAssertEqual(WindNoiseSettings.load(in: defaults), value)
    }
    func testBackupPreservesWindAndLegacyBackupDefaultsToOff() throws {
        let wind = WindNoiseSettings(enabled: true, cutoff: 260)
        let backup = SettingsBackup(gain: 2.73888897895813, gainLimit: 4, equalizer: .init(), backgroundEnabled: true, selectedInput: "builtin", windNoise: wind)
        let restored = try SettingsBackup.decode(backup.encoded())
        XCTAssertEqual(restored.windNoise, wind)
        XCTAssertEqual(restored.gain, backup.gain); XCTAssertEqual(restored.gainLimit, backup.gainLimit)
        var json = try JSONSerialization.jsonObject(with: backup.encoded()) as! [String: Any]
        json.removeValue(forKey: "windNoise"); json.removeValue(forKey: "manualAudio"); json.removeValue(forKey: "tapGate"); json.removeValue(forKey: "screenRecording"); json["version"] = 1
        let legacy = try SettingsBackup.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.windNoise)
        XCTAssertFalse((legacy.windNoise ?? .init()).enabled)
    }
    func testInvalidCutoffCannotBeRestored() throws {
        for cutoff in [-1.0, 0, 59, 601, Double.nan, Double.infinity] {
            let invalid = WindNoiseSettings(enabled: true, cutoff: cutoff)
            XCTAssertFalse(invalid.isValid)
            let backup = SettingsBackup(gain: 0.5, gainLimit: 2, equalizer: .init(), backgroundEnabled: true, selectedInput: "builtin", windNoise: invalid)
            XCTAssertThrowsError(try backup.validated())
        }
    }
}
