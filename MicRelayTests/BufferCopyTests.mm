// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
#import <XCTest/XCTest.h>
#include "../MicRelay/Audio/MRBufferCopy.hpp"

@interface BufferCopyTests : XCTestCase
@end
@implementation BufferCopyTests
- (void)testCircularCopyPreservesSamplesAndDestinationBounds {
    std::array<float, 128> source;
    for (size_t i = 0; i < source.size(); ++i) source[i] = float(i) / 8 - 4;
    source[3] = -0.0f;
    const uint32_t nan = 0x7fc01234;
    std::memcpy(&source[7], &nan, sizeof(nan));
    for (size_t start : {0, 1, 63, 127}) {
        for (size_t count : {0, 1, 16, 127, 128}) {
            std::array<float, 130> destination;
            destination.fill(999);
            mr::copyCircularSamples(source.data(), destination.data() + 1, source.size(), start, count);
            XCTAssertEqual(destination.front(), 999);
            for (size_t i = 0; i < count; ++i)
                XCTAssertEqual(std::memcmp(&destination[i + 1], &source[(start + i) % source.size()], sizeof(float)), 0);
            for (size_t i = count + 1; i < destination.size(); ++i) XCTAssertEqual(destination[i], 999);
        }
    }
}
- (void)testWaveformOrderCapacityAndIndexWrap {
    std::array<std::atomic<float>, 128> source;
    for (size_t i = 0; i < source.size(); ++i) source[i].store(float(i) * 1.25f - 64);
    for (uint32_t end : {0u, 1u, 127u, 128u, UINT32_MAX}) {
        for (size_t capacity : {0, 1, 16, 128, 129}) {
            std::array<float, 132> destination;
            destination.fill(999);
            const auto count = mr::readWaveform(source, end, destination.data() + 1, capacity);
            XCTAssertEqual(count, std::min(capacity, source.size()));
            XCTAssertEqual(destination.front(), 999);
            for (size_t i = 0; i < count; ++i)
                XCTAssertEqual(destination[i + 1], source[uint32_t(end + i) % source.size()].load());
            for (size_t i = count + 1; i < destination.size(); ++i) XCTAssertEqual(destination[i], 999);
        }
    }
}
@end
