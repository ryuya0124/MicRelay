// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation

struct SettingsBackup: Codable, Equatable {
    let format: String
    let version: Int
    let createdAt: Date
    let gain: Double
    let gainLimit: Double
    let equalizer: EqualizerSettings
    let backgroundEnabled: Bool
    let selectedInput: String
    let audioMode: AudioModePreference?
    let windNoise: WindNoiseSettings?
    let manualAudio: ManualAudioSettings?
    let tapGate: TapGateSettings?
    let screenRecording: ScreenRecordingSettings?

    init(gain: Double, gainLimit: Double, equalizer: EqualizerSettings, backgroundEnabled: Bool, selectedInput: String, audioMode: AudioModePreference = .automatic, windNoise: WindNoiseSettings = .init(), manualAudio: ManualAudioSettings = .init(), tapGate: TapGateSettings = .init(), screenRecording: ScreenRecordingSettings = .init()) {
        format = "net.ryuya-dev.MicRelay.settings"; version = 5; createdAt = Date()
        self.gain = gain; self.gainLimit = gainLimit; self.equalizer = equalizer
        self.backgroundEnabled = backgroundEnabled; self.selectedInput = selectedInput
        self.audioMode = audioMode; self.windNoise = windNoise; self.manualAudio = manualAudio
        self.tapGate = tapGate
        self.screenRecording = screenRecording
    }

    func validated() throws -> Self {
        guard format == "net.ryuya-dev.MicRelay.settings", (1...5).contains(version),
              (version >= 5 || screenRecording == nil),
              (version >= 4 || tapGate == nil),
              (version >= 3 || (manualAudio == nil && audioMode != .manual)),
              version >= 2 || (windNoise == nil && !equalizer.bands.contains(where: { $0.filter.usesFrequencyRange })) else { throw BackupError.version }
        guard gain.isFinite, gainLimit.isFinite, gain >= 0, gainLimit > 0, gain <= gainLimit,
              !selectedInput.isEmpty, selectedInput.utf8.count <= 1024,
              equalizer.isValid, windNoise?.isValid != false, manualAudio?.isValid != false, tapGate?.isValid != false,
              audioMode != .manual || manualAudio != nil else { throw BackupError.values }
        return self
    }
    func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576 else { throw BackupError.size }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data).validated()
    }
}
enum BackupError: LocalizedError {
    case version, values, size
    var errorDescription: String? {
        switch self {
        case .version: return String(localized: "backup.error.version", defaultValue: "このバックアップ形式・バージョンには対応していません。")
        case .values: return String(localized: "backup.error.values", defaultValue: "設定値が正しくないため復元できません。")
        case .size: return String(localized: "backup.error.size", defaultValue: "バックアップファイルが大きすぎます。")
        }
    }
}
