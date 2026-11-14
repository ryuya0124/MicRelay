// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import Foundation

enum EqualizerFilter: Int, Codable, CaseIterable, Identifiable {
    case peak, notch, highPass, lowPass
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .peak: return "増減"
        case .notch: return "ノッチ（帯域除去）"
        case .highPass: return "ローカット"
        case .lowPass: return "ハイカット"
        }
    }
}

struct EqualizerBand: Codable, Equatable, Identifiable {
    var id: Int
    var frequency: Double
    var gainDB: Double = 0
    var q: Double = 1
    var filter: EqualizerFilter = .peak
    var enabled = true

    var native: [String: NSNumber] {
        ["frequency": NSNumber(value: frequency), "gainDB": NSNumber(value: gainDB),
         "q": NSNumber(value: q), "type": NSNumber(value: filter.rawValue), "enabled": NSNumber(value: enabled)]
    }
}

struct EqualizerSettings: Codable, Equatable {
    var enabled = false
    var bands: [EqualizerBand] = [80.0, 250, 800, 2500, 6000, 12000].enumerated().map {
        EqualizerBand(id: $0.offset, frequency: $0.element)
    }

    static let key = "equalizerSettings.v1"
    var isValid: Bool {
        bands.count == 6 && Set(bands.map(\.id)) == Set(0..<6) &&
        bands.allSatisfy { $0.frequency.isFinite && (20...20000).contains($0.frequency)
            && $0.gainDB.isFinite && (-36...24).contains($0.gainDB) && $0.q.isFinite && (0.2...30).contains($0.q) }
    }
    static func load(in defaults: UserDefaults = .standard) -> EqualizerSettings {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data),
              value.isValid else { return .init() }
        return value
    }
    func save(in defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}
