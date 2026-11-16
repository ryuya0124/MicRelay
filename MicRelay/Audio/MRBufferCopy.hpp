// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
#pragma once
#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <cstdint>
#include <cstring>

namespace mr {
// Consumer-side copies only. The producer publishes its write position with release ordering.
inline void copyCircularSamples(const float *source, float *destination, size_t capacity, size_t start, size_t count) {
    assert(capacity > 0 && start < capacity && count <= capacity);
    if (count == 0) return;
    const auto first = std::min(count, capacity - start);
    std::memcpy(destination, source + start, first * sizeof(float));
    if (count > first) std::memcpy(destination + first, source, (count - first) * sizeof(float));
}

template<size_t N>
size_t readWaveform(const std::array<std::atomic<float>, N> &source, uint32_t end, float *destination, size_t capacity) {
    static_assert(N > 0 && (N & (N - 1)) == 0, "Waveform capacity must preserve uint32_t index wrap");
    const auto count = std::min(N, capacity);
    for (size_t i = 0; i < count; ++i)
        destination[i] = source[(uint64_t(end) + i) % N].load(std::memory_order_relaxed);
    return count;
}
}
