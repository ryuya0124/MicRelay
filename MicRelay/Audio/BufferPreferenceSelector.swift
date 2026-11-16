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
    var requestedSampleRate: Double? = nil
    var processingLatency: Double? = nil
    var comparisonTolerance: Double { max(0.000025, 1 / sampleRate) }
    func reproduces(_ reference: Self) -> Bool {
        let tolerance = max(comparisonTolerance, reference.comparisonTolerance)
        let sameProcessing: Bool
        switch (processingLatency, reference.processingLatency) {
        case (nil, nil): sameProcessing = true
        case let (a?, b?): sameProcessing = abs(a - b) <= tolerance
        default: sameProcessing = false
        }
        return isStable && reference.isStable && sameProcessing && mode == reference.mode &&
            abs(sampleRate - reference.sampleRate) < 0.5 && actualFrames == reference.actualFrames &&
            abs(ioBufferDuration - reference.ioBufferDuration) <= tolerance &&
            abs(inputLatency - reference.inputLatency) <= tolerance &&
            abs(outputLatency - reference.outputLatency) <= tolerance
    }
    var latencyMeasurement: ModeLatencyMeasurement {
        .init(mode: mode, inputLatency: inputLatency, outputLatency: outputLatency,
              ioBufferDuration: ioBufferDuration, sampleRate: sampleRate, quantum: actualFrames, processingLatency: processingLatency)
    }
    var score: Double { inputLatency + outputLatency + max(ioBufferDuration, Double(actualFrames) / sampleRate) + (processingLatency ?? 0) }
    var matchesRequest: Bool { abs(max(Double(actualFrames), ioBufferDuration * sampleRate) - requestedFrames) < 0.5 }
    var isStable: Bool {
        requestedFrames > 0 && actualFrames > 0 && sampleRate.isFinite && sampleRate > 0 && score.isFinite &&
        (processingLatency.map { $0.isFinite && $0 >= 0 } ?? true) &&
        [ioBufferDuration, inputLatency, outputLatency].allSatisfy { $0.isFinite && $0 >= 0 } &&
        observationDuration.isFinite && observationDuration > 0 &&
        Double(renderedFrames) >= sampleRate * observationDuration * 0.8 && renderError == 0 && missedQuanta == 0
    }
}
enum BufferPreferenceSelector {
    static let requests: [Double] = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]
    static func frameRequests(sampleRate: Double) -> [Double] {
        guard sampleRate.isFinite, sampleRate > 0 else { return requests }
        // USB microframes and common USB/Bluetooth packet periods need not be powers of two.
        let seconds = [0.000125, 0.00025, 0.0005, 0.001, 0.002, 0.0025, 0.005, 0.0075, 0.01, 0.015, 0.02]
        var values = requests
        for duration in seconds {
            let frames = duration * sampleRate
            for value in [floor(frames), frames, ceil(frames)] where value >= 1 && value <= 2048 {
                if !values.contains(where: { abs($0 - value) < 1e-9 }) { values.append(value) }
            }
        }
        return values.sorted()
    }
    static func effectiveFrames(quantum: UInt32, duration: Double, sampleRate: Double) -> Double {
        let frames = duration * sampleRate
        guard duration.isFinite, duration >= 0, sampleRate.isFinite, sampleRate > 0, frames.isFinite else { return Double(quantum) }
        // A fractional period can alternate e.g. 44/45 callbacks. Do not mistake that for a regression.
        return max(Double(quantum), ceil(frames - 1e-6))
    }
    static func recoveryRequest(_ frames: Double, sampleRate: Double, preferred: BufferPreferenceMeasurement?) -> Double {
        guard let preferred, abs(sampleRate - preferred.sampleRate) < 0.5 else { return frames }
        let target = effectiveFrames(quantum: preferred.actualFrames, duration: preferred.ioBufferDuration, sampleRate: sampleRate)
        return abs(frames - target) < 0.5 ? preferred.requestedFrames : frames
    }
    static func observedFloor(_ measurements: [BufferPreferenceMeasurement], mode: String, sampleRate: Double, maximumScore: Double = .infinity) -> Double? {
        measurements.filter { $0.mode == mode && abs($0.sampleRate - sampleRate) < 0.5 &&
            $0.score <= maximumScore &&
            $0.actualFrames > 0 && $0.renderedFrames > 0 && $0.ioBufferDuration.isFinite && $0.ioBufferDuration >= 0 }
            .map { max(Double($0.actualFrames), $0.ioBufferDuration * $0.sampleRate) }.min()
    }
    static func best(_ measurements: [BufferPreferenceMeasurement]) -> BufferPreferenceMeasurement? {
        measurements.filter(\.isStable).min(by: precedes)
    }
    static func ranked(_ measurements: [BufferPreferenceMeasurement]) -> [BufferPreferenceMeasurement] {
        measurements.filter(\.isStable).sorted(by: precedes)
    }
    private static func precedes(_ lhs: BufferPreferenceMeasurement, _ rhs: BufferPreferenceMeasurement) -> Bool {
        if abs(lhs.score - rhs.score) < 1e-9 {
            if lhs.matchesRequest != rhs.matchesRequest { return lhs.matchesRequest }
            if lhs.requestedFrames != rhs.requestedFrames { return lhs.requestedFrames < rhs.requestedFrames }
            return lhs.mode != rhs.mode && lhs.mode.hasSuffix("Measurement")
        }
        return lhs.score < rhs.score
    }
}

struct HardwareRateProbeKey: Hashable {
    let mode: String
    let rate: Double
    init(_ value: BufferPreferenceMeasurement) {
        mode = value.mode; rate = value.sampleRate.rounded()
    }
}

enum HardwareRateProbePlanner {
    // Hints only. Keep the current route's rate and validate actual rates after activation.
    static func requests(current: Double, preferred: Double, fixed: Double? = nil) -> [Double] {
        if let fixed, fixed.isFinite, fixed >= 8000, fixed <= 384000 { return [fixed] }
        var result: [Double] = []
        for rate in [current, preferred, 48000, 96000, 192000, 44100, 88200, 176400, 352800, 384000]
            where rate.isFinite && (8000...384000).contains(rate) {
            if !result.contains(where: { abs($0 - rate) < 0.5 }) { result.append(rate) }
        }
        return result
    }
    static func canReuse(_ observation: BufferPreferenceMeasurement, reference: BufferPreferenceMeasurement) -> Bool {
        // Same nominal rate alone does not prove that the hardware latency path is unchanged.
        observation.reproduces(reference)
    }
}
