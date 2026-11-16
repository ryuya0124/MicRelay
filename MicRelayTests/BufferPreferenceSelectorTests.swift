// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay
final class BufferPreferenceSelectorTests: XCTestCase {
    func testPacketPeriodRequestsFollowActualRateAndIncludeFractionalClocks() {
        let narrowBand = BufferPreferenceSelector.frameRequests(sampleRate:8000)
        XCTAssertTrue(narrowBand.contains(60)); XCTAssertTrue(narrowBand.contains(160))
        let usb = BufferPreferenceSelector.frameRequests(sampleRate:44100)
        XCTAssertTrue(usb.contains(where: { abs($0 - 44.1) < 1e-9 }))
        XCTAssertTrue(usb.contains(44)); XCTAssertTrue(usb.contains(45))
        XCTAssertTrue(usb.allSatisfy { $0 >= 1 && $0 <= 2048 })
        XCTAssertEqual(usb, usb.sorted())
        XCTAssertEqual(BufferPreferenceSelector.frameRequests(sampleRate:.nan),BufferPreferenceSelector.requests)
    }
    func testFractionalQuantumDoesNotOscillateAndRestoresTheOriginalTimeHint() {
        XCTAssertEqual(BufferPreferenceSelector.effectiveFrames(quantum:44,duration:0.001,sampleRate:44100),45)
        XCTAssertEqual(BufferPreferenceSelector.effectiveFrames(quantum:45,duration:0.001,sampleRate:44100),45)
        XCTAssertEqual(BufferPreferenceSelector.effectiveFrames(quantum:16,duration:16/48000,sampleRate:48000),16)
        let preference = BufferPreferenceMeasurement(requestedFrames:44.1,actualFrames:45,sampleRate:44100,ioBufferDuration:0.001,
            inputLatency:0.001,outputLatency:0.0003,missedQuanta:0,renderedFrames:8820,renderError:0,observationDuration:0.2)
        XCTAssertEqual(BufferPreferenceSelector.recoveryRequest(45,sampleRate:44100,preferred:preference),44.1)
        XCTAssertEqual(BufferPreferenceSelector.recoveryRequest(45,sampleRate:48000,preferred:preference),45)
    }
    func testLargerBufferCanWinAndItsLatencyOptimumMustBePreserved() {
        let small = BufferPreferenceMeasurement(requestedFrames:16,actualFrames:16,sampleRate:48000,ioBufferDuration:16/48000,
            inputLatency:0.001,outputLatency:0.01,missedQuanta:0,renderedFrames:9600,renderError:0,mode:"default",observationDuration:0.2)
        let larger = BufferPreferenceMeasurement(requestedFrames:32,actualFrames:32,sampleRate:48000,ioBufferDuration:32/48000,
            inputLatency:0.001,outputLatency:0.0003,missedQuanta:0,renderedFrames:9600,renderError:0,mode:"default",observationDuration:0.2)
        XCTAssertTrue(small.matchesRequest)
        XCTAssertEqual(BufferPreferenceSelector.ranked([small,larger]).first,larger)
        XCTAssertEqual(BufferPreferenceSelector.observedFloor([small,larger],mode:"default",sampleRate:48000,maximumScore:larger.score),32)
        var tuner = BufferTuner()
        tuner.didStart(now:0,actualFrames:32,minimumObservedFrames:32)
        XCTAssertNil(tuner.evaluate(now:100,actualFrames:32,sampleRate:48000,misses:0,transientFailure:false))
    }

    func testFasterUnstableQuantumCanStillBeRetriedAfterRecovery() {
        let small = measurement(16,16,misses:1), larger = measurement(64,64)
        XCTAssertEqual(BufferPreferenceSelector.observedFloor([small,larger],mode:"",sampleRate:48000,maximumScore:larger.score),16)
        for request in [3.0,6,12,24,48,96,192,384,768,1536] { XCTAssertTrue(BufferPreferenceSelector.requests.contains(request)) }
    }

    func testFinalProfileMustReproduceTheMeasuredLatencyNotJustSampleRate() {
        let original = measurement(16,16)
        XCTAssertTrue(original.reproduces(original))
        var drift = original; drift.observationDuration = 1
        XCTAssertFalse(drift.reproduces(original))
        XCTAssertFalse(measurement(32,32).reproduces(original))
        XCTAssertFalse(measurement(16,16,misses:1).reproduces(original))
    }
    private func measurement(_ request: Double, _ actual: UInt32, misses: UInt64 = 0) -> BufferPreferenceMeasurement {
        .init(requestedFrames: request, actualFrames: actual, sampleRate: 48000, ioBufferDuration: Double(actual) / 48000,
            inputLatency: 0.0013, outputLatency: 0.0003, missedQuanta: misses, renderedFrames: 7680, renderError: 0)
    }
    func testSmallestRequestCanProduceLargerRealBuffer() {
        let values = [measurement(1, 1024), measurement(2, 128), measurement(16, 16), measurement(32, 32)]
        XCTAssertEqual(BufferPreferenceSelector.best(values)?.requestedFrames, 16)
        XCTAssertEqual(BufferPreferenceSelector.best(values)?.actualFrames, 16)
    }
    func testRejectsDroppedInputAndSupportsDifferentHardwareFloor() {
        XCTAssertEqual(BufferPreferenceSelector.best([measurement(8, 8, misses: 1), measurement(16, 32), measurement(32, 32)])?.requestedFrames, 32)
        XCTAssertNil(BufferPreferenceSelector.best([measurement(16, 16, misses: 2)]))
        var stalled = measurement(16, 16)
        stalled.observationDuration = 1
        XCTAssertFalse(stalled.isStable)
    }

    func testFallsBackTo512OrLargerWhenSmallBuffersAreUnstable() {
        XCTAssertTrue(BufferPreferenceSelector.requests.contains(512))
        let values = [measurement(16, 16, misses: 3), measurement(128, 128, misses: 1),
                      measurement(256, 256, misses: 1), measurement(512, 512), measurement(1024, 1024)]
        XCTAssertEqual(BufferPreferenceSelector.best(values)?.requestedFrames, 512)
        XCTAssertEqual(BufferPreferenceSelector.best([measurement(512, 512, misses: 1), measurement(2048, 2048)])?.requestedFrames, 2048)
    }
}
