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

    mutating func didStart(now: TimeInterval, actualFrames: Double) {
        if floorFrames == nil { floorFrames = actualFrames }
        lastMisses = 0; windowMisses = 0
        windowStart = now; stableSince = now; graceUntil = now + 1
    }

    mutating func evaluate(now: TimeInterval, actualFrames: Double, sampleRate: Double,
                           misses: UInt64, transientFailure: Bool) -> Double? {
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
            return max(floor, actualFrames / 2)
        }
        return nil
    }
}
