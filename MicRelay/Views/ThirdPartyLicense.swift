// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import Foundation

struct ThirdPartyLicense: Decodable, Identifiable {
    let name: String
    let version: String
    let licenses: [String]
    let homepage: String
    let scope: String
    let text: String
    let sha256: String
    var id: String { name + "-" + version }

    static func load() -> [ThirdPartyLicense] {
        guard let url = Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let notices = try? JSONDecoder().decode([ThirdPartyLicense].self, from: data) else { return [] }
        return notices
    }
}
