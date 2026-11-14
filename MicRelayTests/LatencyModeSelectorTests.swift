// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import XCTest
@testable import MicRelay

final class LatencyModeSelectorTests: XCTestCase {
    private func candidate(_ mode: String, input: Double, output: Double, quantum: UInt32 = 144) -> ModeLatencyMeasurement {
        ModeLatencyMeasurement(mode: mode, inputLatency: input, outputLatency: output,
            ioBufferDuration: 0.003, sampleRate: 48000, quantum: quantum)
    }

    func testChoosesTotalPathRatherThanOnlyShortestInput() {
        let measurement = candidate("AVAudioSessionModeMeasurement", input: 0.000292, output: 0.017542)
        let standard = candidate("AVAudioSessionModeDefault", input: 0.001292, output: 0.001042)
        XCTAssertEqual(LatencyModeSelector.best([measurement, standard]), standard)
    }

    func testMeasurementCanWinOnAnotherDeviceAndInvalidSamplesAreRejected() {
        let measurement = candidate("AVAudioSessionModeMeasurement", input: 0.001, output: 0.001)
        let standard = candidate("AVAudioSessionModeDefault", input: 0.008, output: 0.003)
        let invalid = candidate("Invalid", input: .nan, output: 0)
        XCTAssertEqual(LatencyModeSelector.best([invalid, standard, measurement]), measurement)
        XCTAssertNil(LatencyModeSelector.best([invalid]))
    }
}
