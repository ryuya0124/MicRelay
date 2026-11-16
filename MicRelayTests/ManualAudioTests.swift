// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay
final class ManualAudioTests: XCTestCase {
    func testMenuOptionsKeepImportedSettingsAndAvoidDuplicates() {
        let standard = ManualAudioSettings()
        XCTAssertEqual(standard.frameOptions, ManualAudioSettings.frameChoices)
        XCTAssertEqual(standard.sampleRateOptions, ManualAudioSettings.sampleRateChoices)
        let restored = ManualAudioSettings(frames:123,sampleRate:50000)
        XCTAssertTrue(restored.frameOptions.contains(123))
        XCTAssertTrue(restored.sampleRateOptions.contains(50000))
        XCTAssertEqual(restored.frameOptions.count, ManualAudioSettings.frameChoices.count + 1)
        XCTAssertEqual(restored.sampleRateOptions.count, ManualAudioSettings.sampleRateChoices.count + 1)
        XCTAssertEqual(restored.frameOptions, restored.frameOptions.sorted())
        XCTAssertEqual(restored.sampleRateOptions, restored.sampleRateOptions.sorted())
    }
    private func observation(_ request: ManualAudioSettings = .init(), rate: Double = 48000, low: UInt32 = 16, high: UInt32 = 16,
                             mode: AudioModePreference = .standard, misses: UInt64 = 0, frames: UInt64 = 9600) -> ManualIOObservation {
        .init(request:request,sampleRate:rate,minimumFrames:low,maximumFrames:high,ioDuration:Double(high)/rate,mode:mode,
            renderedFrames:frames,misses:misses,renderError:0,duration:0.2)
    }
    func testRejectedHardwareSettingsNeverOverwriteSavedValuesOrGain() {
        let name="MicRelay.Manual.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let previous=ManualAudioSettings(frames:32,sampleRate:48000,mode:.measurement)
        previous.save(in:defaults)
        MonitorPreferences.saveGainLimit(4,in:defaults); MonitorPreferences.saveGain(2.73888897895813,in:defaults)
        let bytes=defaults.data(forKey:ManualAudioSettings.key)
        let requested=ManualAudioSettings(frames:16,sampleRate:96000,mode:.standard)
        XCTAssertFalse(ManualAudioSettings.commitVerified(observation(requested),in:defaults))
        XCTAssertEqual(defaults.data(forKey:ManualAudioSettings.key),bytes)
        XCTAssertEqual(ManualAudioSettings.load(in:defaults),previous)
        XCTAssertEqual(MonitorPreferences.gain(in:defaults),2.73888897895813)
        XCTAssertEqual(MonitorPreferences.gainLimit(in:defaults),4)
        XCTAssertFalse(ManualAudioSettings.commitVerified(observation(misses:1),in:defaults))
        XCTAssertFalse(ManualAudioSettings.commitVerified(observation(frames:100),in:defaults))
        XCTAssertTrue(ManualAudioSettings.commitVerified(observation(),in:defaults))
        XCTAssertEqual(ManualAudioSettings.load(in:defaults),.init())
    }
    func testEveryRequestedHardwareFieldMustMatchAndInputMustBeStable() {
        XCTAssertTrue(observation().accepted)
        XCTAssertFalse(observation(rate:96000).accepted)
        XCTAssertFalse(observation(.init(sampleRate:48000.1)).accepted)
        XCTAssertFalse(observation(low:8).accepted)
        XCTAssertFalse(observation(high:32).accepted)
        XCTAssertFalse(observation(mode:.measurement).accepted)
        XCTAssertFalse(observation(misses:1).accepted)
        XCTAssertFalse(observation(frames:0).accepted)
        let wrongDuration = ManualIOObservation(request:.init(),sampleRate:48000,minimumFrames:16,maximumFrames:16,
            ioDuration:0.01,mode:.standard,renderedFrames:9600,misses:0,renderError:0,duration:0.2)
        XCTAssertFalse(wrongDuration.accepted)
        XCTAssertFalse(ManualIOApplication(request:.init(),running:true,renderedFrames:9600,actualRate:48000,
            minimumFrames:16,maximumFrames:16,ioDuration:16.25/48000,actualMode:.standard).framesMatch)
        let stopped=ManualIOApplication(request:.init(),running:false,renderedFrames:9600,actualRate:48000,minimumFrames:16,maximumFrames:16,ioDuration:16/48000,actualMode:.standard)
        XCTAssertEqual(stopped.state,.inactive)
    }
    func testManualSettingsRejectInvalidValuesAndRetainValidImportedChoices() {
        XCTAssertFalse(ManualAudioSettings(frames:0).isValid)
        for bad in [0.0, -48000, Double.nan, .infinity] {
            XCTAssertFalse(ManualAudioSettings(sampleRate:bad).isValid)
        }
        XCTAssertTrue(ManualAudioSettings(frames:123,sampleRate:50000,mode:.measurement).isValid)
        XCTAssertFalse(ManualAudioSettings(mode:.automatic).isValid)
        XCTAssertFalse(ManualAudioSettings(mode:.manual).isValid)
    }
    func testBackupV4PreservesManualSettingsAndLegacyV2StillLoads() throws {
        let manual=ManualAudioSettings(frames:32,sampleRate:96000,mode:.measurement)
        let backup=SettingsBackup(gain:2.5,gainLimit:4,equalizer:.init(),backgroundEnabled:true,selectedInput:"builtin",audioMode:.manual,manualAudio:manual)
        let decoded=try SettingsBackup.decode(backup.encoded())
        XCTAssertEqual(decoded.version,4); XCTAssertEqual(decoded.manualAudio,manual); XCTAssertEqual(decoded.audioMode,.manual)
        var json=try JSONSerialization.jsonObject(with:backup.encoded()) as! [String:Any]
        json.removeValue(forKey:"manualAudio")
        XCTAssertThrowsError(try SettingsBackup.decode(JSONSerialization.data(withJSONObject:json)))
        json.removeValue(forKey:"tapGate")
        json["version"]=2;json["audioMode"]="automatic"
        let legacy=try SettingsBackup.decode(JSONSerialization.data(withJSONObject:json))
        XCTAssertNil(legacy.manualAudio);XCTAssertEqual(legacy.gain,2.5)
        json["audioMode"]="manual"
        XCTAssertThrowsError(try SettingsBackup.decode(JSONSerialization.data(withJSONObject:json)))
    }
}
