// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import Accelerate
import Foundation

struct SpectrumFrame: Sendable {
    var frequencies: [Double]
    var inputDB: [Float]
    var equalizedDB: [Float]
    var dominantFrequency: Double
    var sampleRate: Double
    var maximumFrequency: Double { frequencies.last ?? 20000 }
}

/// All FFT/window work stays on a non-audio queue. The producer never waits for this consumer.
final class SpectrumAnalyzer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "net.ryuya-dev.MicRelay.spectrum", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var audio: MRRealtimeAudio?
    private let fft = SpectrumFFT()
    private var input = [Float](repeating: 0, count: 4096)
    private var output = [Float](repeating: 0, count: 4096)
    private var ringInput = [Float](repeating: 0, count: 4096)
    private var ringOutput = [Float](repeating: 0, count: 4096)
    private var cursor = 0
    private var filled = 0

    func start(audio: MRRealtimeAudio, sampleRate: Double, onFrame: @escaping @Sendable (SpectrumFrame) -> Void) {
        queue.async { [self] in
            timer?.cancel()
            self.audio?.analysisEnabled = false
            self.audio = audio
            cursor = 0; filled = 0
            audio.discardAnalysisSamples()
            audio.analysisEnabled = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                while true {
                    let read = input.withUnsafeMutableBufferPointer { inputPointer in
                        self.output.withUnsafeMutableBufferPointer { outputPointer in
                            Int(audio.readAnalysisInput(inputPointer.baseAddress!, output: outputPointer.baseAddress!, capacity: 4096))
                        }
                    }
                    if read == 0 { break }
                    for i in 0..<read {
                        ringInput[cursor] = input[i]; ringOutput[cursor] = output[i]
                        cursor = (cursor + 1) % 4096
                    }
                    filled = min(4096, filled + read)
                }
                guard filled == 4096 else { return }
                var orderedInput = [Float](repeating: 0, count: 4096)
                var orderedOutput = orderedInput
                for i in 0..<4096 {
                    orderedInput[i] = ringInput[(cursor + i) % 4096]
                    orderedOutput[i] = ringOutput[(cursor + i) % 4096]
                }
                let first = fft.spectrum(orderedInput, sampleRate: sampleRate)
                let second = fft.spectrum(orderedOutput, sampleRate: sampleRate)
                onFrame(SpectrumFrame(frequencies: first.frequencies, inputDB: first.db,
                    equalizedDB: second.db, dominantFrequency: first.dominantFrequency, sampleRate: sampleRate))
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel(); timer = nil
            audio?.analysisEnabled = false
            audio = nil
        }
    }

    deinit { timer?.cancel(); audio?.analysisEnabled = false }
}

/// A reusable Hann-windowed 4096-point real FFT. Also used by deterministic signal tests.
final class SpectrumFFT {
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
