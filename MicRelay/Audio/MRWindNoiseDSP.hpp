// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
#pragma once
#include "MREqualizerDSP.hpp"

namespace mr {
constexpr size_t windStageCount = 2;
// Fourth-order Butterworth high-pass. Coefficients are computed off the audio thread.
// No look-ahead, FFT, delay line, or block accumulation.
inline std::array<Coefficients, windStageCount> windCoefficients(double cutoff, double rate) {
    std::array<Coefficients, windStageCount> result{};
    if (!std::isfinite(cutoff) || cutoff <= 0 || !std::isfinite(rate) || rate <= 0) return result;
    constexpr double q[] = {0.541196100146197, 1.306562964876377};
    for (size_t i=0;i<windStageCount;++i) {
        BandParameters p; p.type=FilterType::highPass;
        p.frequency=std::clamp(cutoff,1.0,std::max(1.0,rate*0.45)); p.q=q[i];
        result[i]=coefficients(p,rate);
    }
    return result;
}
inline double processWindNoise(double input, bool enabled, std::array<BiquadState,windStageCount> &states, double smoothing) {
    if (!enabled) return input;
    for (auto &state:states) input=processBand(input,state,smoothing);
    return input;
}
}
