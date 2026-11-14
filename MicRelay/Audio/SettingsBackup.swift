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

    init(gain: Double, gainLimit: Double, equalizer: EqualizerSettings, backgroundEnabled: Bool, selectedInput: String, audioMode: AudioModePreference = .automatic) {
        format = "net.ryuya-dev.MicRelay.settings"; version = 1; createdAt = Date()
        self.gain = gain; self.gainLimit = gainLimit; self.equalizer = equalizer
        self.backgroundEnabled = backgroundEnabled; self.selectedInput = selectedInput
        self.audioMode = audioMode
    }

    func validated() throws -> Self {
        guard format == "net.ryuya-dev.MicRelay.settings", version == 1 else { throw BackupError.version }
        guard gain.isFinite, gainLimit.isFinite, gain >= 0, gainLimit > 0, gain <= gainLimit,
              !selectedInput.isEmpty, selectedInput.utf8.count <= 1024,
              equalizer.isValid else { throw BackupError.values }
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
        case .version: return "このバックアップ形式・バージョンには対応していません。"
        case .values: return "設定値が正しくないため復元できません。"
        case .size: return "バックアップファイルが大きすぎます。"
        }
    }
}
