// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
#import <XCTest/XCTest.h>
#include "../MicRelay/Audio/MRTapGateDSP.hpp"
#include "../MicRelay/Audio/MREqualizerDSP.hpp"
#include <vector>

@interface TapGateDSPTests : XCTestCase
@end
@implementation TapGateDSPTests
- (void)testLowPassAndBandPassCanUseRawOnsetWithoutRestoringCutFrequencies {
    for (auto filter : {mr::FilterType::lowPass,mr::FilterType::bandPass}) {
        mr::BandParameters band; band.type=filter; band.frequency=300;
        band.lowerFrequency=800; band.upperFrequency=1200;
        mr::BiquadState eq; eq.current=eq.target=mr::coefficients(band,48000);
        auto p=mr::tapGateParameters(48000,0.012,-20,16);
        mr::TapGateState before,after;
        for (int i=0;i<1000;++i) {
            const double raw=i==0 ? 0.25 : 0;
            const double filtered=mr::processBand(raw,eq,1);
            const double pre=mr::processTapGateWithSidechain(raw,filtered,false,true,p,before);
            const double post=mr::processTapGateWithSidechain(raw,filtered,true,true,p,after);
            if (i==0) {
                XCTAssertGreaterThan(std::abs(filtered),0);
                XCTAssertLessThan(std::abs(filtered),0.1);
                XCTAssertEqual(pre,filtered); // First filtered sample passes immediately; raw audio never leaks.
                XCTAssertNotEqual(pre,raw);
            }
            XCTAssertEqual(post,0); // This filtered signal never reaches the chosen minimum.
        }
        XCTAssertEqual(before.detections,1u); XCTAssertEqual(after.detections,0u);
    }
}
- (void)testFilteredDetectionCanTriggerOnEQBoostAndDisabledGateAlwaysReturnsFilteredAudio {
    auto p=mr::tapGateParameters(48000,0.012,-40,16);
    mr::TapGateState before,after;
    XCTAssertEqual(mr::processTapGateWithSidechain(0.002,0.02,false,true,p,before),0);
    XCTAssertEqual(mr::processTapGateWithSidechain(0.002,0.02,true,true,p,after),0.02);
    const auto count=after.detections;
    const auto remaining=after.remaining;
    XCTAssertEqual(mr::processTapGateWithSidechain(0.3,0.001,false,false,p,after),0.001);
    XCTAssertEqual(after.detections,count); XCTAssertEqual(after.remaining,remaining);
}
- (void)testOffIsExactBypassWithoutAdvancingDetectorOrWindow {
    auto p = mr::tapGateParameters(48000,0.012,-42,16);
    mr::TapGateState s; s.remaining=17; s.backgroundPower=0.003; s.peakPower=0.007; s.detections=9; s.armed=false;
    for (double x : {-0.73,0.0,0.001,0.8}) XCTAssertEqual(mr::processTapGate(x,false,p,s),x);
    XCTAssertEqual(s.remaining,17u); XCTAssertEqual(s.backgroundPower,0.003);
    XCTAssertEqual(s.peakPower,0.007); XCTAssertEqual(s.detections,9u); XCTAssertFalse(s.armed);
}
- (void)testFirstAboveThresholdSamplePassesImmediatelyAndSustainedSoundIsCutOnTime {
    for (double rate : {8000.0,44100.0,48000.0,96000.0,192000.0,384000.0}) {
        auto p=mr::tapGateParameters(rate,0.012,-42,16); mr::TapGateState s;
        // No preceding samples, FFT window, block fill, attack ramp, or look-ahead are needed.
        XCTAssertEqual(mr::processTapGate(0.25,true,p,s),0.25);
        for (uint32_t i=1;i<p.duration;++i) {
            const double y=mr::processTapGate(0.25,true,p,s);
            if (i < p.duration-p.fade) XCTAssertEqual(y,0.25);
            else XCTAssertGreaterThanOrEqual(y,0);
        }
        XCTAssertEqual(s.remaining,0u);
        for (int i=0;i<int(rate*0.2);++i) XCTAssertEqual(mr::processTapGate(0.25,true,p,s),0);
        XCTAssertEqual(s.detections,1u);
    }
}
- (void)testWeakAttacksMustCrossThresholdAndAreNeverReplayedLater {
    auto p=mr::tapGateParameters(48000,0.005,-30,16); mr::TapGateState s;
    XCTAssertEqual(mr::processTapGate(0.001,true,p,s),0);
    XCTAssertEqual(mr::processTapGate(0.01,true,p,s),0);
    XCTAssertEqual(mr::processTapGate(0.1,true,p,s),0.1);
    XCTAssertEqual(s.detections,1u);
}
- (void)testRapidTapsRetriggerDuringAnOpenWindowAcrossSampleRates {
    for (double rate : {8000.0,44100.0,48000.0,96000.0,192000.0,384000.0}) {
        auto p=mr::tapGateParameters(rate,0.012,-42,16); mr::TapGateState s;
        const int period=int(rate*0.002), taps=100; // Synthetic stress test: 500 onsets/second.
        uint32_t random=1;
        auto noise=[&] { random=1664525*random+1013904223; return (double(random)/UINT32_MAX*2-1)*0.002; };
        for (int i=0;i<int(rate);++i) mr::processTapGate(noise(),true,p,s);
        const uint64_t before=s.detections;
        for (int i=0;i<taps*period;++i) {
            const double x = i%period==0 ? 0.25 : noise();
            const double y=mr::processTapGate(x,true,p,s);
            if (i%period==0) XCTAssertEqual(y,x); // No missing first sample, including inside the preceding window.
        }
        XCTAssertEqual(s.detections-before,uint64_t(taps));
        const int tail=int(p.duration)-period;
        for (int i=0;i<tail;++i) mr::processTapGate(noise(),true,p,s);
        XCTAssertEqual(s.remaining,0u);
        for (int i=0;i<int(rate*0.05);++i) XCTAssertEqual(mr::processTapGate(noise(),true,p,s),0);
    }
}
- (void)testContinuousBackgroundStaysClosedAndTapsPassAtTheirOriginalIndices {
    constexpr double rate=48000;
    auto p=mr::tapGateParameters(rate,0.005,-42,16); mr::TapGateState s;
    uint32_t random=73;
    std::vector<int> detected;
    for (int i=0;i<48000*3;++i) {
        random=1664525*random+1013904223;
        const double noise=0.006*std::sin(2*3.141592653589793*120*i/rate)+(double(random)/UINT32_MAX*2-1)*0.002;
        const bool tap=i==60000 || i==72000 || i==72144; // Includes a 3 ms double tap.
        const double x=tap ? 0.3 : noise;
        const auto before=s.detections;
        const double y=mr::processTapGate(x,true,p,s);
        if (s.detections!=before) detected.push_back(i);
        if (tap) XCTAssertEqual(y,x);
        if (i>48000 && !tap && s.remaining==0) XCTAssertEqual(y,0);
    }
    XCTAssertEqual(detected.size(),3u);
    if (detected.size()==3) { XCTAssertEqual(detected[0],60000); XCTAssertEqual(detected[1],72000); XCTAssertEqual(detected[2],72144); }
}
- (void)testRenderingInDifferentBlockSizesProducesIdenticalSamplesAndDetectionCounts {
    auto p=mr::tapGateParameters(44100,0.007,-42,16);
    std::vector<double> input(4410), reference(input.size());
    for (size_t i=0;i<input.size();++i) input[i]=i%173==0 ? 0.2 : 0.001*std::sin(i*0.2);
    mr::TapGateState a;
    for (size_t i=0;i<input.size();++i) reference[i]=mr::processTapGate(input[i],true,p,a);
    for (size_t block : {1u,16u,44u,45u,512u,2048u}) {
        mr::TapGateState b;
        for (size_t start=0;start<input.size();start+=block)
            for (size_t i=start;i<std::min(start+block,input.size());++i)
                XCTAssertEqual(mr::processTapGate(input[i],true,p,b),reference[i]);
        XCTAssertEqual(a.detections,b.detections); XCTAssertEqual(a.remaining,b.remaining);
    }
}
- (void)testLiveParameterChangesAndNonfiniteInputRecoverWithoutOutputtingOldAudio {
    mr::TapGateState s;
    auto p=mr::tapGateParameters(48000,1,-42,16);
    XCTAssertEqual(mr::processTapGate(0.5,true,p,s),0.5);
    p=mr::tapGateParameters(48000,0.001,-90,3);
    for (int i=0;i<100;++i) XCTAssertTrue(std::isfinite(mr::processTapGate(0,true,p,s)));
    XCTAssertEqual(s.remaining,0u);
    XCTAssertEqual(mr::processTapGate(NAN,true,p,s),0);
    XCTAssertEqual(mr::processTapGate(INFINITY,true,p,s),0);
    XCTAssertEqual(mr::processTapGate(-0.5,true,p,s),-0.5);
}
@end
