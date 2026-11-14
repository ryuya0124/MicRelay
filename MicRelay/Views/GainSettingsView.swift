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
                Section("スライダーの上限") {
                    HStack {
                        TextField("上限", text: $value)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("gainLimitInput")
                        Text("%").foregroundStyle(.secondary)
                    }
                    Text("任意の上限を入力できます。現在のゲインと上限は、この端末に保存されます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("音声のフルスケールを超える増幅分はクリップします。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("ゲイン上限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let text = value.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if let percent = Double(text), model.setGainLimit(percent: percent) { dismiss() }
                        else { error = "0より大きい有効な数値を入力してください。" }
                    }.accessibilityIdentifier("saveGainLimit")
                }
            }
            .onAppear { value = String(format: "%.12g", model.gainLimit * 100) }
        }
    }
}
