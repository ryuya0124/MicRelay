// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay
final class SettingsBackupTests: XCTestCase {
    func testRoundTripKeepsLargeGainAndAllSettings() throws {
        var eq = EqualizerSettings(); eq.enabled = true; eq.bands[3].filter = .notch
        let value = SettingsBackup(gain: 1234, gainLimit: 1e100, equalizer: eq, backgroundEnabled: false, selectedInput: "external-mic", audioMode: .measurement)
        let decoded = try SettingsBackup.decode(value.encoded())
        XCTAssertEqual(decoded.gain, value.gain); XCTAssertEqual(decoded.gainLimit, value.gainLimit)
        XCTAssertEqual(decoded.equalizer, eq); XCTAssertFalse(decoded.backgroundEnabled)
        XCTAssertEqual(decoded.selectedInput, value.selectedInput)
        XCTAssertEqual(decoded.audioMode, .measurement)
    }
    func testRejectsFutureSchemaInvalidValuesAndOversizedFiles() throws {
        let value = SettingsBackup(gain: 0.5, gainLimit: 10, equalizer: .init(), backgroundEnabled: true, selectedInput: "builtin")
        var json = try JSONSerialization.jsonObject(with: value.encoded()) as! [String: Any]
        json["version"] = 999
        XCTAssertThrowsError(try SettingsBackup.decode(JSONSerialization.data(withJSONObject: json)))
        json["version"] = 2; json["gain"] = 11
        XCTAssertThrowsError(try SettingsBackup.decode(JSONSerialization.data(withJSONObject: json)))
        XCTAssertThrowsError(try SettingsBackup.decode(Data(repeating: 0, count: 1_048_577)))
        var eq = EqualizerSettings(); eq.bands[1].id = 0
        XCTAssertThrowsError(try SettingsBackup(gain: 0, gainLimit: 10, equalizer: eq, backgroundEnabled: true, selectedInput: "builtin").validated())
    }
}
