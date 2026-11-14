// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
#import <XCTest/XCTest.h>
#include "../MicRelay/Audio/MREqualizerDSP.hpp"
#include <complex>

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


static std::complex<double> transfer(const mr::Coefficients &c, double frequency, double rate) {
    auto z = std::exp(std::complex<double>(0, -2 * M_PI * frequency / rate));
    return (c.b0 + c.b1*z + c.b2*z*z) / (1.0 + c.a1*z + c.a2*z*z);
}
static double signalResponse(mr::BandParameters parameters, double signal, double rate = 48000) {
    std::array<mr::BiquadState, mr::bandCount> states{};
    states[0].current = states[0].target = mr::coefficients(parameters, rate);
    double input = 0, output = 0;
    for (int i = 0; i < int(rate * 2); ++i) {
        double x = 0.1 * std::sin(2 * M_PI * signal * i / rate);
        double y = mr::processEqualizer(x, true, states, 1);
        if (i >= int(rate)) { input += x*x; output += y*y; }
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

- (void)testRangeFiltersHaveExactEdgesAndComplementaryResponses {
    for (double rate : {8000.0, 16000.0, 44100.0, 48000.0, 96000.0, 192000.0}) {
        mr::BandParameters p; p.lowerFrequency = 300; p.upperFrequency = 2500;
        p.type = mr::FilterType::bandPass; auto pass = mr::coefficients(p, rate);
        p.type = mr::FilterType::bandStop; auto stop = mr::coefficients(p, rate);
        for (double edge : {p.lowerFrequency, p.upperFrequency}) {
            XCTAssertEqualWithAccuracy(20*std::log10(std::abs(transfer(pass,edge,rate))), -3.01029995664, 0.00001);
            XCTAssertEqualWithAccuracy(20*std::log10(std::abs(transfer(stop,edge,rate))), -3.01029995664, 0.00001);
        }
        for (double fraction : {0.001,0.01,0.05,0.1,0.25,0.49}) {
            XCTAssertLessThan(std::abs(transfer(pass,rate*fraction,rate) + transfer(stop,rate*fraction,rate) - 1.0), 1e-9);
        }
    }
}
- (void)testRangeFiltersProcessTheRequestedBand {
    mr::BandParameters p; p.lowerFrequency = 500; p.upperFrequency = 2000;
    const double center = 48000/M_PI * std::atan(std::sqrt(std::tan(M_PI*500/48000)*std::tan(M_PI*2000/48000)));
    p.type = mr::FilterType::bandPass;
    XCTAssertEqualWithAccuracy(signalResponse(p,center), 0, 0.001);
    XCTAssertLessThan(signalResponse(p,50), -20);
    XCTAssertLessThan(signalResponse(p,15000), -20);
    p.type = mr::FilterType::bandStop;
    XCTAssertLessThan(signalResponse(p,center), -100);
    XCTAssertGreaterThan(signalResponse(p,50), -0.1);
    XCTAssertGreaterThan(signalResponse(p,15000), -0.1);
}
- (void)testRangeFiltersHandleLowSampleRateAndUnrepresentableBands {
    mr::BandParameters p; p.lowerFrequency = 500; p.upperFrequency = 12000;
    p.type = mr::FilterType::bandPass;
    XCTAssertEqualWithAccuracy(signalResponse(p,500,8000), -3.0103, 0.001);
    XCTAssertLessThan(signalResponse(p,50,8000), -35);
    p.type = mr::FilterType::bandStop;
    XCTAssertEqualWithAccuracy(signalResponse(p,500,8000), -3.0103, 0.001);
    XCTAssertLessThan(signalResponse(p,3500,8000), -35);
    p.lowerFrequency = 6000; p.upperFrequency = 12000;
    XCTAssertFalse(mr::coefficients(p,8000).active);
    p.type = mr::FilterType::bandPass;
    auto muted = mr::coefficients(p,8000);
    XCTAssertTrue(muted.active); XCTAssertEqual(muted.b0,0);
    p.lowerFrequency = 3992; p.upperFrequency = 12000;
    XCTAssertEqualWithAccuracy(20*std::log10(std::abs(transfer(mr::coefficients(p,8000),3992,8000))), -3.01029995664, 0.00001);
    p.lowerFrequency = 500; p.upperFrequency = 3992;
    XCTAssertEqualWithAccuracy(20*std::log10(std::abs(transfer(mr::coefficients(p,8000),3992,8000))), -3.01029995664, 0.00001);
}
- (void)testNarrowAndWideRangeFiltersStayFiniteAndStable {
    for (auto type : {mr::FilterType::bandPass,mr::FilterType::bandStop}) {
        for (auto range : {std::pair{20.0,21.0},std::pair{19999.0,20000.0},std::pair{20.0,20000.0}}) {
            mr::BandParameters p; p.type=type; p.lowerFrequency=range.first; p.upperFrequency=range.second;
            std::array<mr::BiquadState,mr::bandCount> states{};
            auto c = mr::coefficients(p,48000); states[0].current=states[0].target=c;
            XCTAssertTrue(std::abs(c.a2)<1 && 1+c.a1+c.a2>0 && 1-c.a1+c.a2>0);
            bool finite = true; double peak = 0;
            for (int i=0;i<48000;++i) {
                double y=mr::processEqualizer(i==0 ? 1 : 0,true,states,1);
                finite = finite && std::isfinite(y); peak = std::max(peak,std::abs(y));
            }
            XCTAssertTrue(finite); XCTAssertLessThanOrEqual(peak,1.000001);
        }
    }
}
@end
