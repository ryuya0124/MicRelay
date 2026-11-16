// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation

struct ScreenRecordingSettings: Codable, Equatable {
    static let preferenceKey = "excludeMonitorAudioFromRecording"
    var excludesMonitorAudio = true

    static func load(in defaults: UserDefaults = .standard) -> Self {
        .init(excludesMonitorAudio: defaults.object(forKey: preferenceKey) == nil || defaults.bool(forKey: preferenceKey))
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(excludesMonitorAudio, forKey: Self.preferenceKey)
    }
}
