// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
@testable import MicRelay
final class BufferPreferenceSelectorTests: XCTestCase {
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
