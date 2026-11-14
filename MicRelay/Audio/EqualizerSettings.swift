// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import Foundation

enum EqualizerFilter: Int, Codable, CaseIterable, Identifiable {
    case peak, notch, highPass, lowPass, bandStop, bandPass
    var id: Int { rawValue }
    var usesFrequencyRange: Bool { self == .bandStop || self == .bandPass }
    var title: String {
        switch self {
        case .peak: return String(localized: "eq.gain", defaultValue: "増減")
        case .notch: return String(localized: "eq.filter.notch", defaultValue: "ノッチ（帯域除去）")
        case .highPass: return String(localized: "eq.filter.high_pass", defaultValue: "ローカット")
        case .lowPass: return String(localized: "eq.filter.low_pass", defaultValue: "ハイカット")
        case .bandStop: return String(localized: "eq.filter.band_stop", defaultValue: "バンドストップ（範囲をカット）")
        case .bandPass: return String(localized: "eq.filter.band_pass", defaultValue: "バンドパス（範囲だけ通す）")
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
    var lowerFrequency: Double
    var upperFrequency: Double

    init(id: Int, frequency: Double, gainDB: Double = 0, q: Double = 1, filter: EqualizerFilter = .peak,
         enabled: Bool = true, lowerFrequency: Double? = nil, upperFrequency: Double? = nil) {
        self.id = id; self.frequency = frequency; self.gainDB = gainDB; self.q = q
        self.filter = filter; self.enabled = enabled
        self.lowerFrequency = lowerFrequency ?? min(19999, max(20, frequency / 2))
        self.upperFrequency = upperFrequency ?? min(20000, max(self.lowerFrequency + 1, frequency * 2))
    }

    private enum CodingKeys: String, CodingKey {
        case id, frequency, gainDB, q, filter, enabled, lowerFrequency, upperFrequency
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let filter = try values.decode(EqualizerFilter.self, forKey: .filter)
        // Old settings have no range bounds. Range filters always require both bounds.
        let lower = try filter.usesFrequencyRange ? values.decode(Double.self, forKey: .lowerFrequency) : values.decodeIfPresent(Double.self, forKey: .lowerFrequency)
        let upper = try filter.usesFrequencyRange ? values.decode(Double.self, forKey: .upperFrequency) : values.decodeIfPresent(Double.self, forKey: .upperFrequency)
        self.init(id: try values.decode(Int.self, forKey: .id), frequency: try values.decode(Double.self, forKey: .frequency),
            gainDB: try values.decode(Double.self, forKey: .gainDB), q: try values.decode(Double.self, forKey: .q),
            filter: filter, enabled: try values.decode(Bool.self, forKey: .enabled), lowerFrequency: lower, upperFrequency: upper)
    }

    var native: [String: NSNumber] {
        ["frequency": NSNumber(value: frequency), "gainDB": NSNumber(value: gainDB),
         "q": NSNumber(value: q), "type": NSNumber(value: filter.rawValue), "enabled": NSNumber(value: enabled),
         "lowerFrequency": NSNumber(value: lowerFrequency), "upperFrequency": NSNumber(value: upperFrequency)]
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
            && $0.gainDB.isFinite && (-36...24).contains($0.gainDB) && $0.q.isFinite && (0.2...30).contains($0.q)
            && $0.lowerFrequency.isFinite && $0.upperFrequency.isFinite
            && (20...20000).contains($0.lowerFrequency) && (20...20000).contains($0.upperFrequency)
            && $0.upperFrequency - $0.lowerFrequency >= 1 }
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
