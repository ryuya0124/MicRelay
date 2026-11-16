// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import SwiftUI

struct TapGateControls: View {
    @ObservedObject var model: MonitorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(String(localized: "tap.title", defaultValue: "タップ音ゲート"), isOn: binding(\.enabled))
                .font(.headline).accessibilityIdentifier("tapGateToggle")
            Text(String(localized: "tap.help", defaultValue: "音の立ち上がりから指定時間だけ通します。連打では次の立ち上がりから時間を延長します。タップ以外の急な音にも反応します。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.tapGate.enabled {
                Picker(String(localized: "tap.source.title", defaultValue: "検出に使う音"), selection: binding(\.detectionSource)) {
                    ForEach(TapDetectionSource.allCases) { source in Text(source.title).tag(source) }
                }.pickerStyle(.menu).accessibilityIdentifier("tapGateDetectionSource")
                Text(String(localized: "tap.source.help", defaultValue: "フィルター前は元のマイク音、フィルター後はEQ・風切り音低減で処理した音で判定します。出力はどちらもEQ・風切り音低減の設定に従います。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(String(localized: "tap.duration", defaultValue: "通す時間"))
                    Spacer()
                    TextField("ms", value: Binding(get: { model.tapGate.duration * 1000 }, set: { value in
                        guard value.isFinite else { return }
                        model.updateTapGate { $0.duration = min(1, max(0.001, value / 1000)) }
                    }), format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        .accessibilityLabel(String(localized: "tap.duration", defaultValue: "通す時間"))
                        .accessibilityIdentifier("tapGateDuration")
                    Text("ms").foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { log10(model.tapGate.duration * 1000) }, set: { value in
                    model.updateTapGate { $0.duration = (pow(10, value) * 10).rounded() / 10000 }
                }), in: 0...3)
                    .accessibilityLabel(String(localized: "tap.duration", defaultValue: "通す時間"))
                    .accessibilityIdentifier("tapGateDurationSlider")
                HStack {
                    Text(String(localized: "tap.minimum", defaultValue: "最小入力レベル"))
                    Spacer()
                    Text(String(format: "%.0f dBFS", locale: .current, model.tapGate.minimumDB)).monospacedDigit()
                        .accessibilityIdentifier("tapGateMinimumValue")
                }
                Slider(value: binding(\.minimumDB), in: TapGateSettings.minimumRange, step: 1)
                    .accessibilityLabel(String(localized: "tap.minimum", defaultValue: "最小入力レベル"))
                    .accessibilityIdentifier("tapGateMinimumSlider")
                HStack {
                    Text(String(localized: "tap.rise", defaultValue: "背景音との差"))
                    Spacer()
                    Text(String(format: "%.0f dB", locale: .current, model.tapGate.riseDB)).monospacedDigit()
                        .accessibilityIdentifier("tapGateRiseValue")
                }
                Slider(value: binding(\.riseDB), in: TapGateSettings.riseRange, step: 1)
                    .accessibilityLabel(String(localized: "tap.rise", defaultValue: "背景音との差"))
                    .accessibilityIdentifier("tapGateRiseSlider")
                Text(String(localized: "tap.adjustment_help", defaultValue: "拾いにくいときはレベルや差を下げ、雑音にも反応するときは上げます。時間を長くすると余韻や背景音も通りやすくなります。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.isRunning {
                    LabeledContent(String(localized: "tap.state", defaultValue: "ゲート"), value: model.tapGateOpen
                        ? String(localized: "tap.open", defaultValue: "開いています") : String(localized: "tap.waiting", defaultValue: "待機中"))
                    LabeledContent(String(localized: "tap.detections", defaultValue: "検出回数"), value: String(model.tapGateDetections))
                        .monospacedDigit().accessibilityIdentifier("tapGateDetections")
                }
                Text(String(localized: "tap.latency_help", defaultValue: "先読みなしで、しきい値を超えたところから通します。小さい立ち上がりは欠ける場合があります。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
    private func binding<Value>(_ path: WritableKeyPath<TapGateSettings, Value>) -> Binding<Value> {
        Binding(get: { model.tapGate[keyPath: path] }, set: { value in model.updateTapGate { $0[keyPath: path] = value } })
    }
}
