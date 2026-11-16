// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import Foundation

/// No device model table. Probe the route's OS-enforced floor, then use measured input failures.
struct BufferTuner {
    private(set) var floorFrames: Double?
    private var lastMisses: UInt64 = 0
    private var windowMisses: UInt64 = 0
    private var windowStart: TimeInterval = 0
    private var graceUntil: TimeInterval = 0
    private var stableSince: TimeInterval = 0
    private var retryDelay: TimeInterval = 30
    private var lastProbe: TimeInterval?
    private var probeActualFrames: Double?

    mutating func resetObservedFloor() { floorFrames = nil } // Keep retry backoff across a fresh comparison.

    mutating func didStart(now: TimeInterval, actualFrames: Double, minimumObservedFrames: Double? = nil) {
        floorFrames = min(floorFrames ?? actualFrames, minimumObservedFrames ?? actualFrames, actualFrames)
        if let previous = probeActualFrames, actualFrames >= previous - 0.5 { retryDelay = min(300, retryDelay * 2) }
        probeActualFrames = nil
        lastMisses = 0; windowMisses = 0
        windowStart = now; stableSince = now; graceUntil = now + 1
    }

    mutating func evaluate(now: TimeInterval, actualFrames: Double, sampleRate: Double,
                           misses: UInt64, transientFailure: Bool, allowMinimumReprobe: Bool = false) -> Double? {
        floorFrames = min(floorFrames ?? actualFrames, actualFrames)
        let delta = misses >= lastMisses ? misses - lastMisses : misses
        lastMisses = misses
        guard now >= graceUntil || transientFailure else { return nil }
        windowMisses += delta
        let limit = min(2048, sampleRate * 0.08)
        if transientFailure || windowMisses >= 3 {
            if let probe = lastProbe, now - probe < 10 { retryDelay = min(300, retryDelay * 2) }
            lastProbe = nil
            stableSince = now; windowMisses = 0; windowStart = now
            let next = min(limit, actualFrames * 2)
            return next > actualFrames ? next : nil
        }
        if delta > 0 { stableSince = now }
        if now - windowStart >= 2 { windowMisses = 0; windowStart = now }
        if let floor = floorFrames, actualFrames > floor + 0.5, now - stableSince >= retryDelay {
            lastProbe = now; stableSince = now
            probeActualFrames = actualFrames
            return max(floor, actualFrames / 2)
        }
        // Recheck an initially constrained large buffer; do not treat the first shared session as a permanent floor.
        if allowMinimumReprobe, actualFrames / sampleRate > 0.004, now - stableSince >= retryDelay {
            lastProbe = now; stableSince = now; probeActualFrames = actualFrames
            return 1
        }
        return nil
    }
}
