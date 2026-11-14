// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

#import "MRRealtimeAudio.h"
#import <AVFAudio/AVFAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <vector>
#include <array>
#include "MREqualizerDSP.hpp"

static_assert(std::atomic<float>::is_always_lock_free);
static_assert(std::atomic<double>::is_always_lock_free);
static_assert(std::atomic<uint64_t>::is_always_lock_free);

struct CoefficientMailbox {
    std::atomic<double> b0{1}, b1{0}, b2{0}, a1{0}, a2{0};
    std::atomic<bool> active{false};
};
constexpr uint64_t analysisCapacity = 32768;

struct RealtimeState {
    AudioUnit unit = nullptr;
    std::atomic<bool> open{false};
    std::atomic<double> gain{0.5};
    std::atomic<float> peak{0};
    std::atomic<uint64_t> frames{0};
    std::atomic<int32_t> error{0};
    std::vector<float> input;
    double smoothedGain = 0;
    std::array<std::atomic<float>, 128> wave{};
    std::atomic<uint32_t> waveIndex{0};
    std::atomic<float> maxInput{0}, maxOutput{0};
    UInt32 waveStride = 60, waveCount = 0;
    float wavePeak = 0;
    UInt32 consecutiveMisses = 0;
    std::atomic<uint64_t> misses{0};
    std::atomic<uint32_t> minQuantum{UINT32_MAX}, maxQuantum{0};
    std::atomic<uint32_t> currentQuantum{0};
    std::atomic<uint64_t> callbacks{0};
    std::atomic<bool> eqEnabled{false}, analysisEnabled{false};
    std::atomic<uint64_t> eqSequence{0};
    std::array<CoefficientMailbox, mr::bandCount> eqMailbox;
    std::array<mr::BiquadState, mr::bandCount> eqStates;
    uint64_t eqVersion = UINT64_MAX;
    bool eqWasEnabled = false;
    double eqSmoothing = 0.004, rate = 48000;
    std::array<float, analysisCapacity> analysisInput{}, analysisOutput{};
    std::atomic<uint64_t> analysisRead{0}, analysisWrite{0}, analysisDrops{0};
};

static void syncEqualizer(RealtimeState &s) {
    const uint64_t version = s.eqSequence.load(std::memory_order_acquire);
    if ((version & 1) || version == s.eqVersion) return;
    std::array<mr::Coefficients, mr::bandCount> values;
    for (size_t i = 0; i < mr::bandCount; ++i) {
        const auto &m = s.eqMailbox[i]; auto &v = values[i];
        v.b0 = m.b0.load(std::memory_order_relaxed); v.b1 = m.b1.load(std::memory_order_relaxed);
        v.b2 = m.b2.load(std::memory_order_relaxed); v.a1 = m.a1.load(std::memory_order_relaxed);
        v.a2 = m.a2.load(std::memory_order_relaxed); v.active = m.active.load(std::memory_order_relaxed);
    }
    std::atomic_thread_fence(std::memory_order_acquire);
    if (s.eqSequence.load(std::memory_order_relaxed) != version) return;
    for (size_t i = 0; i < mr::bandCount; ++i) s.eqStates[i].target = values[i];
    s.eqVersion = version;
}

static void silence(AudioBufferList *data, AudioUnitRenderActionFlags *flags) {
    if (data) for (UInt32 i = 0; i < data->mNumberBuffers; ++i)
        if (data->mBuffers[i].mData) memset(data->mBuffers[i].mData, 0, data->mBuffers[i].mDataByteSize);
    *flags |= kAudioUnitRenderAction_OutputIsSilence;
}

static OSStatus render(void *context, AudioUnitRenderActionFlags *flags,
                       const AudioTimeStamp *time, UInt32 bus, UInt32 count, AudioBufferList *output) {
    auto &s = *static_cast<RealtimeState *>(context);
    s.callbacks.fetch_add(1, std::memory_order_relaxed);
    s.currentQuantum.store(count, std::memory_order_relaxed);
    s.minQuantum.store(std::min(count, s.minQuantum.load(std::memory_order_relaxed)), std::memory_order_relaxed);
    s.maxQuantum.store(std::max(count, s.maxQuantum.load(std::memory_order_relaxed)), std::memory_order_relaxed);
    if (!output || !s.open.load(std::memory_order_acquire)) {
        silence(output, flags); return noErr;
    }
    if (count > s.input.size()) {
        s.error.store(kAudioUnitErr_TooManyFramesToProcess);
        s.open.store(false); silence(output, flags); return noErr;
    }
    AudioBufferList input = {1, {{1, count * UInt32(sizeof(float)), s.input.data()}}};
    AudioUnitRenderActionFlags inputFlags = 0;
    OSStatus status = AudioUnitRender(s.unit, &inputFlags, time, 1, count, &input);
    if (status != noErr) {
        s.misses.fetch_add(1, std::memory_order_relaxed);
        // RemoteIO can report a transient missing input quantum during startup.
        // Drop only that quantum, without queuing older audio or adding buffering.
        if (status != kAudioUnitErr_CannotDoInCurrentContext || ++s.consecutiveMisses > 128) {
            s.error.store(status); s.open.store(false);
        }
        silence(output, flags); return noErr;
    }
    s.consecutiveMisses = 0;
    const double target = s.gain.load(std::memory_order_relaxed);
    const bool eqOn = s.eqEnabled.load(std::memory_order_acquire);
    if (eqOn) {
        if (!s.eqWasEnabled) { s.eqStates = {}; s.eqVersion = UINT64_MAX; }
        syncEqualizer(s);
    }
    s.eqWasEnabled = eqOn;
    const uint64_t write = s.analysisWrite.load(std::memory_order_relaxed);
    const bool wantsAnalysis = s.analysisEnabled.load(std::memory_order_relaxed);
    const bool capture = wantsAnalysis && write - s.analysisRead.load(std::memory_order_acquire) + count <= analysisCapacity;
    if (wantsAnalysis && !capture) s.analysisDrops.fetch_add(count, std::memory_order_relaxed);
    float peak = 0, outputPeak = 0;
    for (UInt32 frame = 0; frame < count; ++frame) {
        const float sample = s.input[frame];
        peak = std::max(peak, std::abs(sample));
        s.smoothedGain += (target - s.smoothedGain) * 0.004f;
        const double processed = mr::processEqualizer(double(sample), eqOn, s.eqStates, s.eqSmoothing);
        const float value = float(std::clamp(processed * s.smoothedGain, -1.0, 1.0));
        if (capture) {
            const auto slot = (write + frame) & (analysisCapacity - 1);
            s.analysisInput[slot] = sample;
            s.analysisOutput[slot] = float(processed);
        }
        outputPeak = std::max(outputPeak, std::abs(value));
        if (std::abs(sample) > std::abs(s.wavePeak)) s.wavePeak = sample;
        if (++s.waveCount >= s.waveStride) {
            const auto index = s.waveIndex.load(std::memory_order_relaxed);
            s.wave[index % 128].store(s.wavePeak, std::memory_order_relaxed);
            s.waveIndex.store(index + 1, std::memory_order_release);
            s.wavePeak = 0; s.waveCount = 0;
        }
        for (UInt32 i = 0; i < output->mNumberBuffers; ++i) {
            auto &buffer = output->mBuffers[i];
            auto *samples = static_cast<float *>(buffer.mData);
            if (samples && (frame + 1) * buffer.mNumberChannels * sizeof(float) <= buffer.mDataByteSize)
                for (UInt32 channel = 0; channel < buffer.mNumberChannels; ++channel)
                    samples[frame * buffer.mNumberChannels + channel] = value;
        }
    }
    if (capture) s.analysisWrite.store(write + count, std::memory_order_release);
    // A route/interruption notification can close the gate while input is rendering.
    if (!s.open.load(std::memory_order_acquire)) silence(output, flags);
    s.peak.store(peak, std::memory_order_relaxed);
    s.maxInput.store(std::max(peak, s.maxInput.load(std::memory_order_relaxed)), std::memory_order_relaxed);
    s.maxOutput.store(std::max(outputPeak, s.maxOutput.load(std::memory_order_relaxed)), std::memory_order_relaxed);
    s.frames.fetch_add(count, std::memory_order_relaxed);
    return noErr;
}

@implementation MRRealtimeAudio {
    RealtimeState _state;
    NSArray *_observers;
    std::array<mr::BandParameters, mr::bandCount> _eqParameters;
}
- (instancetype)init {
    if ((self = [super init])) {
        __weak MRRealtimeAudio *weakSelf = self;
        NSMutableArray *tokens = [NSMutableArray array];
        for (NSNotificationName name in @[AVAudioSessionRouteChangeNotification,
                AVAudioSessionInterruptionNotification, AVAudioSessionMediaServicesWereLostNotification,
                AVAudioSessionMediaServicesWereResetNotification]) {
            [tokens addObject:[[NSNotificationCenter defaultCenter] addObserverForName:name
                object:nil queue:nil usingBlock:^(NSNotification *note) { [weakSelf closeGate]; }]];
        }
        _observers = tokens;
    }
    return self;
}
- (void)dealloc {
    for (id observer in _observers) [[NSNotificationCenter defaultCenter] removeObserver:observer];
    [self stop];
}
- (BOOL)fail:(OSStatus)status error:(NSError **)error {
    if (status == noErr) return NO;
    if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    [self stop]; return YES;
}
- (BOOL)prepareWithSampleRate:(double)sampleRate error:(NSError **)error {
    [self stop];
    AudioComponentDescription desc = {kAudioUnitType_Output, kAudioUnitSubType_RemoteIO,
        kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(nullptr, &desc);
    if (!component) { [self fail:kAudio_ParamError error:error]; return NO; }
    if ([self fail:AudioComponentInstanceNew(component, &_state.unit) error:error]) return NO;
    UInt32 enabled = 1;
    if ([self fail:AudioUnitSetProperty(_state.unit, kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Input, 1, &enabled, sizeof(enabled)) error:error]) return NO;
    UInt32 allocateInput = 0;
    if ([self fail:AudioUnitSetProperty(_state.unit, kAudioUnitProperty_ShouldAllocateBuffer,
        kAudioUnitScope_Output, 1, &allocateInput, sizeof(allocateInput)) error:error]) return NO;
    AudioStreamBasicDescription format = {};
    format.mSampleRate = sampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    format.mFramesPerPacket = 1;
    format.mBitsPerChannel = 32;
    format.mChannelsPerFrame = 1;
    format.mBytesPerFrame = format.mBytesPerPacket = sizeof(float);
    if ([self fail:AudioUnitSetProperty(_state.unit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Output, 1, &format, sizeof(format)) error:error]) return NO;
    format.mChannelsPerFrame = 2;
    format.mBytesPerFrame = format.mBytesPerPacket = 2 * sizeof(float);
    if ([self fail:AudioUnitSetProperty(_state.unit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input, 0, &format, sizeof(format)) error:error]) return NO;
    UInt32 maxFrames = 0, size = sizeof(maxFrames);
    if ([self fail:AudioUnitGetProperty(_state.unit, kAudioUnitProperty_MaximumFramesPerSlice,
        kAudioUnitScope_Global, 0, &maxFrames, &size) error:error]) return NO;
    _state.input.assign(std::max(maxFrames, UInt32(4096)), 0);
    _state.rate = sampleRate;
    _state.eqSmoothing = 1 - std::exp(-1.0 / (0.005 * sampleRate));
    _state.eqStates = {}; _state.eqWasEnabled = false; _state.eqVersion = UINT64_MAX;
    [self publishEqualizer];
    _state.frames.store(0); _state.error.store(0); _state.smoothedGain = 0;
    _state.maxInput.store(0); _state.maxOutput.store(0); _state.waveIndex.store(0);
    _state.waveStride = std::max(UInt32(1), UInt32(sampleRate / 800));
    _state.waveCount = 0; _state.wavePeak = 0;
    _state.consecutiveMisses = 0;
    _state.misses.store(0);
    _state.callbacks.store(0); _state.minQuantum.store(UINT32_MAX); _state.maxQuantum.store(0); _state.currentQuantum.store(0);
    for (auto &sample : _state.wave) sample.store(0);
    AURenderCallbackStruct callback = {render, &_state};
    if ([self fail:AudioUnitSetProperty(_state.unit, kAudioUnitProperty_SetRenderCallback,
        kAudioUnitScope_Input, 0, &callback, sizeof(callback)) error:error]) return NO;
    if ([self fail:AudioUnitInitialize(_state.unit) error:error]) return NO;
    return YES;
}
- (BOOL)startWithError:(NSError **)error {
    if (!_state.unit) { [self fail:kAudioUnitErr_Uninitialized error:error]; return NO; }
    _state.open.store(true, std::memory_order_release);
    if ([self fail:AudioOutputUnitStart(_state.unit) error:error]) return NO;
    return YES;
}
- (void)closeGate { _state.open.store(false, std::memory_order_release); }
- (void)stop {
    [self closeGate];
    if (_state.unit) {
        AudioOutputUnitStop(_state.unit);
        AudioUnitUninitialize(_state.unit);
        AudioComponentInstanceDispose(_state.unit);
        _state.unit = nullptr;
    }
    _state.peak.store(0);
}
- (void)setGain:(double)value { _state.gain.store(std::isfinite(value) ? std::max(0.0, value) : 0.0); }
- (double)gain { return _state.gain.load(); }
- (float)peak { return _state.peak.load(); }
- (uint64_t)renderedFrames { return _state.frames.load(); }
- (int32_t)renderError { return _state.error.load(); }
- (float)maximumInputPeak { return _state.maxInput.load(); }
- (float)maximumOutputPeak { return _state.maxOutput.load(); }
- (uint64_t)missedQuanta { return _state.misses.load(); }
- (uint32_t)minimumQuantum { const auto value = _state.minQuantum.load(); return value == UINT32_MAX ? 0 : value; }
- (uint32_t)maximumQuantum { return _state.maxQuantum.load(); }
- (uint32_t)currentQuantum { return _state.currentQuantum.load(); }
- (uint64_t)callbackCount { return _state.callbacks.load(); }
- (void)publishEqualizer {
    _state.eqSequence.fetch_add(1, std::memory_order_acq_rel);
    for (size_t i = 0; i < mr::bandCount; ++i) {
        const auto c = mr::coefficients(_eqParameters[i], _state.rate);
        auto &m = _state.eqMailbox[i];
        m.b0.store(c.b0, std::memory_order_relaxed); m.b1.store(c.b1, std::memory_order_relaxed);
        m.b2.store(c.b2, std::memory_order_relaxed); m.a1.store(c.a1, std::memory_order_relaxed);
        m.a2.store(c.a2, std::memory_order_relaxed); m.active.store(c.active, std::memory_order_relaxed);
    }
    _state.eqSequence.fetch_add(1, std::memory_order_release);
}
- (void)setEqualizerEnabled:(BOOL)enabled bands:(NSArray<NSDictionary<NSString *,NSNumber *> *> *)bands {
    if (!enabled) _state.eqEnabled.store(false, std::memory_order_release);
    for (size_t i = 0; i < mr::bandCount; ++i) {
        mr::BandParameters p;
        if (i < bands.count) {
            NSDictionary *band = bands[i];
            p.frequency = [band[@"frequency"] doubleValue]; p.gainDB = [band[@"gainDB"] doubleValue];
            p.q = [band[@"q"] doubleValue]; p.type = mr::FilterType([band[@"type"] intValue]);
            p.enabled = [band[@"enabled"] boolValue];
        } else { p.enabled = false; }
        _eqParameters[i] = p;
    }
    [self publishEqualizer];
    _state.eqEnabled.store(enabled, std::memory_order_release);
}
- (void)setAnalysisEnabled:(BOOL)value { _state.analysisEnabled.store(value, std::memory_order_release); }
- (BOOL)analysisEnabled { return _state.analysisEnabled.load(std::memory_order_acquire); }
- (void)discardAnalysisSamples { _state.analysisRead.store(_state.analysisWrite.load(std::memory_order_acquire), std::memory_order_release); }
- (NSUInteger)readAnalysisInput:(float *)input output:(float *)output capacity:(NSUInteger)capacity {
    const uint64_t read = _state.analysisRead.load(std::memory_order_relaxed);
    const uint64_t write = _state.analysisWrite.load(std::memory_order_acquire);
    const NSUInteger count = NSUInteger(std::min(uint64_t(capacity), write - read));
    for (NSUInteger i = 0; i < count; ++i) {
        const auto slot = (read + i) & (analysisCapacity - 1);
        input[i] = _state.analysisInput[slot]; output[i] = _state.analysisOutput[slot];
    }
    _state.analysisRead.store(read + count, std::memory_order_release);
    return count;
}
- (uint64_t)analysisDroppedFrames { return _state.analysisDrops.load(); }
- (NSArray<NSNumber *> *)waveform {
    const auto end = _state.waveIndex.load(std::memory_order_acquire);
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:128];
    for (uint32_t i = 0; i < 128; ++i)
        [values addObject:@(_state.wave[(end + i) % 128].load(std::memory_order_relaxed))];
    return values;
}
@end
