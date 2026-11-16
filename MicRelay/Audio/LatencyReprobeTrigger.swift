// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation

/// Revisit an unchanged I/O quantum when the OS's input/output path becomes slower.
/// Ordinary quantum recovery remains the responsibility of BufferTuner.
struct LatencyReprobeTrigger {
    private var baseline: ModeLatencyMeasurement?
    private var startedAt: TimeInterval = 0
    private var lastProbe: TimeInterval?
    private var worsenedSince: TimeInterval?
    private var lastMisses: UInt64 = 0

    mutating func didProbe(now: TimeInterval) { lastProbe = now; worsenedSince = nil }
    mutating func didStart(now: TimeInterval, baseline: ModeLatencyMeasurement) {
        self.baseline = baseline.isValid ? baseline : nil
        startedAt = now; worsenedSince = nil; lastMisses = 0
    }
    mutating func evaluate(now: TimeInterval, current: ModeLatencyMeasurement, misses: UInt64, allowed: Bool) -> Bool {
        let delta = misses >= lastMisses ? misses - lastMisses : misses
        lastMisses = misses
        if baseline == nil, current.isValid {
            baseline = current; startedAt = now; worsenedSince = nil
            return false
        }
        guard allowed, current.isValid, let baseline, delta == 0, now - startedAt >= 3 else {
            worsenedSince = nil; return false
        }
        let rateChanged = abs(current.sampleRate - baseline.sampleRate) >= 0.5
        let baselinePath = baseline.inputLatency + baseline.outputLatency + (baseline.processingLatency ?? 0)
        let currentPath = current.inputLatency + current.outputLatency + (current.processingLatency ?? 0)
        let threshold = max(0.0005, baselinePath * 0.25)
        let slowerPath = currentPath > baselinePath + threshold
        guard rateChanged || slowerPath else { worsenedSince = nil; return false }
        if worsenedSince == nil { worsenedSince = now }
        guard now - worsenedSince! >= 3, lastProbe.map({ now - $0 >= 30 }) ?? true else { return false }
        didProbe(now: now)
        return true
    }
}
