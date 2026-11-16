// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import SwiftUI

struct LicenseView: View {
    @State private var dependencies: [ThirdPartyLicense] = ThirdPartyLicense.load()
    @State private var showsRequestedDependency = false

    private var requestedDependency: ThirdPartyLicense? {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--show-dependency-license=") }) else { return nil }
        return dependencies.first { $0.name == String(argument.dropFirst("--show-dependency-license=".count)) }
    }

    private var license: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "MIT License · Copyright © 2026 ryuya"
        }
        return text
    }

    var body: some View {
        List {
            Section("MicRelay") {
                NavigationLink("MIT License · Copyright © 2026 ryuya") {
                    LicenseTextView(title: "MicRelay", text: license)
                }
                Link(String(localized: "licenses.github", defaultValue: "GitHub ソースコード"), destination: URL(string: "https://github.com/ryuya0124/MicRelay")!)
            }
            Section(String(localized: "licenses.frameworks", defaultValue: "実行時のフレームワーク")) {
                Text(String(localized: "licenses.frameworks_help", defaultValue: "SwiftUI、AVFAudio、AudioToolbox、Accelerate、AVKit、MediaPlayer、Foundation、ScreenCaptureKit、Photosなど、OSが提供するApple標準フレームワークを使用しています。第三者製の実行時ライブラリは同梱していません。"))
                    .font(.footnote)
            }
            Section {
                ForEach(dependencies) { dependency in
                    NavigationLink {
                        LicenseTextView(title: dependency.name, text: dependency.text, homepage: dependency.homepage)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(dependency.name + " " + dependency.version)
                            Text(dependency.licenses.isEmpty ? String(localized: "licenses.see_text", defaultValue: "ライセンス本文参照") : dependency.licenses.joined(separator: " / "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(String(localized: "licenses.dependencies", defaultValue: "開発・署名ツールの依存関係（\(dependencies.count)件）"))
            } footer: {
                Text(String(localized: "licenses.dependencies_help", defaultValue: "Fastlane・Bundlerなどの開発用パッケージです。アプリの音声処理には組み込まれていません。各項目に著作権表記とライセンス本文を収録しています。"))
            }
        }
        .navigationTitle(String(localized: "licenses.title", defaultValue: "ライセンス"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("licensesScreen")
        .navigationDestination(isPresented: $showsRequestedDependency) {
            if let dependency = requestedDependency {
                LicenseTextView(title: dependency.name, text: dependency.text, homepage: dependency.homepage)
            }
        }
        .task {
            #if DEBUG
            if requestedDependency != nil {
                try? await Task.sleep(for: .milliseconds(500))
                showsRequestedDependency = true
            }
            #endif
        }
    }
}

private struct LicenseTextView: View {
    let title: String
    let text: String
    var homepage: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let url = URL(string: homepage), ["https", "http"].contains(url.scheme ?? "") {
                    Link(homepage, destination: url).font(.footnote)
                }
                Text(text).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            }.padding(22).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
