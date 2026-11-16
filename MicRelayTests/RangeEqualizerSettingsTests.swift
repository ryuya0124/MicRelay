// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay

final class RangeEqualizerSettingsTests: XCTestCase {
    func testLegacyBackupPreservesExistingEQAndGain() throws {
        var eq = EqualizerSettings(); eq.enabled = true
        eq.bands[0] = EqualizerBand(id: 0, frequency: 362, gainDB: 0, q: 4.667850610678599, filter: .lowPass)
        let original = SettingsBackup(gain: 2.73888897895813, gainLimit: 4, equalizer: eq, backgroundEnabled: true, selectedInput: "builtin", audioMode: .automatic)
        var json = try JSONSerialization.jsonObject(with: original.encoded()) as! [String: Any]
        json["version"] = 1
        json.removeValue(forKey: "windNoise"); json.removeValue(forKey: "manualAudio"); json.removeValue(forKey: "tapGate")
        var object = json["equalizer"] as! [String: Any]
        object["bands"] = (object["bands"] as! [[String: Any]]).map { band in
            var value = band; value.removeValue(forKey: "lowerFrequency"); value.removeValue(forKey: "upperFrequency"); return value
        }
        json["equalizer"] = object
        let decoded = try SettingsBackup.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.gain, original.gain); XCTAssertEqual(decoded.gainLimit, original.gainLimit)
        XCTAssertEqual(decoded.equalizer.bands[0], eq.bands[0])
        XCTAssertEqual(decoded.equalizer.bands.map(\.filter), eq.bands.map(\.filter))
        XCTAssertEqual(decoded.audioMode, .automatic)
        XCTAssertTrue(decoded.equalizer.isValid)
    }

    func testRangeFiltersPersistAndBackupRoundTrip() throws {
        let name = "MicRelay.RangeTest.\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: name)!
        defer { isolated.removePersistentDomain(forName: name) }
        var eq = EqualizerSettings(); eq.enabled = true
        eq.bands[0].filter = .bandStop; eq.bands[0].lowerFrequency = 500; eq.bands[0].upperFrequency = 2000
        eq.bands[1].filter = .bandPass; eq.bands[1].lowerFrequency = 300; eq.bands[1].upperFrequency = 6000
        eq.save(in: isolated)
        XCTAssertEqual(EqualizerSettings.load(in: isolated), eq)
        let backup = SettingsBackup(gain: 3, gainLimit: 20, equalizer: eq, backgroundEnabled: true, selectedInput: "builtin")
        XCTAssertEqual(backup.version,4)
        XCTAssertEqual(try SettingsBackup.decode(backup.encoded()).equalizer,eq)
        var json = try JSONSerialization.jsonObject(with: backup.encoded()) as! [String: Any]; json["version"] = 1
        XCTAssertThrowsError(try SettingsBackup.decode(JSONSerialization.data(withJSONObject: json)))
    }

    func testInvalidBoundsAndMissingRangeFieldsAreRejected() throws {
        var eq = EqualizerSettings(); eq.bands[0].filter = .bandPass
        for range in [(500.0,500.0),(2000,500),(500,500.5),(0,1000),(500,20001),(Double.nan,1000)] {
            eq.bands[0].lowerFrequency = range.0; eq.bands[0].upperFrequency = range.1
            XCTAssertFalse(eq.isValid)
        }
        eq.bands[0].lowerFrequency = 500; eq.bands[0].upperFrequency = 2000
        let data = try JSONEncoder().encode(eq)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var bands = json["bands"] as! [[String: Any]]; bands[0].removeValue(forKey: "lowerFrequency"); json["bands"] = bands
        XCTAssertThrowsError(try JSONDecoder().decode(EqualizerSettings.self,from:JSONSerialization.data(withJSONObject:json)))
    }
}
