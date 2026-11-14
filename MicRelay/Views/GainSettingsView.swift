// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import SwiftUI

struct GainSettingsView: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "gain.slider_limit", defaultValue: "スライダーの上限")) {
                    HStack {
                        TextField(String(localized: "gain.maximum", defaultValue: "上限"), text: $value)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("gainLimitInput")
                        Text("%").foregroundStyle(.secondary)
                    }
                    Text(String(localized: "gain.limit_help", defaultValue: "任意の上限を入力できます。現在のゲインと上限は、この端末に保存されます。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text(String(localized: "gain.clipping_help", defaultValue: "音声のフルスケールを超える増幅分はクリップします。"))
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(String(localized: "gain.limit", defaultValue: "ゲイン上限"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel", defaultValue: "キャンセル")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save", defaultValue: "保存")) {
                        if let percent = MonitorPreferences.parseGainLimit(value), model.setGainLimit(percent: percent) { dismiss() }
                        else { error = String(localized: "gain.error.invalid", defaultValue: "0より大きい有効な数値を入力してください。") }
                    }.accessibilityIdentifier("saveGainLimit")
                }
            }
            .onAppear { value = MonitorPreferences.gainLimitInput(model.gainLimit) }
        }
    }
}
