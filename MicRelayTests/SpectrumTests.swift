// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import XCTest
import Accelerate
@testable import MicRelay

final class SpectrumTests: XCTestCase {
    func testNativeWaveformReadPreservesDestinationBounds() {
        let audio = MRRealtimeAudio()
        var samples = [Float](repeating: 99, count: 132)
        let count = samples.withUnsafeMutableBufferPointer { buffer in
            audio.readWaveform(buffer.baseAddress! + 2, capacity: 128)
        }
        XCTAssertEqual(count, 128)
        XCTAssertEqual(Array(samples.prefix(2)), [99, 99])
        XCTAssertTrue(samples[2..<130].allSatisfy { $0 == 0 })
        XCTAssertEqual(Array(samples.suffix(2)), [99, 99])
    }
    func testSineFrequencyAmplitudeAndSilence() {
        let fft = SpectrumFFT()
        let frequency = 48000.0 * 85 / 4096
        let sine = (0..<4096).map { Float(0.5 * sin(2 * Double.pi * frequency * Double($0) / 48000)) }
        let result = fft.spectrum(sine, sampleRate: 48000)
        XCTAssertEqual(result.dominantFrequency, frequency, accuracy: 0.001)
        XCTAssertEqual(result.db.max()!, -6.0206, accuracy: 0.1)
        XCTAssertTrue(fft.spectrum([Float](repeating: 0, count: 4096), sampleRate: 48000).db.allSatisfy { $0 == -120 })
    }

    func testCircularFFTMatchesBuild7AcrossWrapsAndSampleRateChanges() {
        let fft = SpectrumFFT(), reference = ReferenceSpectrumFFT()
        let samples: [Float] = (0..<4096).map { i -> Float in
            let first = 0.4 * sin(Double(i) * 0.13)
            let second = 0.17 * cos(Double(i) * 0.317)
            let noise = Double(i % 97 - 48) / 500
            return Float(first + second + noise)
        }
        for rate in [8000.0, 44100, 48000, 96000, 192000, 384000, 8000, 48000] {
            for cursor in [0, 1, 15, 1023, 2047, 4095] {
                let ordered = (0..<4096).map { samples[(cursor + $0) % 4096] }
                let expected = reference.spectrum(ordered, sampleRate: rate)
                let actual = fft.spectrum(samples, startingAt: cursor, sampleRate: rate)
                XCTAssertEqual(actual.frequencies, expected.frequencies)
                XCTAssertEqual(actual.db, expected.db, "rate=\(rate), cursor=\(cursor)")
                XCTAssertEqual(actual.dominantFrequency, expected.dominantFrequency)
            }
        }
    }

    func testCachedSpectrumDoesNotMutateRetainedFrames() {
        let fft = SpectrumFFT()
        let samples = (0..<4096).map { Float(sin(Double($0) * 0.1)) }
        let first = fft.spectrum(samples, sampleRate: 8000)
        let savedFrequencies = first.frequencies, savedDB = first.db
        _ = fft.spectrum(samples, startingAt: 4095, sampleRate: 192000)
        _ = fft.spectrum(samples, sampleRate: 8000)
        XCTAssertEqual(first.frequencies, savedFrequencies)
        XCTAssertEqual(first.db, savedDB)
        XCTAssertEqual(first.frequencies.last!, 3992, accuracy: 0.00001)
    }

    func testAnalyzerBuildsItsFirstLazyWindowFromTheLatestSamples() {
        let samples = (0..<5000).map { Float(sin(Double($0) * 0.13) * 0.4) }
        let audio = SpectrumInputFixture(samples: samples)
        let analyzer = SpectrumAnalyzer(), reference = ReferenceSpectrumFFT()
        let expectedInput = reference.spectrum(Array(samples.suffix(4096)), sampleRate: 48000)
        let expectedOutput = reference.spectrum(Array(samples.suffix(4096)).map { $0 * 0.7 }, sampleRate: 48000)
        let received = expectation(description: "First real analyzer window")
        analyzer.start(audio: audio, sampleRate: 48000) { frame in
            XCTAssertEqual(frame.frequencies, expectedInput.frequencies)
            XCTAssertEqual(frame.inputDB, expectedInput.db)
            XCTAssertEqual(frame.equalizedDB, expectedOutput.db)
            received.fulfill()
        }
        wait(for: [received], timeout: 3)
        analyzer.stop()
    }

    func testEqualizerSettingsPersistenceAndInvalidFallback() {
        let name = "MicRelay.EQTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var value = EqualizerSettings()
        value.enabled = true
        value.bands[2].filter = .notch
        value.bands[2].frequency = 1234
        value.save(in: defaults)
        XCTAssertEqual(EqualizerSettings.load(in: defaults), value)
        value.bands[2].q = -1
        value.save(in: defaults)
        XCTAssertEqual(EqualizerSettings.load(in: defaults), EqualizerSettings())
    }
}

// Unit-test input only; no synthetic signal is installed in the app or displayed in UI tests.
private final class SpectrumInputFixture: MRRealtimeAudio {
    private let samples: [Float]
    private var position = 0
    init(samples: [Float]) { self.samples = samples; super.init() }
    override func readAnalysisInput(_ input: UnsafeMutablePointer<Float>, output: UnsafeMutablePointer<Float>, capacity: UInt) -> UInt {
        let count = min(Int(capacity), samples.count - position)
        for i in 0..<count { input[i] = samples[position + i]; output[i] = input[i] * 0.7 }
        position += count
        return UInt(count)
    }
}

// Build 7 reference, deliberately unchanged: tests compare the new circular path with its output.
private final class ReferenceSpectrumFFT {
    private let count = 4096
    private let setup = vDSP_create_fftsetup(12, FFTRadix(kFFTRadix2))!
    private var window = [Float](repeating: 0, count: 4096)
    private var work = [Float](repeating: 0, count: 4096)
    private var real = [Float](repeating: 0, count: 2048)
    private var imaginary = [Float](repeating: 0, count: 2048)
    private var power = [Float](repeating: 0, count: 2048)

    init() { vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_DENORM)) }
    deinit { vDSP_destroy_fftsetup(setup) }

    func spectrum(_ samples: [Float], sampleRate: Double) -> (frequencies: [Double], db: [Float], dominantFrequency: Double) {
        precondition(samples.count == count && sampleRate > 0)
        vDSP_vmul(samples, 1, window, 1, &work, 1, vDSP_Length(count))
        for i in 0..<2048 { real[i] = work[2 * i]; imaginary[i] = work[2 * i + 1] }
        real.withUnsafeMutableBufferPointer { r in
            imaginary.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, 12, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, 2048)
            }
        }
        let maxHz = min(20000, sampleRate * 0.499)
        let frequencies = (0..<128).map { 20 * pow(maxHz / 20, Double($0) / 127) }
        var db = [Float](repeating: -120, count: 128)
        for i in 0..<128 {
            let low = i == 0 ? 20 : sqrt(frequencies[i - 1] * frequencies[i])
            let high = i == 127 ? maxHz : sqrt(frequencies[i] * frequencies[i + 1])
            let center = max(1, min(2047, Int((frequencies[i] * Double(count) / sampleRate).rounded())))
            let start = max(1, min(2047, Int(ceil(low * Double(count) / sampleRate))))
            let end = max(1, min(2047, Int(floor(high * Double(count) / sampleRate))))
            let value = start <= end ? power[start...end].max()! : power[center]
            let amplitude = sqrt(max(0, value)) * (2 / Float(count))
            db[i] = max(-120, 20 * log10(max(amplitude, 1e-6)))
        }
        let peakIndex = (1..<2048).max { power[$0] < power[$1] } ?? 1
        return (frequencies, db, Double(peakIndex) * sampleRate / Double(count))
    }
}
