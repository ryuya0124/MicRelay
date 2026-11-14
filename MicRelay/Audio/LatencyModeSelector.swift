// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import Foundation

struct ModeLatencyMeasurement: Codable, Equatable {
    let mode: String
    let inputLatency: Double
    let outputLatency: Double
    let ioBufferDuration: Double
    let sampleRate: Double
    let quantum: UInt32

    var score: Double { inputLatency + outputLatency + max(ioBufferDuration, Double(quantum) / sampleRate) }
    var isValid: Bool {
        sampleRate.isFinite && sampleRate > 0 && quantum > 0 &&
        [inputLatency, outputLatency, ioBufferDuration].allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

enum LatencyModeSelector {
    static func best(_ measurements: [ModeLatencyMeasurement]) -> ModeLatencyMeasurement? {
        measurements.filter(\.isValid).min {
            if abs($0.score - $1.score) < 0.000_000_001 { return $0.mode.hasSuffix("Measurement") }
            return $0.score < $1.score
        }
    }
}
