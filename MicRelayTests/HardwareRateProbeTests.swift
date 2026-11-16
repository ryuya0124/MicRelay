// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay
final class HardwareRateProbeTests: XCTestCase {
    private func sample(_ rate: Double, frames: UInt32, input: Double = 0.001, output: Double = 0.0003, misses: UInt64 = 0, mode: String = "default", hint: Double? = nil) -> BufferPreferenceMeasurement {
        .init(requestedFrames: Double(frames), actualFrames: frames, sampleRate: rate, ioBufferDuration: Double(frames)/rate,
            inputLatency: input, outputLatency: output, missedQuanta: misses, renderedFrames: UInt64(rate*0.2), renderError: 0,
            mode: mode, observationDuration: 0.2, requestedSampleRate: hint)
    }
    func testChoosesMeasuredTotalRatherThanHighestSampleRate() {
        let normal = sample(48000,frames:16)
        let fast = sample(96000,frames:16)
        let largerQuantum = sample(192000,frames:128)
        XCTAssertEqual(BufferPreferenceSelector.best([normal,fast,largerQuantum]),fast)
        let expensiveInput = sample(192000,frames:16,input:0.008)
        XCTAssertEqual(BufferPreferenceSelector.best([normal,fast,expensiveInput]),fast)
        XCTAssertEqual(BufferPreferenceSelector.best([normal,sample(96000,frames:16,misses:1)]),normal)
    }
    func testKnownAudioUnitProcessingDelayIsIncludedInRanking() {
        let normal = sample(48000,frames:16)
        var converted = sample(192000,frames:16)
        converted.processingLatency = 0.004
        XCTAssertEqual(BufferPreferenceSelector.best([normal,converted]),normal)
        XCTAssertEqual(LatencyModeSelector.best([normal.latencyMeasurement,converted.latencyMeasurement]),normal.latencyMeasurement)
        XCTAssertFalse(normal.reproduces(converted))
        var sameRate = normal; sameRate.processingLatency = 0
        var slower = sameRate; slower.processingLatency = 0.004
        XCTAssertFalse(slower.reproduces(sameRate))
        converted.processingLatency = -1
        XCTAssertFalse(converted.isStable)
        XCTAssertFalse(converted.latencyMeasurement.isValid)
    }
    func testIgnoredRateHintsReuseOnlyStableActualConfigurations() {
        let baseline = sample(48000,frames:16)
        XCTAssertTrue(HardwareRateProbePlanner.canReuse(sample(48000,frames:16,hint:192000),reference:baseline))
        XCTAssertFalse(HardwareRateProbePlanner.canReuse(sample(48000,frames:16,misses:1,hint:192000),reference:baseline))
        XCTAssertFalse(HardwareRateProbePlanner.canReuse(sample(96000,frames:16),reference:baseline))
        XCTAssertFalse(HardwareRateProbePlanner.canReuse(sample(48000,frames:16,mode:"measurement"),reference:baseline))
        XCTAssertFalse(HardwareRateProbePlanner.canReuse(sample(48000,frames:16,output:0.017),reference:baseline))
    }
    func testObservedFloorIsScopedToTheWinningModeAndActualRate() {
        let values = [sample(48000,frames:8), sample(96000,frames:32), sample(96000,frames:16,mode:"measurement")]
        XCTAssertEqual(BufferPreferenceSelector.observedFloor(values,mode:"default",sampleRate:96000),32)
        XCTAssertEqual(BufferPreferenceSelector.observedFloor(values,mode:"measurement",sampleRate:96000),16)
        XCTAssertNil(BufferPreferenceSelector.observedFloor(values,mode:"default",sampleRate:192000))
    }
    func testRateCandidatesKeepTheCurrentHardwareRateAndFixedDiagnostics() {
        let values = HardwareRateProbePlanner.requests(current:44100,preferred:44100)
        XCTAssertEqual(values.first,44100); XCTAssertEqual(Set(values).count,values.count)
        XCTAssertTrue(values.contains(48000)); XCTAssertTrue(values.contains(96000)); XCTAssertTrue(values.contains(192000))
        XCTAssertTrue(values.contains(352800))
        XCTAssertEqual(HardwareRateProbePlanner.requests(current:48000,preferred:48000,fixed:96000),[96000])
        XCTAssertTrue(HardwareRateProbePlanner.requests(current:.nan,preferred:.infinity).allSatisfy { $0.isFinite && $0 > 0 })
    }
}
