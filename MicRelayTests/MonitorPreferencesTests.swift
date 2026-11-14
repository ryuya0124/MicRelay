// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import XCTest
@testable import MicRelay

final class MonitorPreferencesTests: XCTestCase {
    func testGainSurvivesReloadAndSupportsOneThousandPercent() {
        let name = "MicRelayTests.\(UUID().uuidString)"
        let first = UserDefaults(suiteName: name)!
        defer { first.removePersistentDomain(forName: name) }
        XCTAssertEqual(MonitorPreferences.gain(in: first), 0.5)
        XCTAssertEqual(MonitorPreferences.gainLimit(in: first), 2)
        MonitorPreferences.saveGainLimit(10, in: first)
        MonitorPreferences.saveGain(10, in: first)
        let reloaded = UserDefaults(suiteName: name)!
        XCTAssertEqual(MonitorPreferences.gain(in: reloaded), 10)
        MonitorPreferences.saveGain(2.37, in: reloaded)
        XCTAssertEqual(MonitorPreferences.gain(in: first), 2.37, accuracy: 0.0001)
    }

    func testInvalidStoredGainIsBounded() {
        let name = "MicRelayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        MonitorPreferences.saveGainLimit(10, in: defaults)
        defaults.set(1000, forKey: MonitorPreferences.gainKey)
        XCTAssertEqual(MonitorPreferences.gain(in: defaults), 10)
        defaults.set(-2, forKey: MonitorPreferences.gainKey)
        XCTAssertEqual(MonitorPreferences.gain(in: defaults), 0)
    }

    func testNewDefaultAndLegacyGainMigration() {
        let name = "MicRelay.Migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(MonitorPreferences.gainLimit(in: defaults), 2)
        defaults.set(10, forKey: MonitorPreferences.gainKey)
        XCTAssertEqual(MonitorPreferences.gainLimit(in: defaults), 10)
        XCTAssertEqual(MonitorPreferences.gain(in: defaults), 10)
        XCTAssertTrue(MonitorPreferences.saveGainLimit(2, in: defaults))
        XCTAssertEqual(MonitorPreferences.gain(in: defaults), 2)
    }

    func testUserCanSetAnUpperBoundAboveAnyApplicationPreset() {
        let name = "MicRelayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(MonitorPreferences.saveGainLimit(1e100, in: defaults))
        MonitorPreferences.saveGain(1e90, in: defaults)
        let reloaded = UserDefaults(suiteName: name)!
        XCTAssertEqual(MonitorPreferences.gainLimit(in: reloaded), 1e100)
        XCTAssertEqual(MonitorPreferences.gain(in: reloaded), 1e90)
        XCTAssertTrue(MonitorPreferences.saveGainLimit(2, in: defaults))
        XCTAssertEqual(MonitorPreferences.gain(in: defaults), 2)
        XCTAssertFalse(MonitorPreferences.saveGainLimit(.infinity, in: defaults))
        XCTAssertFalse(MonitorPreferences.saveGainLimit(0, in: defaults))
    }
}
