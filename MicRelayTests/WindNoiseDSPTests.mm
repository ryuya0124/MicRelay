// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
#import <XCTest/XCTest.h>
#include "../MicRelay/Audio/MRWindNoiseDSP.hpp"
#include <complex>

static double windResponse(double frequency, double cutoff, double rate) {
    const auto z = std::polar(1.0, -2*M_PI*frequency/rate);
    std::complex<double> h = 1;
    for (const auto &c : mr::windCoefficients(cutoff,rate))
        h *= (c.b0+c.b1*z+c.b2*z*z)/(1.0+c.a1*z+c.a2*z*z);
    return 20*std::log10(std::abs(h));
}
@interface WindNoiseDSPTests : XCTestCase
@end
@implementation WindNoiseDSPTests
- (void)testOffBypassesExactlyWithoutAdvancingFilterState {
    std::array<mr::BiquadState,mr::windStageCount> states{};
    states[0].z1=0.37; states[0].z2=-0.1;
    states[1].target=mr::windCoefficients(120,48000)[1];
    for (double sample : {-1.0,-0.01,0.0,0.35,1.0})
        XCTAssertEqual(mr::processWindNoise(sample,false,states,0.004),sample);
    XCTAssertEqual(states[0].z1,0.37); XCTAssertEqual(states[0].z2,-0.1);
    XCTAssertEqual(states[1].current.b0,1);
}
- (void)testLowWindFrequenciesAreReducedWithoutCuttingTheVoiceMidrange {
    for (double rate : {8000.0,16000.0,44100.0,48000.0,96000.0,192000.0}) {
        XCTAssertEqualWithAccuracy(windResponse(120,120,rate),-3.01029995664,0.00001);
        XCTAssertLessThan(windResponse(30,120,rate),-48);
        XCTAssertLessThan(windResponse(40,120,rate),-38);
        XCTAssertGreaterThan(windResponse(1000,120,rate),-0.001);
        XCTAssertLessThan(windResponse(120,600,rate),-55);
    }
}
- (void)testMixedWindAndVoiceSignalAndImmediateImpulseOutput {
    constexpr double rate=48000;
    auto coeffs=mr::windCoefficients(120,rate);
    std::array<mr::BiquadState,mr::windStageCount> states{};
    for (size_t i=0;i<states.size();++i) states[i].current=states[i].target=coeffs[i];
    double lowSin=0,lowCos=0,voiceSin=0,voiceCos=0;
    // Discard one second of filter settling, measure an integer number of periods.
    for (int i=0;i<96000;++i) {
        const double low=2*M_PI*30*i/rate, voice=2*M_PI*1000*i/rate;
        const double y=mr::processWindNoise(0.5*std::sin(low)+0.25*std::sin(voice),true,states,1);
        if (i>=48000) { lowSin+=y*std::sin(low); lowCos+=y*std::cos(low); voiceSin+=y*std::sin(voice); voiceCos+=y*std::cos(voice); }
    }
    XCTAssertLessThan(std::hypot(lowSin,lowCos)*2/48000,0.002);
    XCTAssertEqualWithAccuracy(std::hypot(voiceSin,voiceCos)*2/48000,0.25,0.00001);
    states={};
    for (size_t i=0;i<states.size();++i) states[i].current=states[i].target=coeffs[i];
    // The first input sample already produces output: there is no look-ahead FIFO.
    XCTAssertGreaterThan(mr::processWindNoise(1,true,states,1),0.9);
}
- (void)testLiveCutoffChangesStayFiniteAcrossSupportedSampleRates {
    for (double rate : {8000.0,16000.0,44100.0,48000.0,96000.0,192000.0}) {
        std::array<mr::BiquadState,mr::windStageCount> states{};
        const double smoothing=1-std::exp(-1/(0.005*rate));
        bool finite=true; double peak=0;
        for (int block=0;block<50;++block) {
            auto coeffs=mr::windCoefficients(block%2 ? 60 : 600,rate);
            for (size_t i=0;i<states.size();++i) states[i].target=coeffs[i];
            for (int i=0;i<1024;++i) {
                double y=mr::processWindNoise(0.25*std::sin(2*M_PI*1000*(block*1024+i)/rate),true,states,smoothing);
                finite=finite && std::isfinite(y); peak=std::max(peak,std::abs(y));
            }
        }
        XCTAssertTrue(finite); XCTAssertLessThan(peak,0.5);
    }
}
@end
