// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay

final class TapGateSettingsTests: XCTestCase {
    func testDefaultIsOffAndDisabledSettingsPersistWithoutChangingGain() throws {
        let name = "MicRelay.TapTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(TapGateSettings.load(in: defaults).enabled)
        MonitorPreferences.saveGainLimit(4, in: defaults); MonitorPreferences.saveGain(2.75, in: defaults)
        var value = TapGateSettings(enabled: true, duration: 0.007, minimumDB: -38, riseDB: 18, detectionSource: .beforeFilters)
        value.save(in: defaults)
        XCTAssertEqual(TapGateSettings.load(in: defaults), value)
        value.enabled = false; value.save(in: defaults)
        XCTAssertEqual(TapGateSettings.load(in: defaults), value)
        XCTAssertEqual(MonitorPreferences.gain(in: defaults), 2.75)
        XCTAssertEqual(MonitorPreferences.gainLimit(in: defaults), 4)
    }
    func testBackupV4RoundTripAndAllLegacyVersionsDefaultToOff() throws {
        let value = TapGateSettings(enabled: true, duration: 0.003, minimumDB: -45, riseDB: 12, detectionSource: .beforeFilters)
        let backup = SettingsBackup(gain: 2.75, gainLimit: 4, equalizer: .init(), backgroundEnabled: true, selectedInput: "builtin", tapGate: value)
        let decoded = try SettingsBackup.decode(backup.encoded())
        XCTAssertEqual(decoded.version,5); XCTAssertEqual(decoded.tapGate,value)
        for version in 1...3 {
            var json = try JSONSerialization.jsonObject(with: backup.encoded()) as! [String: Any]
            json["version"] = version; json.removeValue(forKey: "tapGate"); json.removeValue(forKey: "screenRecording")
            if version < 3 { json.removeValue(forKey: "manualAudio") }
            if version < 2 { json.removeValue(forKey: "windNoise") }
            let old = try SettingsBackup.decode(JSONSerialization.data(withJSONObject: json))
            XCTAssertNil(old.tapGate); XCTAssertFalse((old.tapGate ?? .init()).enabled)
            XCTAssertEqual(old.gain,2.75); XCTAssertEqual(old.gainLimit,4)
        }
    }
    func testInvalidValuesCannotBeSavedOrRestored() throws {
        for value in [TapGateSettings(duration: 0), .init(duration: .nan), .init(duration: 1.1),
                      .init(minimumDB: .infinity), .init(minimumDB: -91), .init(riseDB: 2), .init(riseDB: 31)] {
            XCTAssertFalse(value.isValid)
            XCTAssertThrowsError(try SettingsBackup(gain: 1, gainLimit: 4, equalizer: .init(), backgroundEnabled: true, selectedInput: "builtin", tapGate: value).validated())
        }
    }
    func testOldGateSettingsDefaultToFilteredDetectionAndUnknownSourceIsRejected() throws {
        let data = try JSONEncoder().encode(TapGateSettings(enabled: true))
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "detectionSource")
        let previous = try JSONDecoder().decode(TapGateSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(previous.detectionSource,.afterFilters); XCTAssertTrue(previous.enabled)
        json["detectionSource"] = "unknown"
        XCTAssertThrowsError(try JSONDecoder().decode(TapGateSettings.self, from: JSONSerialization.data(withJSONObject: json)))
    }
}
