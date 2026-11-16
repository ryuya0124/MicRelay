// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay

final class StartupIOProbeTests: XCTestCase {
    private func entry(frames: UInt32 = 16) -> IOProfileCache.Entry {
        let sample = BufferPreferenceMeasurement(requestedFrames: Double(frames), actualFrames: frames, sampleRate: 48000,
            ioBufferDuration: Double(frames)/48000, inputLatency: 0.001, outputLatency: 0.0003,
            missedQuanta: 0, renderedFrames: 9600, renderError: 0, mode: "default", observationDuration: 0.2)
        return .init(measurement: sample, floor: Double(frames), modes: [sample.latencyMeasurement])
    }
    func testNormalComparisonStopsAtBudgetButInputRecoveryRemainsAvailable() {
        XCTAssertTrue(StartupIOProbe.canCompare(elapsed: 3.9, hasStable: true))
        XCTAssertFalse(StartupIOProbe.canCompare(elapsed: 4, hasStable: true))
        XCTAssertFalse(StartupIOProbe.canCompare(elapsed: 100, hasStable: true))
        XCTAssertTrue(StartupIOProbe.canCompare(elapsed: 100, hasStable: false))
        XCTAssertEqual(StartupIOProbe.frames.count,4)
        XCTAssertTrue(StartupIOProbe.recoveryFrames.contains(512)); XCTAssertEqual(StartupIOProbe.recoveryFrames.last,2048)
        XCTAssertLessThanOrEqual(StartupIOProbe.extraRates(current:48000,fixed:nil).count,2)
        XCTAssertEqual(StartupIOProbe.extraRates(current:48000,fixed:96000),[])
    }
    func testUnchangedLargeQuantumKeepsBackoffAfterFreshComparison() {
        var tuner = BufferTuner()
        tuner.didStart(now:0,actualFrames:512)
        XCTAssertEqual(tuner.evaluate(now:31,actualFrames:512,sampleRate:48000,misses:0,transientFailure:false,allowMinimumReprobe:true),1)
        tuner.resetObservedFloor()
        tuner.didStart(now:32,actualFrames:512,minimumObservedFrames:512)
        XCTAssertNil(tuner.evaluate(now:63,actualFrames:512,sampleRate:48000,misses:0,transientFailure:false,allowMinimumReprobe:true))
        XCTAssertEqual(tuner.evaluate(now:93,actualFrames:512,sampleRate:48000,misses:0,transientFailure:false,allowMinimumReprobe:true),1)
    }
    func testProfileSurvivesRelaunchAndIsSeparatedByRouteKey() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("profiles.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var first = IOProfileCache(url: url)
        let value = entry()
        first.put(value, for: "KA13|builtin|OS-A")
        var second = IOProfileCache(url: url)
        XCTAssertEqual(second["KA13|builtin|OS-A"]?.measurement,value.measurement)
        XCTAssertNil(second["another-device|builtin|OS-A"])
        XCTAssertNil(second["KA13|builtin|OS-B"])
        second.remove("KA13|builtin|OS-A")
        XCTAssertNil(IOProfileCache(url:url)["KA13|builtin|OS-A"])
    }
    func testCorruptCacheAndUnstableProfileCannotBecomeTrustedSettings() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("profiles.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("broken".utf8).write(to:url)
        var cache = IOProfileCache(url:url)
        XCTAssertNil(cache["route"])
        let invalid = entry(frames:0)
        XCTAssertFalse(invalid.isValid)
        cache.put(invalid,for:"route")
        XCTAssertNil(cache["route"])
        for index in 0..<18 { cache.put(entry(),for:"\(index)") }
        let saved = try JSONDecoder().decode([String:IOProfileCache.Entry].self,from:Data(contentsOf:url))
        XCTAssertEqual(saved.count,16)
    }
}
