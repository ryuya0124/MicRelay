// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation

enum TapDetectionSource: String, Codable, CaseIterable, Identifiable {
    case beforeFilters, afterFilters
    var id: String { rawValue }
    var title: String {
        switch self {
        case .beforeFilters: return String(localized: "tap.source.before", defaultValue: "フィルター前の入力")
        case .afterFilters: return String(localized: "tap.source.after", defaultValue: "フィルター後の音")
        }
    }
}

struct TapGateSettings: Codable, Equatable {
    var enabled = false
    var duration: Double = 0.012
    var minimumDB: Double = -42
    var riseDB: Double = 16
    var detectionSource: TapDetectionSource = .afterFilters
    static let key = "tapGateSettings.v1"
    static let durationRange = 0.001...1.0
    static let minimumRange = -90.0...0.0
    static let riseRange = 3.0...30.0
    var isValid: Bool {
        duration.isFinite && Self.durationRange.contains(duration) &&
        minimumDB.isFinite && Self.minimumRange.contains(minimumDB) &&
        riseDB.isFinite && Self.riseRange.contains(riseDB)
    }
    static func load(in defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return .init() }
        return value
    }
    func save(in defaults: UserDefaults = .standard) {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

extension TapGateSettings {
    private enum CodingKeys: String, CodingKey { case enabled, duration, minimumDB, riseDB, detectionSource }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        duration = try container.decode(Double.self, forKey: .duration)
        minimumDB = try container.decode(Double.self, forKey: .minimumDB)
        riseDB = try container.decode(Double.self, forKey: .riseDB)
        detectionSource = try container.decodeIfPresent(TapDetectionSource.self, forKey: .detectionSource) ?? .afterFilters
    }
}
