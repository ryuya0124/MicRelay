// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import XCTest
@testable import MicRelay

final class BufferTunerTests: XCTestCase {
    func testStartupMissesDoNotRaiseBuffer() {
        var tuner = BufferTuner()
        tuner.didStart(now: 0, actualFrames: 32)
        XCTAssertNil(tuner.evaluate(now: 0.5, actualFrames: 32, sampleRate: 48000, misses: 2, transientFailure: false))
        XCTAssertNil(tuner.evaluate(now: 1.5, actualFrames: 32, sampleRate: 48000, misses: 2, transientFailure: false))
        XCTAssertEqual(tuner.floorFrames, 32)
    }

    func testDeviceRouteSpecificFloorAndRecovery() {
        var tuner = BufferTuner()
        tuner.didStart(now: 0, actualFrames: 128)
        XCTAssertEqual(tuner.evaluate(now: 2, actualFrames: 128, sampleRate: 48000, misses: 4, transientFailure: false), 256)
        tuner.didStart(now: 2, actualFrames: 256)
        XCTAssertNil(tuner.evaluate(now: 15, actualFrames: 256, sampleRate: 48000, misses: 0, transientFailure: false))
        XCTAssertEqual(tuner.evaluate(now: 33, actualFrames: 256, sampleRate: 48000, misses: 0, transientFailure: false), 128)
        tuner.didStart(now: 33, actualFrames: 128)
        XCTAssertNil(tuner.evaluate(now: 100, actualFrames: 128, sampleRate: 48000, misses: 0, transientFailure: false))
    }

    func testRepeatedFailedProbesBackOff() {
        var tuner = BufferTuner()
        tuner.didStart(now: 0, actualFrames: 32)
        XCTAssertEqual(tuner.evaluate(now: 2, actualFrames: 32, sampleRate: 48000, misses: 0, transientFailure: true), 64)
        tuner.didStart(now: 2, actualFrames: 64)
        XCTAssertEqual(tuner.evaluate(now: 33, actualFrames: 64, sampleRate: 48000, misses: 0, transientFailure: false), 32)
        tuner.didStart(now: 33, actualFrames: 32)
        XCTAssertEqual(tuner.evaluate(now: 34, actualFrames: 32, sampleRate: 48000, misses: 0, transientFailure: true), 64)
        tuner.didStart(now: 34, actualFrames: 64)
        XCTAssertNil(tuner.evaluate(now: 65, actualFrames: 64, sampleRate: 48000, misses: 0, transientFailure: false))
        XCTAssertEqual(tuner.evaluate(now: 95, actualFrames: 64, sampleRate: 48000, misses: 0, transientFailure: false), 32)
    }

    func testBrokenInputCannotIncreaseLatencyWithoutBound() {
        var tuner = BufferTuner()
        tuner.didStart(now: 0, actualFrames: 2048)
        XCTAssertNil(tuner.evaluate(now: 2, actualFrames: 2048, sampleRate: 48000, misses: 100, transientFailure: true))
    }

    func testInitialConstraintIsRecheckedAndUnchangedHardwareBacksOff() {
        var tuner = BufferTuner()
        tuner.didStart(now: 0, actualFrames: 1024)
        XCTAssertEqual(tuner.evaluate(now: 31, actualFrames: 1024, sampleRate: 48000, misses: 0, transientFailure: false, allowMinimumReprobe: true), 1)
        tuner.didStart(now: 31, actualFrames: 1024)
        XCTAssertNil(tuner.evaluate(now: 62, actualFrames: 1024, sampleRate: 48000, misses: 0, transientFailure: false, allowMinimumReprobe: true))
        XCTAssertEqual(tuner.evaluate(now: 92, actualFrames: 1024, sampleRate: 48000, misses: 0, transientFailure: false, allowMinimumReprobe: true), 1)
        tuner.didStart(now: 92, actualFrames: 16, minimumObservedFrames: 16)
        XCTAssertEqual(tuner.floorFrames, 16)
        XCTAssertNil(tuner.evaluate(now: 500, actualFrames: 16, sampleRate: 48000, misses: 0, transientFailure: false, allowMinimumReprobe: true))
    }

    func testLowerObservedFloorIsNotLostWhenStableStartupUsesLargerBuffer() {
        var tuner = BufferTuner()
        tuner.didStart(now: 0, actualFrames: 128, minimumObservedFrames: 16)
        XCTAssertEqual(tuner.floorFrames, 16)
        XCTAssertEqual(tuner.evaluate(now: 31, actualFrames: 128, sampleRate: 48000, misses: 0, transientFailure: false), 64)
        tuner.didStart(now: 31, actualFrames: 64)
        XCTAssertEqual(tuner.floorFrames, 16)
    }
}
