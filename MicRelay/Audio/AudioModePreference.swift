// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import AVFAudio
enum AudioModePreference: String, Codable, CaseIterable, Identifiable {
    case automatic, standard, measurement
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: return "自動"; case .standard: return "標準"; case .measurement: return "測定" }
    }
    var sessionMode: AVAudioSession.Mode { self == .measurement ? .measurement : .default }
    static func load(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: "audioModePreference") ?? "") ?? .automatic
    }
}
