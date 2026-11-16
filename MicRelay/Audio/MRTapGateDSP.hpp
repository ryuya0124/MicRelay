// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

namespace mr {
struct TapGateParameters {
    double minimumPower = 0, onsetRatio = 1, rearmRatio = 1;
    double backgroundAlpha = 0, peakDecay = 0;
    uint32_t duration = 1, fade = 1;
};
// Control thread only. The detector itself has no look-ahead or analysis window.
inline TapGateParameters tapGateParameters(double rate, double seconds, double minimumDB, double riseDB) {
    rate = std::isfinite(rate) && rate > 0 ? rate : 48000;
    seconds = std::isfinite(seconds) ? std::clamp(seconds, 0.001, 1.0) : 0.012;
    minimumDB = std::isfinite(minimumDB) ? std::clamp(minimumDB, -90.0, 0.0) : -42;
    riseDB = std::isfinite(riseDB) ? std::clamp(riseDB, 3.0, 30.0) : 16;
    TapGateParameters p;
    p.minimumPower = std::pow(10.0, minimumDB / 10);
    p.onsetRatio = std::pow(10.0, riseDB / 10);
    p.rearmRatio = std::pow(10.0, (riseDB - 3) / 10);
    p.backgroundAlpha = 1 - std::exp(-1 / (0.020 * rate));
    p.peakDecay = std::exp(-1 / (0.0004 * rate));
    p.duration = uint32_t(std::clamp(std::ceil(seconds * rate), 1.0, double(UINT32_MAX)));
    p.fade = std::max(uint32_t(1), std::min(p.duration, uint32_t(std::ceil(0.0002 * rate))));
    return p;
}
struct TapGateState {
    double backgroundPower = 0, peakPower = 0, onsetPeak = 0;
    uint32_t remaining = 0;
    uint64_t detections = 0;
    bool armed = true;
};
inline double processTapGate(double input, double detector, bool enabled, const TapGateParameters &p, TapGateState &s) {
    if (!enabled) return input; // Exact bypass: no detector or countdown advances.
    if (!std::isfinite(input) || !std::isfinite(detector)) { s = {}; return 0; }
    const double power = detector * detector;
    s.peakPower = std::max(power, s.peakPower * p.peakDecay);
    // Background adaptation follows the decision. A strong first sample can pass immediately.
    const double background = s.backgroundPower;
    if (!s.armed) {
        s.onsetPeak = std::max(s.onsetPeak, s.peakPower);
        if (s.peakPower <= s.onsetPeak * 0.25 ||
            s.peakPower < std::max(p.minimumPower * 0.5, background * p.rearmRatio)) s.armed = true;
    }
    if (s.armed && power >= p.minimumPower && power > background * p.onsetRatio) {
        s.remaining = p.duration; // Retrigger even while open; never wait for the previous window to end.
        ++s.detections; s.armed = false; s.onsetPeak = s.peakPower;
    }
    // Limit transient contamination of the noise estimate: dense taps must not become the background.
    // Sustained changes still adapt, but a brief impulse contributes at most 4x the current floor.
    const double backgroundTarget = std::min(power, std::max(p.minimumPower, background * 4));
    s.backgroundPower += p.backgroundAlpha * (backgroundTarget - s.backgroundPower);
    s.remaining = std::min(s.remaining, p.duration);
    if (s.remaining == 0) return 0;
    // Fade only inside the final 0.2 ms of the requested window; never delay the attack or extend the cut.
    const double gain = s.remaining <= p.fade ? double(s.remaining - 1) / p.fade : 1;
    --s.remaining;
    return input * gain;
}
inline double processTapGate(double input, bool enabled, const TapGateParameters &p, TapGateState &s) {
    return processTapGate(input, input, enabled, p, s);
}
inline double processTapGateWithSidechain(double raw, double filtered, bool afterFilters, bool enabled,
                                         const TapGateParameters &p, TapGateState &s) {
    if (!enabled) return filtered;
    return processTapGate(filtered, afterFilters ? filtered : raw, true, p, s);
}
}
