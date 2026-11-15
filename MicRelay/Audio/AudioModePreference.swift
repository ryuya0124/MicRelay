// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import AVFAudio
enum AudioModePreference: String, Codable, CaseIterable, Identifiable {
    case automatic, standard, measurement, manual
    var id: String { rawValue }
    var title: String {
        switch self { case .manual: return String(localized: "audio.mode.manual", defaultValue: "完全手動"); case .automatic: return String(localized: "audio.mode.automatic", defaultValue: "自動"); case .standard: return String(localized: "audio.mode.standard", defaultValue: "標準"); case .measurement: return String(localized: "audio.mode.measurement", defaultValue: "測定") }
    }
    var sessionMode: AVAudioSession.Mode { self == .measurement ? .measurement : .default }
    static func load(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: "audioModePreference") ?? "") ?? .automatic
    }
}
