// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation

enum StartupIOProbe {
    static let comparisonBudget: TimeInterval = 4
    static let frames: [Double] = [16, 8, 32, 1]
    static let recoveryFrames: [Double] = [64, 128, 256, 512, 1024, 2048]
    static func canCompare(elapsed: TimeInterval, hasStable: Bool) -> Bool {
        !hasStable || elapsed < comparisonBudget
    }
    static func extraRates(current: Double, fixed: Double?) -> [Double] {
        guard fixed == nil else { return [] }
        return [48000.0, 96000, 44100].filter { abs($0 - current) >= 0.5 }.prefix(2).map { $0 }
    }
}

struct IOProfileCache {
    struct Entry: Codable, Equatable {
        let measurement: BufferPreferenceMeasurement
        let floor: Double?
        let modes: [ModeLatencyMeasurement]
        var usedAt: Date = Date()
        var isValid: Bool {
            measurement.isStable && (floor.map { $0.isFinite && $0 > 0 } ?? true) && modes.allSatisfy(\.isValid)
        }
    }
    private var entries: [String: Entry] = [:]
    private let url: URL?
    init(url: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("validated-io-v1.json")) {
        self.url = url
        if let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
           let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data), decoded.count <= 16 {
            entries = decoded.filter { $0.value.isValid }
        }
    }
    subscript(key: String) -> Entry? { entries[key] }
    mutating func put(_ entry: Entry, for key: String) {
        guard entry.isValid else { return }
        var entry = entry; entry.usedAt = Date(); entries[key] = entry
        while entries.count > 16, let oldest = entries.min(by: { $0.value.usedAt < $1.value.usedAt })?.key { entries.removeValue(forKey: oldest) }
        save()
    }
    mutating func remove(_ key: String) { entries.removeValue(forKey: key); save() }
    private func save() {
        guard let url, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
