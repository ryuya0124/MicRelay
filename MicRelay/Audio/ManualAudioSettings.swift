// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation

struct ManualAudioSettings: Codable, Equatable {
    var frames: UInt32 = 16
    var sampleRate: Double = 48000
    var mode: AudioModePreference = .standard
    static let key = "manualAudioSettings.v1"
    var isValid: Bool {
        frames > 0 && sampleRate.isFinite && sampleRate > 0 &&
        bufferDuration.isFinite && bufferDuration > 0 && [.standard, .measurement].contains(mode)
    }
    var bufferDuration: Double { Double(frames) / sampleRate }
    var summary: String { "\(frames) frames · \(String(format: "%.9g", locale: .current, sampleRate)) Hz" }
    var verificationSummary: String { "\(summary) · I/O \(Self.durationLabel(bufferDuration))" }
    static func durationLabel(_ seconds: Double) -> String { String(format: "%.3f ms", locale: .current, seconds * 1000) }
    static let frameChoices: [UInt32] = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096]
    static let sampleRateChoices: [Double] = [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000]
    // Reuse the static arrays for ordinary settings. Only an imported nonstandard value needs a new list.
    var frameOptions: [UInt32] {
        guard frames > 0, !Self.frameChoices.contains(frames) else { return Self.frameChoices }
        return (Self.frameChoices + [frames]).sorted()
    }
    var sampleRateOptions: [Double] {
        guard sampleRate.isFinite, sampleRate > 0, !Self.sampleRateChoices.contains(sampleRate) else { return Self.sampleRateChoices }
        return (Self.sampleRateChoices + [sampleRate]).sorted()
    }
    @discardableResult
    static func commitVerified(_ observation: ManualIOObservation, in defaults: UserDefaults = .standard) -> Bool {
        guard observation.accepted, observation.request.isValid else { return false }
        observation.request.save(in: defaults)
        return true
    }
    static func load(in defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey:key), let value = try? JSONDecoder().decode(Self.self,from:data), value.isValid else { return .init() }
        return value
    }
    func save(in defaults: UserDefaults = .standard) {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data,forKey:Self.key)
    }
}

struct ManualIOApplication: Equatable {
    enum State { case inactive, pending, matched, different }
    let state: State
    let framesMatch: Bool
    let rateMatches: Bool
    let modeMatches: Bool
    init(request: ManualAudioSettings, running: Bool, renderedFrames: UInt64,
         actualRate: Double, minimumFrames: UInt32, maximumFrames: UInt32,
         ioDuration: Double, actualMode: AudioModePreference?) {
        // Tolerate floating-point representation only; a rounded nearby setting is a rejection.
        rateMatches = actualRate.isFinite && abs(actualRate-request.sampleRate) < 0.000001
        framesMatch = minimumFrames == request.frames && maximumFrames == request.frames &&
            ioDuration.isFinite && abs(ioDuration*actualRate-Double(request.frames)) < 0.000001
        modeMatches = actualMode == request.mode
        if !running { state = .inactive }
        else if minimumFrames == 0 || actualRate <= 0 || !actualRate.isFinite { state = .pending }
        else if !framesMatch || !rateMatches || !modeMatches { state = .different }
        else { state = renderedFrames > 0 ? .matched : .pending }
    }
}

struct ManualIOObservation: Equatable {
    let request: ManualAudioSettings
    let sampleRate: Double
    let minimumFrames: UInt32
    let maximumFrames: UInt32
    let ioDuration: Double
    let mode: AudioModePreference?
    let renderedFrames: UInt64
    let misses: UInt64
    let renderError: Int32
    let duration: Double
    var application: ManualIOApplication {
        .init(request: request, running: true, renderedFrames: renderedFrames, actualRate: sampleRate,
            minimumFrames: minimumFrames, maximumFrames: maximumFrames, ioDuration: ioDuration, actualMode: mode)
    }
    var isStable: Bool {
        sampleRate.isFinite && sampleRate > 0 && duration.isFinite && duration > 0 &&
        Double(renderedFrames) >= sampleRate * duration * 0.8 && misses == 0 && renderError == 0
    }
    var accepted: Bool { application.state == .matched && isStable }
    var actualSummary: String { "\(minimumFrames)–\(maximumFrames) frames · \(String(format: "%.9g", locale: .current, sampleRate)) Hz · I/O \(ManualAudioSettings.durationLabel(ioDuration)) · \(mode?.title ?? "—")" }
}

enum ManualAudioApplyError: LocalizedError {
    case connection, permission, mismatch(ManualIOObservation), unstable
    var errorDescription: String? {
        switch self {
        case .connection: return String(localized: "manual.error.connection", defaultValue: "イヤホン・HDMI機器を接続するか、本体スピーカーを有効にしてから適用してください。")
        case .permission: return String(localized: "manual.error.permission", defaultValue: "設定の適用確認にはマイクへのアクセスが必要です。")
        case .mismatch(let observation):
            return String(localized: "manual.error.mismatch", defaultValue: "要求値と実際の値が一致しません。要求: \(observation.request.verificationSummary + " · " + observation.request.mode.title)。実際: \(observation.actualSummary)。")
        case .unstable: return String(localized: "manual.error.unstable", defaultValue: "要求した設定では安定した音声入力を確認できませんでした。")
        }
    }
}
