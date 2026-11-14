// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
#import <XCTest/XCTest.h>
#include "../MicRelay/Audio/MREqualizerDSP.hpp"

static double response(mr::FilterType type, double center, double signal, double gain = 0) {
    std::array<mr::BiquadState, mr::bandCount> states{};
    mr::BandParameters p; p.type = type; p.frequency = center; p.gainDB = gain;
    states[0].current = states[0].target = mr::coefficients(p, 48000);
    double input = 0, output = 0;
    for (int i = 0; i < 96000; ++i) {
        double x = 0.1 * std::sin(2 * M_PI * signal * i / 48000);
        double y = mr::processEqualizer(x, true, states, 1);
        if (i >= 48000) { input += x*x; output += y*y; }
    }
    return 10 * std::log10(std::max(output / input, 1e-30));
}

@interface EqualizerDSPTests : XCTestCase
@end
@implementation EqualizerDSPTests
- (void)testHardBypassPreservesSamplesAndState {
    std::array<mr::BiquadState, mr::bandCount> states{};
    states[0].z1 = 123; states[0].z2 = -456;
    states[0].target.active = true;
    for (double value : {-1.0, -0.123456789, 0.0, 0.875, 1.0}) {
        XCTAssertEqual(mr::processEqualizer(value, false, states, 0.01), value);
    }
    XCTAssertEqual(states[0].z1, 123);
    XCTAssertEqual(states[0].z2, -456);
}
- (void)testPeakingGainAtCenter {
    XCTAssertEqualWithAccuracy(response(mr::FilterType::peak, 1000, 1000, -18), -18, 0.02);
    XCTAssertEqualWithAccuracy(response(mr::FilterType::peak, 1000, 1000, 12), 12, 0.02);
}
- (void)testNotchAndCuts {
    XCTAssertLessThan(response(mr::FilterType::notch, 1000, 1000), -100);
    XCTAssertLessThan(response(mr::FilterType::highPass, 1000, 100), -35);
    XCTAssertLessThan(response(mr::FilterType::lowPass, 1000, 10000), -35);
    XCTAssertGreaterThan(response(mr::FilterType::highPass, 1000, 10000), -0.1);
}
@end
