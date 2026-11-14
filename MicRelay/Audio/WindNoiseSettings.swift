// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation

struct WindNoiseSettings: Codable, Equatable {
    var enabled = false
    var cutoff: Double = 120
    static let key = "windNoiseSettings.v1"
    static let cutoffRange = 60.0...600.0
    var isValid: Bool { cutoff.isFinite && Self.cutoffRange.contains(cutoff) }
    static func load(in defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return .init() }
        return value
    }
    func save(in defaults: UserDefaults = .standard) {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
