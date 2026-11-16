// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay

final class LatencyReprobeTriggerTests: XCTestCase {
    func testBaselineCanBeEstablishedAfterTheFirstCallbackArrives() {
        var trigger = LatencyReprobeTrigger()
        trigger.didStart(now:0,baseline:path(frames:0))
        XCTAssertFalse(trigger.evaluate(now:4,current:path(),misses:0,allowed:true))
        XCTAssertFalse(trigger.evaluate(now:8,current:path(output:0.017),misses:0,allowed:true))
        XCTAssertTrue(trigger.evaluate(now:11,current:path(output:0.017),misses:0,allowed:true))
    }
    private func path(output: Double = 0.0003, rate: Double = 48000, frames: UInt32 = 16) -> ModeLatencyMeasurement {
        .init(mode:"default",inputLatency:0.001,outputLatency:output,ioBufferDuration:Double(frames)/rate,sampleRate:rate,quantum:frames)
    }
    func testSlowerOSPathIsDetectedEvenWhenTheQuantumDoesNotChange() {
        var trigger = LatencyReprobeTrigger()
        trigger.didStart(now:0,baseline:path())
        XCTAssertFalse(trigger.evaluate(now:4,current:path(output:0.017),misses:0,allowed:true))
        XCTAssertTrue(trigger.evaluate(now:7,current:path(output:0.017),misses:0,allowed:true))
        trigger.didStart(now:8,baseline:path(output:0.017))
        XCTAssertFalse(trigger.evaluate(now:100,current:path(output:0.017),misses:0,allowed:true))
    }
    func testAnOrdinaryQuantumIncreaseDoesNotCauseAModeSweep() {
        var trigger = LatencyReprobeTrigger()
        trigger.didStart(now:0,baseline:path())
        XCTAssertFalse(trigger.evaluate(now:4,current:path(frames:256),misses:0,allowed:true))
        XCTAssertFalse(trigger.evaluate(now:100,current:path(frames:256),misses:0,allowed:true))
    }
    func testRateChangeRespectsCooldownAndBackgroundRestriction() {
        var trigger = LatencyReprobeTrigger()
        trigger.didProbe(now:0); trigger.didStart(now:0,baseline:path())
        let changed = path(rate:96000,frames:32)
        XCTAssertFalse(trigger.evaluate(now:4,current:changed,misses:0,allowed:true))
        XCTAssertFalse(trigger.evaluate(now:7,current:changed,misses:0,allowed:true))
        XCTAssertFalse(trigger.evaluate(now:30,current:changed,misses:0,allowed:false))
        XCTAssertFalse(trigger.evaluate(now:31,current:changed,misses:0,allowed:true))
        XCTAssertTrue(trigger.evaluate(now:34,current:changed,misses:0,allowed:true))
    }
    func testDropoutsResetTheSustainedChangeWindow() {
        var trigger = LatencyReprobeTrigger()
        trigger.didStart(now:0,baseline:path())
        let changed = path(output:0.01)
        XCTAssertFalse(trigger.evaluate(now:4,current:changed,misses:0,allowed:true))
        XCTAssertFalse(trigger.evaluate(now:5,current:changed,misses:1,allowed:true))
        XCTAssertFalse(trigger.evaluate(now:7,current:changed,misses:1,allowed:true))
        XCTAssertTrue(trigger.evaluate(now:10,current:changed,misses:1,allowed:true))
    }
}
