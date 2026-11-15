// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Owns RemoteIO. All control methods are called on the main thread.
/// closeGate is safe from any notification thread and never waits for the UI.
@interface MRRealtimeAudio : NSObject
- (BOOL)prepareWithSampleRate:(double)sampleRate error:(NSError **)error;
- (BOOL)startWithError:(NSError **)error;
- (void)closeGate;
- (void)stop;
@property(nonatomic) double gain;
@property(nonatomic, readonly) float peak;
@property(nonatomic, readonly) uint64_t renderedFrames;
@property(nonatomic, readonly) int32_t renderError;
- (NSArray<NSNumber *> *)waveform;
@property(nonatomic, readonly) float maximumInputPeak;
@property(nonatomic, readonly) float maximumOutputPeak;
@property(nonatomic, readonly) uint64_t missedQuanta;
@property(nonatomic, readonly) uint32_t minimumQuantum;
@property(nonatomic, readonly) uint32_t maximumQuantum;
@property(nonatomic, readonly) uint32_t currentQuantum;
@property(nonatomic, readonly) uint64_t callbackCount;
@property(nonatomic) BOOL outputMuted;
- (void)resetQuantumStatistics;
- (void)setWindNoiseEnabled:(BOOL)enabled cutoff:(double)cutoff;
- (void)setEqualizerEnabled:(BOOL)enabled bands:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)bands;
@property(nonatomic) BOOL analysisEnabled;
- (NSUInteger)readAnalysisInput:(float *)input output:(float *)output capacity:(NSUInteger)capacity;
- (void)discardAnalysisSamples;
@property(nonatomic, readonly) uint64_t analysisDroppedFrames;
@end
NS_ASSUME_NONNULL_END
