// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation

struct BufferPreferenceMeasurement: Codable, Equatable {
    let requestedFrames: Double
    let actualFrames: UInt32
    let sampleRate: Double
    let ioBufferDuration: Double
    let inputLatency: Double
    let outputLatency: Double
    let missedQuanta: UInt64
    let renderedFrames: UInt64
    let renderError: Int32
    var mode: String = ""
    var observationDuration: Double = 0.16
    var score: Double { inputLatency + outputLatency + max(ioBufferDuration, Double(actualFrames) / sampleRate) }
    var matchesRequest: Bool { abs(max(Double(actualFrames), ioBufferDuration * sampleRate) - requestedFrames) < 0.5 }
    var isStable: Bool {
        requestedFrames > 0 && actualFrames > 0 && sampleRate.isFinite && sampleRate > 0 &&
        [ioBufferDuration, inputLatency, outputLatency].allSatisfy { $0.isFinite && $0 >= 0 } &&
        observationDuration.isFinite && observationDuration > 0 &&
        Double(renderedFrames) >= sampleRate * observationDuration * 0.8 && renderError == 0 && missedQuanta == 0
    }
}
enum BufferPreferenceSelector {
    static let requests: [Double] = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048]
    static func best(_ measurements: [BufferPreferenceMeasurement]) -> BufferPreferenceMeasurement? {
        measurements.filter(\.isStable).min {
            if abs($0.score - $1.score) < 1e-9 {
                if $0.matchesRequest != $1.matchesRequest { return $0.matchesRequest }
                if $0.requestedFrames != $1.requestedFrames { return $0.requestedFrames < $1.requestedFrames }
                return $0.mode != $1.mode && $0.mode.hasSuffix("Measurement")
            }
            return $0.score < $1.score
        }
    }
}
