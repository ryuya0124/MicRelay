// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import Foundation

enum MonitorPreferences {
    static let gainKey = "monitorGain"
    static let gainLimitKey = "monitorGainLimit"

    static func gain(in defaults: UserDefaults = .standard) -> Double {
        guard let number = defaults.object(forKey: gainKey) as? NSNumber else { return min(0.5, gainLimit(in: defaults)) }
        return clampedGain(number.doubleValue, limit: gainLimit(in: defaults))
    }

    static func saveGain(_ value: Double, in defaults: UserDefaults = .standard) {
        defaults.set(clampedGain(value, limit: gainLimit(in: defaults)), forKey: gainKey)
    }

    static func gainLimit(in defaults: UserDefaults = .standard) -> Double {
        // Preserve gains saved before a user-defined limit existed, while new installs start at 200%.
        guard let stored = defaults.object(forKey: gainLimitKey) as? NSNumber else {
            let oldGain = (defaults.object(forKey: gainKey) as? NSNumber)?.doubleValue ?? 0
            return oldGain.isFinite ? max(2, oldGain) : 2
        }
        let value = stored.doubleValue
        return value.isFinite && value > 0 ? value : 2
    }

    @discardableResult
    static func saveGainLimit(_ value: Double, in defaults: UserDefaults = .standard) -> Bool {
        guard value.isFinite, value > 0 else { return false }
        let existingGain = gain(in: defaults)
        defaults.set(value, forKey: gainLimitKey)
        saveGain(existingGain, in: defaults)
        return true
    }

    private static func clampedGain(_ value: Double, limit: Double) -> Double {
        value.isFinite ? min(limit, max(0, value)) : min(0.5, limit)
    }

    static func percentLabel(_ gain: Double) -> String {
        let percent = gain * 100
        return String(format: percent >= 1_000_000 ? "%.4g%%" : "%.0f%%", percent)
    }
}
