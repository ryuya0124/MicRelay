// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

#pragma once
#include <algorithm>
#include <array>
#include <cmath>

namespace mr {
constexpr size_t bandCount = 6;
enum class FilterType : int { peak = 0, notch = 1, highPass = 2, lowPass = 3, bandStop = 4, bandPass = 5 };
struct BandParameters {
    double frequency = 1000, gainDB = 0, q = 1;
    FilterType type = FilterType::peak;
    bool enabled = true;
    double lowerFrequency = 300, upperFrequency = 3000;
};
struct Coefficients {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    bool active = false;
};
struct BiquadState {
    double z1 = 0, z2 = 0;
    Coefficients current, target;
};

// Normalized RBJ biquad equations; no look-ahead or block buffering.
inline Coefficients coefficients(BandParameters p, double rate) {
    Coefficients c;
    if (!p.enabled || !std::isfinite(rate) || rate <= 0 || !std::isfinite(p.frequency)) return c;
    if (p.type == FilterType::bandStop || p.type == FilterType::bandPass) {
        if (!std::isfinite(p.lowerFrequency) || !std::isfinite(p.upperFrequency) ||
            p.lowerFrequency <= 0 || p.upperFrequency <= p.lowerFrequency) return c;
        const double limit = rate * 0.5;
        if (p.lowerFrequency >= limit) {
            if (p.type == FilterType::bandPass) { c.b0 = 0; c.active = true; }
            return c;
        }
        if (p.upperFrequency >= limit) {
            // Only the lower edge is representable: use a single high/low cut.
            const double w = 2 * 3.14159265358979323846 * p.lowerFrequency / rate;
            const double cs = std::cos(w), alpha = std::sin(w) / std::sqrt(2.0), a0 = 1 + alpha;
            c.a1 = -2 * cs / a0; c.a2 = (1 - alpha) / a0;
            if (p.type == FilterType::bandPass) { c.b0 = (1 + cs) / (2 * a0); c.b1 = -2 * c.b0; }
            else { c.b0 = (1 - cs) / (2 * a0); c.b1 = 2 * c.b0; }
            c.b2 = c.b0; c.active = true;
            return c;
        } else {
            // Prewarp both -3 dB edges, then bilinear-transform the analog BPF/BSF.
            // One biquad per band; no extra samples, look-ahead, or playback buffer.
            constexpr double pi = 3.14159265358979323846;
            const double lo = std::tan(pi * p.lowerFrequency / rate), hi = std::tan(pi * p.upperFrequency / rate);
            const double product = lo * hi, width = hi - lo, a0 = 1 + width + product;
            c.a1 = 2 * (product - 1) / a0; c.a2 = (1 - width + product) / a0;
            if (p.type == FilterType::bandPass) { c.b0 = width / a0; c.b1 = 0; c.b2 = -c.b0; }
            else { c.b0 = (1 + product) / a0; c.b1 = c.a1; c.b2 = c.b0; }
            c.active = true;
            return c;
        }
    }
    if (p.frequency >= rate * 0.499) {
        if (p.type == FilterType::highPass) { c.b0 = 0; c.active = true; }
        return c;
    }
    if (p.type == FilterType::peak && std::abs(p.gainDB) < 0.00001) return c;
    const double frequency = std::clamp(p.frequency, 1.0, rate * 0.499);
    const double q = std::clamp(p.q, 0.2, 30.0);
    const double w = 2.0 * 3.14159265358979323846 * frequency / rate;
    const double cs = std::cos(w), sn = std::sin(w), alpha = sn / (2.0 * q);
    double b0, b1, b2, a0, a1 = -2 * cs, a2;
    if (p.type == FilterType::peak) {
        const double a = std::pow(10.0, std::clamp(p.gainDB, -36.0, 24.0) / 40.0);
        b0 = 1 + alpha * a; b1 = -2 * cs; b2 = 1 - alpha * a;
        a0 = 1 + alpha / a; a2 = 1 - alpha / a;
    } else {
        a0 = 1 + alpha; a2 = 1 - alpha;
        if (p.type == FilterType::notch) { b0 = 1; b1 = -2 * cs; b2 = 1; }
        else if (p.type == FilterType::highPass) { b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = b0; }
        else { b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = b0; }
    }
    c.b0 = b0 / a0; c.b1 = b1 / a0; c.b2 = b2 / a0;
    c.a1 = a1 / a0; c.a2 = a2 / a0; c.active = true;
    return c;
}

inline double processBand(double x, BiquadState &s, double smoothing) {
    if (!s.target.active) { s.z1 = 0; s.z2 = 0; s.current = s.target; return x; }
    auto &c = s.current;
    const auto &t = s.target;
    c.b0 += (t.b0 - c.b0) * smoothing; c.b1 += (t.b1 - c.b1) * smoothing;
    c.b2 += (t.b2 - c.b2) * smoothing; c.a1 += (t.a1 - c.a1) * smoothing;
    c.a2 += (t.a2 - c.a2) * smoothing;
    const double y = c.b0 * x + s.z1;
    s.z1 = c.b1 * x - c.a1 * y + s.z2;
    s.z2 = c.b2 * x - c.a2 * y;
    if (!std::isfinite(y)) { s.z1 = 0; s.z2 = 0; return 0; }
    if (std::abs(s.z1) < 1e-24) s.z1 = 0;
    if (std::abs(s.z2) < 1e-24) s.z2 = 0;
    return y;
}

inline double processEqualizer(double x, bool enabled, std::array<BiquadState, bandCount> &states, double smoothing) {
    if (!enabled) return x; // Hard bypass: no biquad state is read or advanced.
    for (auto &state : states) x = processBand(x, state, smoothing);
    return x;
}
}
